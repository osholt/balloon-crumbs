import {
  WIND_LEVELS_METRES_MSL,
  buildFlightPlanGpx,
  circlePolygon,
  forecastDistanceMetres,
  forecastFlightTrack,
  openMeteoRequestUrl,
  parseOpenMeteoForecast,
  vectorAtAltitude,
} from "./planner-core.mjs";

// Keep the installed-app hand-off on its already-shipped associated domain.
// The planner itself is hosted at balloon-crumbs.pages.dev.
const APP_LINK_ORIGIN = "https://balloon-crumbs.tailendcharlie.app";
const FORECAST_AREA_RADIUS_METRES = 750;
const INTENDED_AREA_RADIUS_METRES = 400;
const DEFAULT_CENTER = [-2.5, 54.4];

const elements = Object.fromEntries(
  [
    "airspace-toggle",
    "clock",
    "code-result",
    "copy-code",
    "departure-time",
    "duration-minutes",
    "forecast-distance",
    "forecast-summary",
    "forecast-validity",
    "generate-code",
    "generate-status",
    "launch-elevation",
    "launch-status",
    "landing-status",
    "map",
    "map-prompt",
    "maximum-altitude",
    "open-in-app",
    "plan-code",
    "plan-expiry",
    "plan-name",
    "set-landing",
    "set-launch",
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
  markers: {},
  windMarkers: [],
  forecastRequest: null,
  forecastGeneration: 0,
};

function setStatus(element, message, kind = "") {
  element.textContent = message;
  element.classList.toggle("error", kind === "error");
  element.classList.toggle("good", kind === "good");
}

function toLocalInputValue(date) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function selectedDeparture() {
  const value = new Date(elements.departure_time.value);
  if (Number.isNaN(value.getTime())) throw new Error("Choose a valid departure time.");
  return value;
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
  const rounded = new Date(now.getTime() + 45 * 60_000);
  rounded.setMinutes(0, 0, 0);
  elements.departure_time.min = toLocalInputValue(new Date(now.getTime() - 30 * 60_000));
  elements.departure_time.max = toLocalInputValue(new Date(now.getTime() + 47 * 60 * 60_000));
  elements.departure_time.value = toLocalInputValue(rounded);
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
      paint: { "raster-opacity": 0.76, "raster-fade-duration": 180 },
    },
    firstSymbol,
  );

  map.addSource("forecast-track", { type: "geojson", data: lineCollection(null) });
  map.addLayer({
    id: "forecast-track-casing",
    type: "line",
    source: "forecast-track",
    paint: { "line-color": "#11151c", "line-width": 9, "line-opacity": 0.8 },
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
        "#4ea5ff",
        500,
        "#55e1d2",
        1000,
        "#ffd45e",
        2000,
        "#ff6f8c",
      ],
      "line-width": 5,
      "line-opacity": 0.96,
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
  element.title = label;
  element.setAttribute("aria-label", label);
  return element;
}

function setMarker(kind, point, label) {
  state.markers[kind]?.remove();
  if (!point) {
    delete state.markers[kind];
    return;
  }
  state.markers[kind] = new maplibregl.Marker({ element: markerElement(kind, label) })
    .setLngLat([point.longitude, point.latitude])
    .addTo(state.map);
}

function selectedWindLevel() {
  return WIND_LEVELS_METRES_MSL[Number(elements.wind_altitude.value)] ?? 500;
}

function clearWindMarkers() {
  for (const marker of state.windMarkers) marker.remove();
  state.windMarkers = [];
}

function updateWindMarkers() {
  clearWindMarkers();
  const altitude = selectedWindLevel();
  elements.wind_altitude_label.textContent = `${altitude} m MSL`;
  if (!state.field || !elements.wind_toggle.checked) return;
  for (const column of state.field.columns) {
    const vector = vectorAtAltitude(column, altitude);
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
        .setLngLat([column.position.longitude, column.position.latitude])
        .addTo(state.map),
    );
  }
}

function updateSources() {
  if (!state.map?.isStyleLoaded()) return;
  state.map.getSource("forecast-track")?.setData(lineCollection(state.track));
  state.map
    .getSource("forecast-area")
    ?.setData(polygonFeature(state.forecastLanding, FORECAST_AREA_RADIUS_METRES));
  state.map
    .getSource("intended-area")
    ?.setData(polygonFeature(state.intendedLanding, INTENDED_AREA_RADIUS_METRES));
}

function fitForecast() {
  if (!state.track?.length) return;
  const bounds = new maplibregl.LngLatBounds();
  for (const point of state.track) bounds.extend([point.longitude, point.latitude]);
  if (state.intendedLanding) {
    bounds.extend([state.intendedLanding.longitude, state.intendedLanding.latitude]);
  }
  state.map.fitBounds(bounds, { padding: 90, maxZoom: 11, duration: 700 });
}

function validFlightSettings() {
  const durationMinutes = Number(elements.duration_minutes.value);
  const launchElevationMetresMsl = Number(elements.launch_elevation.value);
  const maximumAltitudeMetresMsl = Number(elements.maximum_altitude.value);
  if (!Number.isFinite(durationMinutes) || durationMinutes < 10 || durationMinutes > 180) {
    throw new Error("Flight duration must be between 10 and 180 minutes.");
  }
  if (!Number.isFinite(launchElevationMetresMsl) || launchElevationMetresMsl < -50) {
    throw new Error("Choose a valid launch elevation in metres MSL.");
  }
  if (
    !Number.isFinite(maximumAltitudeMetresMsl) ||
    maximumAltitudeMetresMsl < launchElevationMetresMsl ||
    maximumAltitudeMetresMsl > 2500
  ) {
    throw new Error("Maximum altitude must be above launch and no more than 2,500 m MSL.");
  }
  return { durationMinutes, launchElevationMetresMsl, maximumAltitudeMetresMsl };
}

function recomputeTrack({ fit = false } = {}) {
  if (!state.field || !state.launch) return;
  try {
    state.track = forecastFlightTrack({ field: state.field, launch: state.launch, ...validFlightSettings() });
    state.forecastLanding = state.track.at(-1);
    if (!state.manualLanding || !state.intendedLanding) state.intendedLanding = state.forecastLanding;
    setMarker("forecast", state.forecastLanding, "Forecast landing");
    setMarker("intended", state.intendedLanding, "Pilot intended landing area");
    updateSources();
    updateWindMarkers();
    elements.set_landing.disabled = false;
    elements.generate_code.disabled = false;
    elements.forecast_summary.hidden = false;
    elements.forecast_distance.textContent = `${(forecastDistanceMetres(state.track) / 1000).toFixed(1)} km forecast drift`;
    elements.forecast_validity.textContent = `Wind valid ${formatUtc(state.field.validAt)}`;
    setStatus(
      elements.landing_status,
      state.manualLanding
        ? "Pilot landing area retained. Forecast landing has updated separately."
        : "Pilot landing area currently follows the forecast endpoint.",
      "good",
    );
    setStatus(
      elements.wind_status,
      `UKMO wind valid ${formatUtc(state.field.validAt)} · forecast model, not an observation.`,
      "good",
    );
    if (fit) fitForecast();
  } catch (error) {
    state.track = null;
    state.forecastLanding = null;
    elements.generate_code.disabled = true;
    elements.set_landing.disabled = true;
    elements.forecast_summary.hidden = true;
    updateSources();
    setStatus(elements.wind_status, error.message, "error");
  }
}

async function refreshForecast() {
  if (!state.launch) return;
  let departure;
  try {
    departure = selectedDeparture();
    validFlightSettings();
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
    state.field = parseOpenMeteoForecast(payload, departure);
    recomputeTrack({ fit: true });
  } catch (error) {
    if (error.name === "AbortError") return;
    state.field = null;
    state.track = null;
    state.forecastLanding = null;
    clearWindMarkers();
    updateSources();
    elements.generate_code.disabled = true;
    elements.set_landing.disabled = true;
    elements.forecast_summary.hidden = true;
    setStatus(
      elements.wind_status,
      `No usable live wind forecast: ${error.message} Do not substitute a guessed track.`,
      "error",
    );
    setStatus(elements.landing_status, "Waiting for a usable wind forecast.");
  }
}

function chooseLaunch(point) {
  state.launch = { latitude: point.lat, longitude: point.lng };
  state.manualLanding = false;
  state.intendedLanding = null;
  setMarker("launch", state.launch, "Launch");
  setStatus(
    elements.launch_status,
    `${state.launch.latitude.toFixed(5)}, ${state.launch.longitude.toFixed(5)}`,
    "good",
  );
  state.mode = null;
  elements.map_prompt.hidden = true;
  void refreshForecast();
}

function chooseLanding(point) {
  state.intendedLanding = { latitude: point.lat, longitude: point.lng };
  state.manualLanding = true;
  setMarker("intended", state.intendedLanding, "Pilot intended landing area");
  updateSources();
  state.mode = null;
  elements.map_prompt.hidden = true;
  setStatus(
    elements.landing_status,
    `Pilot landing area set at ${state.intendedLanding.latitude.toFixed(5)}, ${state.intendedLanding.longitude.toFixed(5)}. It can be updated again.`,
    "good",
  );
}

function beginMapChoice(mode) {
  state.mode = mode;
  elements.map_prompt.hidden = false;
  elements.map_prompt.textContent =
    mode === "launch" ? "Click the map to set the launch point" : "Click the map to move the intended landing area";
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
      departureAt: selectedDeparture(),
      launch: state.launch,
      forecastLanding: state.forecastLanding,
      intendedLanding: state.intendedLanding,
    });
    const response = await fetch("/api/v1/plans", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ name, gpx }),
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
    elements.generate_code.disabled = !state.track;
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
  elements.set_launch.addEventListener("click", () => beginMapChoice("launch"));
  elements.set_landing.addEventListener("click", () => beginMapChoice("landing"));
  elements.use_location.addEventListener("click", useDeviceLocation);
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
  for (const input of [elements.duration_minutes, elements.launch_elevation, elements.maximum_altitude]) {
    input.addEventListener("change", () => recomputeTrack({ fit: false }));
  }
  elements.generate_code.addEventListener("click", () => void generatePlanCode());
  elements.copy_code.addEventListener("click", () => void copyPlanCode());
}

async function start() {
  configureDepartureInput();
  updateClock();
  window.setInterval(updateClock, 1_000);
  bindControls();
  updateWindMarkers();
  try {
    const style = await loadMapStyle();
    state.map = new maplibregl.Map({
      container: "map",
      style,
      center: DEFAULT_CENTER,
      zoom: 5.1,
      attributionControl: false,
    });
    state.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
    state.map.addControl(new maplibregl.AttributionControl({ compact: true }), "bottom-right");
    state.map.on("load", () => {
      addPlannerLayers(state.map);
      updateSources();
      state.map.on("click", (event) => {
        if (state.mode === "launch") chooseLaunch(event.lngLat);
        else if (state.mode === "landing") chooseLanding(event.lngLat);
      });
    });
  } catch (error) {
    elements.map.textContent = `Map unavailable: ${error.message}`;
    setStatus(elements.wind_status, "The map could not start, so no flight forecast was made.", "error");
  }
}

void start();
