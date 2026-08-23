import {
  ROUTE_CONTROL_FRACTIONS,
  WIND_GRID_SPAN_METRES,
  WIND_LEVELS_METRES_MSL,
  altitudeForFlightFraction,
  buildFlightPlanGpx,
  buildForecastPlanDocument,
  circlePolygon,
  forecastDistanceMetres,
  forecastLandingEnvelope,
  forecastRepresentativeRoute,
  interpolatedVectorAtPosition,
  openMeteoRequestUrl,
  normaliseOperationalBoundary,
  operationalBoundariesGeoJson,
  parseOpenMeteoForecast,
  planWindRouteToDestination,
} from "./planner-core.mjs";
import { applyThemePaint, themeStyle } from "./planner-theme.mjs";

// Keep the installed-app hand-off on its already-shipped associated domain.
// The planner itself is hosted at balloon-crumbs.pages.dev/planner.html.
const APP_LINK_ORIGIN = "https://balloon-crumbs.tailendcharlie.app";
const FORECAST_AREA_RADIUS_METRES = 750;
const INTENDED_AREA_RADIUS_METRES = 400;
const WIND_MARKER_SPACING_PIXELS = 150;
const DEFAULT_CENTER = [-2.5, 54.4];
const elements = Object.fromEntries(
  [
    "airspace-toggle",
    "add-altitude-boundary",
    "boundary-altitude-datum",
    "boundary-list",
    "boundary-lower-altitude",
    "boundary-name",
    "boundary-source",
    "boundary-status",
    "boundary-upper-altitude",
    "cancel-boundary",
    "clock",
    "code-result",
    "copy-code",
    "clear-destination",
    "departure-time",
    "draw-boundary-area",
    "draw-boundary-line",
    "forecast-distance",
    "forecast-summary",
    "forecast-validity",
    "flight-profile",
    "flight-profile-title",
    "finish-boundary",
    "generate-code",
    "generate-status",
    "launch-elevation",
    "launch-status",
    "landing-status",
    "max-altitude",
    "max-altitude-label",
    "max-ascent-rate",
    "max-ascent-rate-label",
    "max-descent-rate",
    "max-descent-rate-label",
    "map",
    "map-prompt",
    "map-status",
    "map-status-text",
    "open-in-app",
    "plan-code",
    "plan-expiry",
    "plan-name",
    "place-search",
    "place-search-form",
    "place-search-results",
    "place-search-status",
    "place-search-submit",
    "profile-duration",
    "profile-landing",
    "profile-limit",
    "profile-stages",
    "profile-start",
    "profile-window",
    "retry-map",
    "route-status",
    "set-landing",
    "set-launch",
    "theme-label",
    "theme-toggle",
    "use-location",
    "wind-altitude",
    "wind-altitude-label",
    "wind-status",
    "wind-toggle",
  ].map((id) => [id.replaceAll("-", "_"), document.getElementById(id)]),
);

const state = {
  map: null,
  mode: "launch",
  launch: null,
  field: null,
  track: null,
  forecastLanding: null,
  intendedLanding: null,
  manualLanding: false,
  landingEnvelope: [],
  landingCandidateCount: 0,
  routePlan: null,
  markers: {},
  windMarkers: [],
  forecastRequest: null,
  forecastGeneration: 0,
  placeSearchRequest: null,
  lastPlaceSearchAt: 0,
  mapTileFailures: 0,
  operationalBoundaries: [],
  operationalBoundaryDraft: null,
};

function setStatus(element, message, kind = "") {
  element.textContent = message;
  element.classList.toggle("error", kind === "error");
  element.classList.toggle("good", kind === "good");
}

function clearPlaceSearchResults() {
  elements.place_search_results.replaceChildren();
  elements.place_search_results.hidden = true;
}

function usePlaceSearchResult(result) {
  clearPlaceSearchResults();
  elements.place_search.value = result.displayName.split(",")[0];
  state.map.easeTo({
    center: [result.longitude, result.latitude],
    zoom: 14,
    duration: 700,
  });
  chooseLaunch({ lat: result.latitude, lng: result.longitude });
  setStatus(
    elements.place_search_status,
    `Launch set at ${result.displayName}. Check the pin against the map before flight.`,
    "good",
  );
}

function renderPlaceSearchResults(results) {
  clearPlaceSearchResults();
  for (const result of results) {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("aria-label", `Set launch at ${result.displayName}`);
    const name = document.createElement("strong");
    const detail = document.createElement("span");
    const parts = result.displayName.split(",").map((part) => part.trim());
    name.textContent = parts.shift() || result.displayName;
    detail.textContent = parts.join(", ");
    button.append(name, detail);
    button.addEventListener("click", () => usePlaceSearchResult(result));
    item.append(button);
    elements.place_search_results.append(item);
  }
  elements.place_search_results.hidden = false;
}

async function searchForPlace(event) {
  event.preventDefault();
  const query = elements.place_search.value.trim().replace(/\s+/g, " ");
  clearPlaceSearchResults();
  if (query.length < 2 || query.length > 100) {
    setStatus(elements.place_search_status, "Enter between 2 and 100 characters.", "error");
    return;
  }
  if (!state.map) {
    setStatus(elements.place_search_status, "Wait for the map to finish loading.", "error");
    return;
  }

  state.placeSearchRequest?.abort();
  const request = new AbortController();
  state.placeSearchRequest = request;
  elements.place_search_submit.disabled = true;
  setStatus(elements.place_search_status, `Searching for “${query}”…`);
  try {
    const delay = Math.max(0, 1_100 - (Date.now() - state.lastPlaceSearchAt));
    if (delay > 0) await new Promise((resolve) => window.setTimeout(resolve, delay));
    state.lastPlaceSearchAt = Date.now();
    const response = await fetch(`/geocode/v1/search?q=${encodeURIComponent(query)}`, {
      headers: { Accept: "application/json" },
      signal: request.signal,
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error || `Place search returned ${response.status}.`);
    const results = Array.isArray(body.results) ? body.results : [];
    if (results.length === 0) {
      setStatus(
        elements.place_search_status,
        `No UK places matched “${query}”. Try adding a nearby town or county.`,
        "error",
      );
      return;
    }
    renderPlaceSearchResults(results);
    setStatus(elements.place_search_status, "Choose a result to set it as the launch point.", "good");
  } catch (error) {
    if (error.name !== "AbortError") {
      setStatus(elements.place_search_status, `Place search failed: ${error.message}`, "error");
    }
  } finally {
    if (state.placeSearchRequest === request) {
      state.placeSearchRequest = null;
      elements.place_search_submit.disabled = !state.map;
    }
  }
}

function toLocalDateInputValue(date) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

function selectedSearchDay() {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(elements.departure_time.value);
  if (!match) throw new Error("Choose a valid flight date.");
  const dayStart = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  if (
    dayStart.getFullYear() !== Number(match[1]) ||
    dayStart.getMonth() !== Number(match[2]) - 1 ||
    dayStart.getDate() !== Number(match[3])
  ) {
    throw new Error("Choose a valid flight date.");
  }
  return dayStart;
}

function selectedDepartureSearch() {
  const dayStart = selectedSearchDay();
  const nextDay = new Date(
    dayStart.getFullYear(),
    dayStart.getMonth(),
    dayStart.getDate() + 1,
  );
  const today = new Date();
  const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const minimumDepartureOffsetMinutes =
    dayStart.getTime() === todayStart.getTime()
      ? Math.max(0, Math.ceil((today.getTime() - dayStart.getTime()) / 60_000))
      : 0;
  const maximumDepartureOffsetMinutes =
    Math.floor((nextDay.getTime() - dayStart.getTime()) / 60_000) - 1;
  if (minimumDepartureOffsetMinutes > maximumDepartureOffsetMinutes) {
    throw new Error("There are no remaining start times today. Choose tomorrow instead.");
  }
  return {
    dayStart,
    minimumDepartureOffsetMinutes,
    maximumDepartureOffsetMinutes,
    departureSearchStepMinutes: 120,
  };
}

function formatUtc(date) {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "UTC",
    weekday: "short",
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date) + " UTC";
}

function formatLocalDateTime(date) {
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "short",
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZoneName: "short",
  }).format(date);
}

function formatLocalTime(date) {
  return new Intl.DateTimeFormat("en-GB", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZoneName: "short",
  }).format(date);
}

function formatLocalDay(date) {
  return new Intl.DateTimeFormat("en-GB", {
    weekday: "long",
    day: "2-digit",
    month: "long",
  }).format(date);
}

function updateClock() {
  elements.clock.textContent = new Intl.DateTimeFormat("en-GB", {
    timeZone: "UTC",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date()) + " UTC";
}

function configureDepartureInput() {
  const now = new Date();
  const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  elements.departure_time.min = toLocalDateInputValue(now);
  elements.departure_time.max = toLocalDateInputValue(tomorrow);
  elements.departure_time.value = toLocalDateInputValue(now);
}

function normalizeStyleUrl(value) {
  if (/^https?:\/\//i.test(value)) {
    return value.replace(/^https?:\/\/[^/]+/i, window.location.origin);
  }
  return `${window.location.origin}${value.startsWith("/") ? "" : "/"}${value}`;
}

async function loadMapStyle() {
  const response = await fetch("/maps/styles/balloon-crumbs.json", {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) throw new Error("The basemap style is unavailable.");
  const style = await response.json();
  if (style.glyphs) style.glyphs = normalizeStyleUrl(style.glyphs);
  for (const source of Object.values(style.sources ?? {})) {
    if (Array.isArray(source.tiles)) source.tiles = source.tiles.map(normalizeStyleUrl);
  }
  return style;
}

function selectedMapTheme() {
  return elements.theme_toggle.checked ? "dark" : "light";
}

function applyMapTheme() {
  const themeName = selectedMapTheme();
  document.documentElement.dataset.theme = themeName;
  elements.theme_label.textContent = themeName === "dark" ? "Dark map" : "Light map";
  applyThemePaint(state.map, themeName);
}

function setMapStatus(message, kind = "", retry = false) {
  elements.map_status.hidden = false;
  elements.map_status.classList.toggle("error", kind === "error");
  elements.map_status.classList.toggle("good", kind === "good");
  elements.map_status_text.textContent = message;
  elements.retry_map.hidden = !retry;
}

function lineCollection(track) {
  if (!track || track.length < 2) return { type: "FeatureCollection", features: [] };
  return {
    type: "FeatureCollection",
    features: track.slice(1).map((point, index) => ({
      type: "Feature",
      properties: {
        altitude: (track[index].altitudeMetresMsl + point.altitudeMetresMsl) / 2,
      },
      geometry: {
        type: "LineString",
        coordinates: [
          [track[index].longitude, track[index].latitude],
          [point.longitude, point.latitude],
        ],
      },
    })),
  };
}

function polygonFeature(center, radiusMetres) {
  return {
    type: "FeatureCollection",
    features: center
      ? [
          {
            type: "Feature",
            properties: {},
            geometry: { type: "Polygon", coordinates: [circlePolygon(center, radiusMetres)] },
          },
        ]
      : [],
  };
}

function landingEnvelopeFeature(boundary) {
  if (!Array.isArray(boundary) || boundary.length === 0) {
    return { type: "FeatureCollection", features: [] };
  }
  const coordinates = boundary.map((point) => [point.longitude, point.latitude]);
  let geometry;
  if (coordinates.length >= 3) {
    geometry = { type: "Polygon", coordinates: [[...coordinates, coordinates[0]]] };
  } else if (coordinates.length === 2) {
    geometry = { type: "LineString", coordinates };
  } else {
    geometry = { type: "Point", coordinates: coordinates[0] };
  }
  return {
    type: "FeatureCollection",
    features: [{ type: "Feature", properties: {}, geometry }],
  };
}

function addPlannerLayers(map) {
  const firstSymbol = map.getStyle().layers.find((layer) => layer.type === "symbol")?.id;
  map.addSource("openaip-chart", {
    type: "raster",
    tiles: [`${window.location.origin}/maps/openaip/{z}/{x}/{y}.png`],
    tileSize: 256,
    attribution: "© OpenAIP contributors · CC BY-NC 4.0",
  });
  map.addLayer(
    {
      id: "openaip-chart",
      type: "raster",
      source: "openaip-chart",
      minzoom: 4,
      maxzoom: 14,
      paint: {
        "raster-opacity": selectedMapTheme() === "dark" ? 0.76 : 0.62,
        "raster-fade-duration": 180,
      },
    },
    firstSymbol,
  );

  map.addSource("landing-envelope", {
    type: "geojson",
    data: landingEnvelopeFeature(null),
  });
  map.addSource("operational-boundaries", {
    type: "geojson",
    data: operationalBoundariesGeoJson(state.operationalBoundaries),
  });
  map.addLayer({
    id: "operational-boundaries-fill",
    type: "fill",
    source: "operational-boundaries",
    filter: ["==", ["geometry-type"], "Polygon"],
    paint: { "fill-color": "#ff806c", "fill-opacity": 0.12 },
  });
  map.addLayer({
    id: "operational-boundaries-line",
    type: "line",
    source: "operational-boundaries",
    paint: {
      "line-color": "#ff806c",
      "line-width": 4,
      "line-dasharray": [2.5, 1.75],
    },
    layout: { "line-cap": "round", "line-join": "round" },
  });
  map.addLayer({
    id: "landing-envelope-fill",
    type: "fill",
    source: "landing-envelope",
    paint: { "fill-color": "#a78bfa", "fill-opacity": 0.14 },
  });
  map.addLayer({
    id: "landing-envelope-outline",
    type: "line",
    source: "landing-envelope",
    paint: {
      "line-color": "#a78bfa",
      "line-width": 2.5,
      "line-dasharray": [3, 2],
    },
  });

  map.addSource("forecast-track", { type: "geojson", data: lineCollection(null) });
  map.addLayer({
    id: "forecast-track-casing",
    type: "line",
    source: "forecast-track",
    paint: {
      "line-color": selectedMapTheme() === "dark" ? "#ffffff" : "#11151c",
      "line-width": 12,
      "line-opacity": 1,
    },
    layout: { "line-cap": "round", "line-join": "round" },
  });
  map.addLayer({
    id: "forecast-track",
    type: "line",
    source: "forecast-track",
    paint: {
      "line-color": [
        "interpolate",
        ["linear"],
        ["get", "altitude"],
        0,
        "#00c8ff",
        500,
        "#00f5a0",
        1000,
        "#ffe600",
        2000,
        "#ff245d",
      ],
      "line-width": 7,
      "line-opacity": 1,
    },
    layout: { "line-cap": "round", "line-join": "round" },
  });

  for (const [sourceId, color, opacity] of [
    ["forecast-area", "#ffc85a", 0.2],
    ["intended-area", "#65e19b", 0.22],
  ]) {
    map.addSource(sourceId, { type: "geojson", data: polygonFeature(null, 1) });
    map.addLayer({
      id: `${sourceId}-fill`,
      type: "fill",
      source: sourceId,
      paint: { "fill-color": color, "fill-opacity": opacity },
    });
    map.addLayer({
      id: `${sourceId}-outline`,
      type: "line",
      source: sourceId,
      paint: { "line-color": color, "line-width": 2.5, "line-dasharray": [2, 1.5] },
    });
  }
}

function markerElement(kind, label) {
  const element = document.createElement("div");
  element.className = `map-marker ${kind}`;
  const draggable =
    kind === "launch" || kind === "intended" || (kind === "forecast" && !state.manualLanding);
  if (draggable) element.classList.add("draggable");
  const dragInstruction = kind === "forecast" ? "drag to choose destination" : "drag to move";
  element.title = draggable ? `${label} — ${dragInstruction}` : label;
  element.setAttribute("aria-label", draggable ? `${label}; ${dragInstruction}` : label);
  return element;
}

function setMarker(kind, point, label) {
  state.markers[kind]?.remove();
  if (!point) {
    delete state.markers[kind];
    return;
  }
  const draggable =
    kind === "launch" || kind === "intended" || (kind === "forecast" && !state.manualLanding);
  const marker = new maplibregl.Marker({
    element: markerElement(kind, label),
    draggable,
  })
    .setLngLat([point.longitude, point.latitude])
    .addTo(state.map);
  if (kind === "launch") {
    marker.on("dragstart", () => {
      setStatus(elements.launch_status, "Moving launch point…");
    });
    marker.on("dragend", () => {
      chooseLaunch(marker.getLngLat(), { preserveDestination: true, fit: false });
    });
  } else if (kind === "intended") {
    marker.on("dragstart", () => {
      setStatus(elements.landing_status, "Moving destination…");
    });
    marker.on("dragend", () => {
      void chooseLanding(marker.getLngLat(), { fit: false });
    });
  } else if (kind === "forecast" && draggable) {
    marker.on("dragstart", () => {
      setStatus(elements.landing_status, "Drag the yellow endpoint to your intended destination…");
    });
    marker.on("dragend", () => {
      void chooseLanding(marker.getLngLat(), { fit: false });
    });
  }
  state.markers[kind] = marker;
}

function selectedWindLevel() {
  return WIND_LEVELS_METRES_MSL[Number(elements.wind_altitude.value)] ?? 500;
}

function clearWindMarkers() {
  for (const marker of state.windMarkers) marker.remove();
  state.windMarkers = [];
}

function windDisplayPositions() {
  const columns = state.field?.columns ?? [];
  const canvas = state.map?.getCanvas();
  if (!canvas || columns.length === 0) return [];
  const latitudes = columns.map((column) => column.position.latitude);
  const longitudes = columns.map((column) => column.position.longitude);
  const minimumLatitude = Math.min(...latitudes);
  const maximumLatitude = Math.max(...latitudes);
  const minimumLongitude = Math.min(...longitudes);
  const maximumLongitude = Math.max(...longitudes);
  const positions = [];
  for (
    let y = WIND_MARKER_SPACING_PIXELS / 2;
    y < canvas.clientHeight;
    y += WIND_MARKER_SPACING_PIXELS
  ) {
    for (
      let x = WIND_MARKER_SPACING_PIXELS / 2;
      x < canvas.clientWidth;
      x += WIND_MARKER_SPACING_PIXELS
    ) {
      const point = state.map.unproject([x, y]);
      if (
        point.lat < minimumLatitude ||
        point.lat > maximumLatitude ||
        point.lng < minimumLongitude ||
        point.lng > maximumLongitude
      ) {
        continue;
      }
      positions.push({ latitude: point.lat, longitude: point.lng });
    }
  }
  return positions;
}

function updateWindMarkers() {
  clearWindMarkers();
  const altitude = selectedWindLevel();
  elements.wind_altitude_label.textContent = `${altitude} m MSL`;
  if (!state.field || !elements.wind_toggle.checked) return;
  let departureOffsetSeconds = 0;
  try {
    departureOffsetSeconds =
      (state.routePlan?.departureOffsetMinutes ??
        selectedDepartureSearch().minimumDepartureOffsetMinutes) * 60;
  } catch {
    // Keep the map clear until a valid search day is selected.
    return;
  }
  for (const position of windDisplayPositions()) {
    const vector = interpolatedVectorAtPosition(
      state.field,
      position,
      altitude,
      departureOffsetSeconds,
    );
    if (!vector) continue;
    const element = document.createElement("div");
    element.className = "wind-marker";
    const arrow = document.createElement("span");
    arrow.className = "arrow";
    arrow.textContent = "↑";
    arrow.style.transform = `rotate(${(vector.fromDegrees + 180) % 360}deg)`;
    const speed = document.createElement("span");
    speed.className = "speed";
    speed.textContent = `${Math.round(vector.speedKmh)}`;
    element.append(arrow, speed);
    state.windMarkers.push(
      new maplibregl.Marker({ element, anchor: "center" })
        .setLngLat([position.longitude, position.latitude])
        .addTo(state.map),
    );
  }
}

function updateSources() {
  if (!state.map) return;
  state.map.getSource("forecast-track")?.setData(lineCollection(state.track));
  state.map
    .getSource("landing-envelope")
    ?.setData(landingEnvelopeFeature(state.landingEnvelope));
  state.map
    .getSource("forecast-area")
    ?.setData(polygonFeature(state.forecastLanding, FORECAST_AREA_RADIUS_METRES));
  state.map
    .getSource("intended-area")
    ?.setData(polygonFeature(state.intendedLanding, INTENDED_AREA_RADIUS_METRES));
  state.map
    .getSource("operational-boundaries")
    ?.setData(
      operationalBoundariesGeoJson(
        state.operationalBoundaries,
        state.operationalBoundaryDraft,
      ),
    );
}

function fitForecast() {
  const bounds = new maplibregl.LngLatBounds();
  if (state.launch) bounds.extend([state.launch.longitude, state.launch.latitude]);
  for (const point of state.track ?? []) bounds.extend([point.longitude, point.latitude]);
  if (state.intendedLanding) {
    bounds.extend([state.intendedLanding.longitude, state.intendedLanding.latitude]);
  }
  // Prioritise the displayed flight: fitting the full 10–180 minute envelope
  // can shrink a useful one-hour track until it is almost invisible.
  if (!state.track || state.track.length < 2) {
    for (const point of state.landingEnvelope) {
      bounds.extend([point.longitude, point.latitude]);
    }
  }
  if (!bounds.isEmpty()) state.map.fitBounds(bounds, { padding: 90, maxZoom: 11, duration: 700 });
}

function syncMaxAltitudeControl() {
  const launchElevationMetresMsl = Number(elements.launch_elevation.value);
  const minimum = Number.isFinite(launchElevationMetresMsl)
    ? Math.min(2000, Math.max(100, Math.ceil(launchElevationMetresMsl / 50) * 50))
    : 100;
  elements.max_altitude.min = String(minimum);
  if (Number(elements.max_altitude.value) < minimum) {
    elements.max_altitude.value = String(minimum);
  }
  elements.max_altitude_label.textContent =
    `${Number(elements.max_altitude.value).toLocaleString("en-GB")} m MSL`;
}

function syncVerticalRateControls() {
  elements.max_ascent_rate_label.textContent =
    `${Number(elements.max_ascent_rate.value).toFixed(1)} m/s`;
  elements.max_descent_rate_label.textContent =
    `${Number(elements.max_descent_rate.value).toFixed(1)} m/s`;
}

function validLaunchSettings() {
  const launchElevationMetresMsl = Number(elements.launch_elevation.value);
  if (
    !Number.isFinite(launchElevationMetresMsl) ||
    launchElevationMetresMsl < -50 ||
    launchElevationMetresMsl > 1000
  ) {
    throw new Error("Choose a valid launch elevation in metres MSL.");
  }
  const altitudeCeilingMetresMsl = Number(elements.max_altitude.value);
  if (
    !Number.isFinite(altitudeCeilingMetresMsl) ||
    altitudeCeilingMetresMsl < launchElevationMetresMsl ||
    altitudeCeilingMetresMsl > 2000
  ) {
    throw new Error("Choose a maximum altitude between launch elevation and 2,000 m MSL.");
  }
  const maximumAscentRateMetresPerSecond = Number(elements.max_ascent_rate.value);
  const maximumDescentRateMetresPerSecond = Number(elements.max_descent_rate.value);
  if (
    !Number.isFinite(maximumAscentRateMetresPerSecond) ||
    maximumAscentRateMetresPerSecond < 0.1 ||
    maximumAscentRateMetresPerSecond > 10 ||
    !Number.isFinite(maximumDescentRateMetresPerSecond) ||
    maximumDescentRateMetresPerSecond < 0.1 ||
    maximumDescentRateMetresPerSecond > 10
  ) {
    throw new Error("Choose maximum ascent and descent rates between 0.1 and 10.0 m/s.");
  }
  return {
    launchElevationMetresMsl,
    altitudeCeilingMetresMsl,
    maximumAscentRateMetresPerSecond,
    maximumDescentRateMetresPerSecond,
  };
}

function formatMissDistance(distanceMetres) {
  return distanceMetres < 1000
    ? `${Math.round(distanceMetres)} m`
    : `${(distanceMetres / 1000).toFixed(1)} km`;
}

function renderFlightProfile() {
  if (!state.routePlan) {
    elements.flight_profile.hidden = true;
    elements.profile_stages.replaceChildren();
    return;
  }
  const {
    launchElevationMetresMsl,
    altitudeCeilingMetresMsl,
    maximumAscentRateMetresPerSecond,
    maximumDescentRateMetresPerSecond,
  } = validLaunchSettings();
  const departureAt = state.routePlan.departureAt;
  const durationMinutes = state.routePlan.durationMinutes;
  const landingAt = new Date(departureAt.getTime() + durationMinutes * 60_000);
  const altitudes =
    state.routePlan.kind === "representative"
      ? ROUTE_CONTROL_FRACTIONS.map((fraction) =>
          altitudeForFlightFraction({
            fraction,
            launchElevationMetresMsl,
            maximumAltitudeMetresMsl: state.routePlan.peakAltitudeMetresMsl,
          }),
        )
      : [
          launchElevationMetresMsl,
          ...state.routePlan.controlAltitudesMetresMsl,
          launchElevationMetresMsl,
        ];
  const labels = ["Launch", "20%", "40%", "60%", "80%", "Landing"];
  elements.flight_profile_title.textContent =
    state.routePlan.kind === "representative" ? "Representative forecast" : "Optimised forecast";
  elements.profile_limit.textContent =
    `Ceiling ${altitudeCeilingMetresMsl.toLocaleString("en-GB")} m · ` +
    `↑ ${maximumAscentRateMetresPerSecond.toFixed(1)} · ` +
    `↓ ${maximumDescentRateMetresPerSecond.toFixed(1)} m/s`;
  elements.profile_start.textContent = formatLocalDateTime(departureAt);
  elements.profile_landing.textContent = formatLocalDateTime(landingAt);
  elements.profile_duration.textContent = `${durationMinutes.toFixed(1)} min`;
  const window = state.routePlan.departureWindow;
  elements.profile_window.hidden = !window;
  elements.profile_window.textContent = window
    ? window.startOffsetMinutes === window.endOffsetMinutes
      ? `Matching start: ${formatLocalTime(window.startAt)}`
      : `Matching start window: ${formatLocalTime(window.startAt)}–${formatLocalTime(window.endAt)}`
    : "";
  elements.profile_stages.replaceChildren();
  for (const [index, fraction] of ROUTE_CONTROL_FRACTIONS.entries()) {
    const row = document.createElement("tr");
    const stage = document.createElement("td");
    const time = document.createElement("td");
    const altitude = document.createElement("td");
    const change = document.createElement("td");
    const roundedAltitude = Math.round(altitudes[index]);
    stage.textContent = labels[index];
    time.textContent = formatLocalTime(
      new Date(departureAt.getTime() + durationMinutes * fraction * 60_000),
    );
    altitude.textContent = `${roundedAltitude.toLocaleString("en-GB")} m`;
    if (index === 0) {
      change.textContent = "—";
      change.className = "level";
    } else {
      const difference = roundedAltitude - Math.round(altitudes[index - 1]);
      const rateMetresPerSecond =
        Math.abs(difference) / (durationMinutes * 60 * 0.2);
      change.textContent =
        difference > 0
          ? `↑ ${difference.toLocaleString("en-GB")} m · ${rateMetresPerSecond.toFixed(1)} m/s`
          : difference < 0
            ? `↓ ${Math.abs(difference).toLocaleString("en-GB")} m · ${rateMetresPerSecond.toFixed(1)} m/s`
            : "—";
      change.className = difference > 0 ? "climb" : difference < 0 ? "descent" : "level";
    }
    row.append(stage, time, altitude, change);
    elements.profile_stages.append(row);
  }
  elements.flight_profile.hidden = false;
}

function recomputeTrack({ fit = false } = {}) {
  if (!state.field || !state.launch) return;
  try {
    const departureSearch = selectedDepartureSearch();
    const settings = {
      field: state.field,
      launch: state.launch,
      ...validLaunchSettings(),
      ...departureSearch,
    };
    if (state.manualLanding && state.intendedLanding) {
      state.routePlan = planWindRouteToDestination({
        ...settings,
        destination: state.intendedLanding,
      });
      state.track = state.routePlan.track;
      state.landingEnvelope = state.routePlan.boundary;
      state.landingCandidateCount = state.routePlan.candidateCount;
      const missDistance = formatMissDistance(state.routePlan.missDistanceMetres);
      setStatus(
        elements.route_status,
        state.routePlan.reachesDestination
          ? `Forecast lands ${missDistance} from the destination — within 100 m.`
          : `Closest forecast misses the destination by ${missDistance}; no match within 100 m.`,
        state.routePlan.reachesDestination ? "good" : "error",
      );
      state.forecastLanding = state.track.at(-1);
      setMarker("forecast", state.forecastLanding, "Calculated forecast landing");
      setMarker("intended", state.intendedLanding, "Destination");
      state.mode = null;
      elements.map_prompt.hidden = true;
    } else {
      const envelope = forecastLandingEnvelope(settings);
      state.routePlan = forecastRepresentativeRoute({
        ...settings,
        departureOffsetMinutes: departureSearch.minimumDepartureOffsetMinutes,
      });
      state.track = state.routePlan.track;
      state.forecastLanding = state.routePlan.landing;
      state.landingEnvelope = envelope.boundary;
      state.landingCandidateCount = envelope.candidates.length;
      setMarker("forecast", state.forecastLanding, "Forecast endpoint");
      setMarker("intended", null);
      state.mode = "landing";
      elements.map_prompt.hidden = false;
      elements.map_prompt.textContent = "Click map or drag yellow endpoint";
      setStatus(
        elements.route_status,
        "Representative drift shown. Place a destination to optimise the flight.",
        "good",
      );
    }
    updateSources();
    updateWindMarkers();
    elements.set_landing.disabled = false;
    elements.clear_destination.disabled = !state.manualLanding;
    elements.generate_code.disabled = !state.track || !state.manualLanding;
    elements.forecast_summary.hidden = !state.track;
    if (state.track) {
      elements.forecast_distance.textContent = `${(forecastDistanceMetres(state.track) / 1000).toFixed(1)} km forecast drift`;
      elements.forecast_validity.textContent =
        `${formatLocalDateTime(state.routePlan.departureAt)} · ` +
        `${state.routePlan.durationMinutes.toFixed(1)} min · ` +
        `${state.manualLanding ? "optimised" : "representative"} · hourly wind interpolation`;
    }
    renderFlightProfile();
    setStatus(
      elements.landing_status,
      state.manualLanding
        ? `Destination set; drag the green pin to adjust. ${state.routePlan.evaluatedCandidateCount} candidates checked.`
        : `Envelope: ${state.landingCandidateCount} coarse forecasts. Not a safe-landing assessment.`,
      "good",
    );
    setStatus(
      elements.wind_status,
      `Wind: ${formatLocalDay(departureSearch.dayStart)} · ${state.field.columns.length} points · ` +
        `~${Math.round(WIND_GRID_SPAN_METRES / 1000)} km grid · ` +
        `${formatLocalTime(state.routePlan?.departureAt ?? new Date(
          departureSearch.dayStart.getTime() +
            departureSearch.minimumDepartureOffsetMinutes * 60_000,
        ))} model hour (not observed).`,
      "good",
    );
    if (fit) fitForecast();
  } catch (error) {
    state.track = null;
    state.forecastLanding = null;
    state.landingEnvelope = [];
    state.landingCandidateCount = 0;
    state.routePlan = null;
    elements.generate_code.disabled = true;
    elements.set_landing.disabled = true;
    elements.clear_destination.disabled = true;
    elements.forecast_summary.hidden = true;
    renderFlightProfile();
    updateSources();
    setStatus(elements.wind_status, error.message, "error");
    setStatus(elements.route_status, "No route calculation is available with these settings.", "error");
  }
}

async function refreshForecast({ fit = true } = {}) {
  if (!state.launch) return;
  let departureSearch;
  try {
    departureSearch = selectedDepartureSearch();
    validLaunchSettings();
  } catch (error) {
    setStatus(elements.wind_status, error.message, "error");
    return;
  }
  state.forecastRequest?.abort();
  const request = new AbortController();
  state.forecastRequest = request;
  const generation = ++state.forecastGeneration;
  elements.generate_code.disabled = true;
  setStatus(elements.wind_status, "Loading UKMO wind layers from Open-Meteo…");
  try {
    const url = openMeteoRequestUrl({ endpoint: "/weather/v1/forecast", center: state.launch });
    const response = await fetch(`${url.pathname}${url.search}`, {
      headers: { Accept: "application/json" },
      signal: request.signal,
    });
    if (!response.ok) throw new Error(`Wind service returned ${response.status}.`);
    const payload = await response.json();
    if (generation !== state.forecastGeneration) return;
    state.field = parseOpenMeteoForecast(payload, departureSearch.dayStart);
    recomputeTrack({ fit });
  } catch (error) {
    if (error.name === "AbortError") return;
    state.field = null;
    state.track = null;
    state.forecastLanding = null;
    state.landingEnvelope = [];
    state.landingCandidateCount = 0;
    state.routePlan = null;
    clearWindMarkers();
    updateSources();
    elements.generate_code.disabled = true;
    elements.set_landing.disabled = true;
    elements.clear_destination.disabled = true;
    elements.forecast_summary.hidden = true;
    renderFlightProfile();
    setStatus(
      elements.wind_status,
      `No usable live wind forecast: ${error.message} Do not substitute a guessed track.`,
      "error",
    );
    setStatus(elements.landing_status, "Waiting for a usable wind forecast.");
    setStatus(elements.route_status, "No route calculation is available without wind data.", "error");
  }
}

function chooseLaunch(point, { preserveDestination = false, fit = true } = {}) {
  const retainDestination =
    preserveDestination && state.manualLanding && state.intendedLanding !== null;
  state.launch = { latitude: point.lat, longitude: point.lng };
  state.field = null;
  if (!retainDestination) {
    state.manualLanding = false;
    state.intendedLanding = null;
  }
  state.track = null;
  state.forecastLanding = null;
  state.landingEnvelope = [];
  state.landingCandidateCount = 0;
  state.routePlan = null;
  clearWindMarkers();
  elements.clear_destination.disabled = !retainDestination;
  elements.set_landing.disabled = true;
  elements.generate_code.disabled = true;
  elements.forecast_summary.hidden = true;
  renderFlightProfile();
  setMarker("launch", state.launch, "Launch");
  setMarker("forecast", null);
  if (!retainDestination) setMarker("intended", null);
  updateSources();
  setStatus(
    elements.launch_status,
    `${state.launch.latitude.toFixed(5)}, ${state.launch.longitude.toFixed(5)} · Drag the blue pin to adjust.`,
    "good",
  );
  state.mode = null;
  elements.map_prompt.hidden = true;
  setStatus(elements.landing_status, "Waiting for the wind forecast.");
  setStatus(elements.route_status, "Calculating the landing envelope from this launch point…");
  void refreshForecast({ fit });
}

async function chooseLanding(point, { fit = true } = {}) {
  state.intendedLanding = { latitude: point.lat, longitude: point.lng };
  state.manualLanding = true;
  setMarker("intended", state.intendedLanding, "Destination");
  updateSources();
  state.mode = null;
  elements.map_prompt.hidden = true;
  elements.clear_destination.disabled = false;
  setStatus(
    elements.landing_status,
    `Destination set at ${state.intendedLanding.latitude.toFixed(5)}, ${state.intendedLanding.longitude.toFixed(5)}. Drag the green pin to adjust; optimising route…`,
    "good",
  );
  await new Promise((resolve) => {
    window.requestAnimationFrame(() => window.setTimeout(resolve, 0));
  });
  recomputeTrack({ fit });
}

function clearDestination() {
  state.manualLanding = false;
  state.intendedLanding = null;
  state.routePlan = null;
  elements.clear_destination.disabled = true;
  recomputeTrack({ fit: true });
}

function beginMapChoice(mode) {
  state.mode = mode;
  elements.map_prompt.hidden = false;
  elements.map_prompt.textContent =
    mode === "launch"
      ? "Click the map to set the launch point; drag the pin later to adjust"
      : "Click the map to set the intended destination; drag the pin later to adjust";
}

const OPERATIONAL_BOUNDARY_STORAGE_KEY = "balloon-crumbs.operational-boundaries.v1";

function boundaryId() {
  return globalThis.crypto?.randomUUID?.() ?? `boundary-${Date.now()}`;
}

function boundaryDescription(boundary) {
  const geometry = boundary.kind === "line" ? "Line" : boundary.kind === "area" ? "Area" : "Altitude";
  const limits = [
    boundary.lowerAltitudeMeters === null ? null : `min ${boundary.lowerAltitudeMeters} m`,
    boundary.upperAltitudeMeters === null ? null : `max ${boundary.upperAltitudeMeters} m`,
  ].filter(Boolean);
  return `${geometry}${limits.length ? ` · ${limits.join(" · ")} · ${boundary.altitudeDatum}` : ""} · ${boundary.source}`;
}

function persistOperationalBoundaries() {
  try {
    localStorage.setItem(
      OPERATIONAL_BOUNDARY_STORAGE_KEY,
      JSON.stringify(state.operationalBoundaries),
    );
  } catch {
    setStatus(
      elements.boundary_status,
      "Boundaries are visible now but this browser could not save them.",
      "error",
    );
  }
}

function renderOperationalBoundaries() {
  elements.boundary_list.replaceChildren();
  for (const boundary of state.operationalBoundaries) {
    const item = document.createElement("li");
    const copy = document.createElement("div");
    const title = document.createElement("strong");
    const detail = document.createElement("small");
    const remove = document.createElement("button");
    title.textContent = boundary.label;
    detail.textContent = boundaryDescription(boundary);
    remove.type = "button";
    remove.textContent = "Remove";
    remove.setAttribute("aria-label", `Remove ${boundary.label}`);
    remove.addEventListener("click", () => {
      state.operationalBoundaries = state.operationalBoundaries.filter(
        (candidate) => candidate.id !== boundary.id,
      );
      persistOperationalBoundaries();
      renderOperationalBoundaries();
      updateSources();
      setStatus(elements.boundary_status, `${boundary.label} removed.`);
    });
    copy.append(title, detail);
    item.append(copy, remove);
    elements.boundary_list.append(item);
  }
}

function loadOperationalBoundaries() {
  try {
    const decoded = JSON.parse(localStorage.getItem(OPERATIONAL_BOUNDARY_STORAGE_KEY) ?? "[]");
    state.operationalBoundaries = Array.isArray(decoded)
      ? decoded.flatMap((value) => {
          try {
            return [normaliseOperationalBoundary(value)];
          } catch {
            return [];
          }
        })
      : [];
  } catch {
    state.operationalBoundaries = [];
  }
  renderOperationalBoundaries();
}

function boundaryLabelAndSource() {
  const label = elements.boundary_name.value.trim();
  const source = elements.boundary_source.value.trim();
  if (!label || !source) throw new Error("Add a boundary name and source first.");
  return { label, source };
}

function beginOperationalBoundary(kind) {
  try {
    const { label, source } = boundaryLabelAndSource();
    state.operationalBoundaryDraft = { id: boundaryId(), label, source, kind, points: [] };
    state.mode = "boundary";
    elements.finish_boundary.disabled = true;
    elements.cancel_boundary.disabled = false;
    elements.map_prompt.hidden = false;
    elements.map_prompt.textContent =
      kind === "line" ? "Click two points for the boundary line" : "Click at least three corners, then finish the area";
    setStatus(elements.boundary_status, "Boundary drawing started. Map points are approximate.");
    updateSources();
  } catch (error) {
    setStatus(elements.boundary_status, error.message, "error");
  }
}

function cancelOperationalBoundary() {
  state.operationalBoundaryDraft = null;
  state.mode = null;
  elements.finish_boundary.disabled = true;
  elements.cancel_boundary.disabled = true;
  elements.map_prompt.hidden = true;
  updateSources();
  setStatus(elements.boundary_status, "Boundary drawing cancelled.");
}

function finishOperationalBoundary() {
  const draft = state.operationalBoundaryDraft;
  if (!draft) return;
  try {
    const boundary = normaliseOperationalBoundary({
      ...draft,
      lowerAltitudeMeters: null,
      upperAltitudeMeters: null,
      altitudeDatum: "wgs84Geoid",
    });
    state.operationalBoundaries = [...state.operationalBoundaries, boundary];
    state.operationalBoundaryDraft = null;
    state.mode = null;
    elements.finish_boundary.disabled = true;
    elements.cancel_boundary.disabled = true;
    elements.map_prompt.hidden = true;
    persistOperationalBoundaries();
    renderOperationalBoundaries();
    updateSources();
    setStatus(elements.boundary_status, `${boundary.label} saved in this browser.`, "good");
  } catch (error) {
    setStatus(elements.boundary_status, error.message, "error");
  }
}

function addOperationalBoundaryPoint(point) {
  const draft = state.operationalBoundaryDraft;
  if (!draft) return;
  draft.points.push({ latitude: point.lat, longitude: point.lng });
  elements.finish_boundary.disabled = draft.kind !== "area" || draft.points.length < 3;
  updateSources();
  if (draft.kind === "line" && draft.points.length >= 2) finishOperationalBoundary();
}

function optionalNumber(element) {
  const raw = element.value.trim();
  if (!raw) return null;
  const value = Number(raw);
  if (!Number.isFinite(value)) throw new Error("Altitude limits must be numbers.");
  return value;
}

function windFieldDigest(field) {
  const input = JSON.stringify({
    validAt: field?.validAt,
    requestedAt: field?.requestedAt,
    columns: (field?.columns ?? []).map((column) => ({
      position: column.position,
      vectors: column.vectors,
    })),
  });
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return `fnv1a32:${(hash >>> 0).toString(16).padStart(8, "0")}`;
}

function addAltitudeBoundary() {
  try {
    const { label, source } = boundaryLabelAndSource();
    const boundary = normaliseOperationalBoundary({
      id: boundaryId(),
      label,
      source,
      kind: "altitudeBand",
      points: [],
      lowerAltitudeMeters: optionalNumber(elements.boundary_lower_altitude),
      upperAltitudeMeters: optionalNumber(elements.boundary_upper_altitude),
      altitudeDatum: elements.boundary_altitude_datum.value,
    });
    state.operationalBoundaries = [...state.operationalBoundaries, boundary];
    persistOperationalBoundaries();
    renderOperationalBoundaries();
    updateSources();
    setStatus(elements.boundary_status, `${boundary.label} saved in this browser.`, "good");
  } catch (error) {
    setStatus(elements.boundary_status, error.message, "error");
  }
}

function useDeviceLocation() {
  if (!("geolocation" in navigator)) {
    setStatus(elements.launch_status, "This browser cannot provide a location.", "error");
    return;
  }
  setStatus(elements.launch_status, "Waiting for this device’s location…");
  navigator.geolocation.getCurrentPosition(
    (position) => {
      const point = { lat: position.coords.latitude, lng: position.coords.longitude };
      state.map.easeTo({ center: [point.lng, point.lat], zoom: 10, duration: 600 });
      chooseLaunch(point);
    },
    () => setStatus(elements.launch_status, "Location was not available. Set launch on the map instead.", "error"),
    { enableHighAccuracy: false, timeout: 10_000, maximumAge: 60_000 },
  );
}

async function generatePlanCode() {
  if (!state.track || !state.launch || !state.forecastLanding || !state.intendedLanding) return;
  elements.generate_code.disabled = true;
  elements.code_result.hidden = true;
  setStatus(elements.generate_status, "Creating a short plan code…");
  try {
    const name = elements.plan_name.value.trim() || "Forecast balloon flight";
    const gpx = buildFlightPlanGpx({
      name,
      track: state.track,
      departureAt: state.routePlan.departureAt,
      launch: state.launch,
      forecastLanding: state.forecastLanding,
      intendedLanding: state.intendedLanding,
    });
    const forecastTimes = (state.field.timeSlices ?? [])
      .map((slice) => slice.validAt)
      .filter((value) => value instanceof Date && !Number.isNaN(value.getTime()))
      .sort((first, second) => first - second);
    const forecastPlan = buildForecastPlanDocument({
      id: globalThis.crypto?.randomUUID?.() ?? `plan-${Date.now()}`,
      name,
      createdAt: new Date(),
      launch: state.launch,
      launchElevationMetresMsl: Number(elements.launch_elevation.value),
      intendedLanding: state.intendedLanding,
      intendedLandingRadiusMetres: INTENDED_AREA_RADIUS_METRES,
      forecastLanding: state.forecastLanding,
      routePlan: state.routePlan,
      landingEnvelope: state.landingEnvelope,
      wind: {
        provider: "Open-Meteo",
        model: "UKMO seamless",
        requestedAt: state.field.requestedAt,
        validFrom: forecastTimes[0] ?? state.field.validAt,
        validTo: forecastTimes.at(-1) ?? state.field.validAt,
        attribution: "Weather data by Open-Meteo",
        licence: "CC BY 4.0",
        fieldDigest: windFieldDigest(state.field),
      },
      operationalBoundaries: state.operationalBoundaries,
      gpxFallback: gpx,
    });
    const response = await fetch("/api/v1/plans", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ name, gpx, forecastPlan }),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error || `Relay returned ${response.status}.`);
    elements.plan_code.textContent = body.code;
    elements.open_in_app.href = `${APP_LINK_ORIGIN}/planner.html?code=${encodeURIComponent(body.code)}`;
    elements.plan_expiry.textContent = body.expiresAt
      ? `Expires ${formatUtc(new Date(body.expiresAt))}. The forecast itself becomes stale much sooner.`
      : "Plan codes expire; the forecast itself becomes stale much sooner.";
    elements.code_result.hidden = false;
    setStatus(elements.generate_status, "Plan saved. Enter the code in Balloon Crumbs or open the app link.", "good");
  } catch (error) {
    setStatus(elements.generate_status, `The plan could not be saved: ${error.message}`, "error");
  } finally {
    elements.generate_code.disabled = !state.track || !state.manualLanding;
  }
}

async function copyPlanCode() {
  const code = elements.plan_code.textContent;
  if (!code) return;
  try {
    await navigator.clipboard.writeText(code);
    elements.copy_code.textContent = "Copied";
    window.setTimeout(() => { elements.copy_code.textContent = "Copy"; }, 1_500);
  } catch {
    setStatus(elements.generate_status, "Copy was blocked; select the code manually.", "error");
  }
}

function bindControls() {
  elements.place_search_form.addEventListener("submit", (event) => void searchForPlace(event));
  elements.set_launch.addEventListener("click", () => beginMapChoice("launch"));
  elements.set_landing.addEventListener("click", () => beginMapChoice("landing"));
  elements.clear_destination.addEventListener("click", clearDestination);
  elements.use_location.addEventListener("click", useDeviceLocation);
  elements.theme_toggle.addEventListener("change", applyMapTheme);
  elements.retry_map.addEventListener("click", () => window.location.reload());
  elements.wind_altitude.addEventListener("input", updateWindMarkers);
  elements.wind_toggle.addEventListener("change", updateWindMarkers);
  elements.airspace_toggle.addEventListener("change", () => {
    if (state.map?.getLayer("openaip-chart")) {
      state.map.setLayoutProperty(
        "openaip-chart",
        "visibility",
        elements.airspace_toggle.checked ? "visible" : "none",
      );
    }
  });
  elements.departure_time.addEventListener("change", () => void refreshForecast());
  elements.launch_elevation.addEventListener("change", () => {
    syncMaxAltitudeControl();
    recomputeTrack({ fit: false });
  });
  elements.max_altitude.addEventListener("input", syncMaxAltitudeControl);
  elements.max_altitude.addEventListener("change", () => recomputeTrack({ fit: true }));
  elements.max_ascent_rate.addEventListener("input", syncVerticalRateControls);
  elements.max_ascent_rate.addEventListener("change", () => recomputeTrack({ fit: true }));
  elements.max_descent_rate.addEventListener("input", syncVerticalRateControls);
  elements.max_descent_rate.addEventListener("change", () => recomputeTrack({ fit: true }));
  elements.generate_code.addEventListener("click", () => void generatePlanCode());
  elements.copy_code.addEventListener("click", () => void copyPlanCode());
  elements.draw_boundary_line.addEventListener("click", () => beginOperationalBoundary("line"));
  elements.draw_boundary_area.addEventListener("click", () => beginOperationalBoundary("area"));
  elements.finish_boundary.addEventListener("click", finishOperationalBoundary);
  elements.cancel_boundary.addEventListener("click", cancelOperationalBoundary);
  elements.add_altitude_boundary.addEventListener("click", addAltitudeBoundary);
}

async function start() {
  elements.theme_toggle.checked = window.matchMedia("(prefers-color-scheme: dark)").matches;
  applyMapTheme();
  configureDepartureInput();
  syncMaxAltitudeControl();
  syncVerticalRateControls();
  updateClock();
  window.setInterval(updateClock, 1_000);
  bindControls();
  loadOperationalBoundaries();
  updateWindMarkers();
  try {
    setMapStatus("Loading basemap tiles…");
    const style = themeStyle(await loadMapStyle(), selectedMapTheme());
    state.map = new maplibregl.Map({
      container: "map",
      style,
      center: DEFAULT_CENTER,
      zoom: 5.1,
      attributionControl: false,
    });
    state.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
    state.map.addControl(new maplibregl.AttributionControl({ compact: true }), "bottom-right");
    state.map.on("sourcedata", (event) => {
      if (event.sourceId === "basemap" && event.isSourceLoaded) {
        state.mapTileFailures = 0;
        setMapStatus("Basemap tiles loaded", "good");
      }
    });
    state.map.on("error", (event) => {
      const sourceId = event.sourceId ?? event.source?.id;
      if (sourceId !== "basemap" && sourceId !== "openaip-chart") return;
      state.mapTileFailures += 1;
      setMapStatus(
        sourceId === "basemap"
          ? "Some basemap tiles failed to load."
          : "Some OpenAIP chart tiles failed to load.",
        "error",
        true,
      );
    });
    state.map.on("load", () => {
      addPlannerLayers(state.map);
      elements.place_search_submit.disabled = false;
      applyMapTheme();
      updateSources();
      state.map.on("moveend", updateWindMarkers);
      state.map.on("resize", updateWindMarkers);
      state.map.on("click", (event) => {
        if (state.mode === "launch") chooseLaunch(event.lngLat);
        else if (state.mode === "landing") void chooseLanding(event.lngLat);
        else if (state.mode === "boundary") addOperationalBoundaryPoint(event.lngLat);
      });
    });
  } catch (error) {
    elements.map.textContent = `Map unavailable: ${error.message}`;
    elements.place_search_submit.disabled = true;
    setMapStatus("The basemap could not start.", "error", true);
    setStatus(elements.place_search_status, "Place search is unavailable without the map.", "error");
    setStatus(elements.wind_status, "The map could not start, so no flight forecast was made.", "error");
  }
}

void start();
