export const WIND_LEVELS_METRES_MSL = Object.freeze([
  20, 50, 100, 150, 200, 300, 400, 500, 600, 800, 1000, 1250, 1500, 2000,
]);

const EARTH_RADIUS_METRES = 6_371_000;
const DEFAULT_STEP_SECONDS = 60;

function finiteNumber(value, label) {
  const number = Number(value);
  if (!Number.isFinite(number)) throw new TypeError(`${label} must be finite.`);
  return number;
}

function validPoint(point, label = "point") {
  const latitude = finiteNumber(point?.latitude, `${label} latitude`);
  const longitude = finiteNumber(point?.longitude, `${label} longitude`);
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new RangeError(`${label} is outside valid latitude/longitude bounds.`);
  }
  return { latitude, longitude };
}

export function windForecastGrid(center) {
  const origin = validPoint(center, "forecast centre");
  return Object.freeze([
    ...[-0.04, 0, 0.04].flatMap((latitudeOffset) =>
      [-0.06, 0, 0.06].map((longitudeOffset) => ({
        latitude: Math.max(-90, Math.min(90, origin.latitude + latitudeOffset)),
        longitude: Math.max(-180, Math.min(180, origin.longitude + longitudeOffset)),
      })),
    ),
  ]);
}

export function openMeteoRequestUrl({ endpoint, center }) {
  const url = new URL(endpoint, "https://planner.invalid");
  const points = windForecastGrid(center);
  const variables = WIND_LEVELS_METRES_MSL.flatMap((altitude) => [
    `wind_speed_${altitude}m`,
    `wind_direction_${altitude}m`,
  ]);
  url.searchParams.set("latitude", points.map((point) => point.latitude.toFixed(6)).join(","));
  url.searchParams.set("longitude", points.map((point) => point.longitude.toFixed(6)).join(","));
  url.searchParams.set("models", "ukmo_seamless");
  url.searchParams.set("hourly", variables.join(","));
  url.searchParams.set("wind_speed_unit", "kmh");
  url.searchParams.set("timezone", "GMT");
  url.searchParams.set("forecast_days", "3");
  return url;
}

function parseUtcHour(value) {
  if (typeof value !== "string" || value.length < 16) return null;
  const parsed = new Date(/[zZ]|[+-]\d\d:\d\d$/.test(value) ? value : `${value}Z`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function nearestTimeIndex(times, requestedAt) {
  const target = requestedAt.getTime();
  let selected = 0;
  for (let index = 1; index < times.length; index += 1) {
    if (Math.abs(times[index].getTime() - target) < Math.abs(times[selected].getTime() - target)) {
      selected = index;
    }
  }
  return selected;
}

export function parseOpenMeteoForecast(payload, requestedAt) {
  const target = requestedAt instanceof Date ? requestedAt : new Date(requestedAt);
  if (Number.isNaN(target.getTime())) throw new TypeError("Forecast time is invalid.");
  const entries = Array.isArray(payload) ? payload : [payload];
  const columns = [];
  let validAt = null;

  for (const entry of entries) {
    if (!entry || typeof entry !== "object" || !entry.hourly) continue;
    let position;
    try {
      position = validPoint(
        { latitude: entry.latitude, longitude: entry.longitude },
        "forecast column",
      );
    } catch {
      continue;
    }
    const rawTimes = Array.isArray(entry.hourly.time) ? entry.hourly.time : [];
    const times = rawTimes.map(parseUtcHour);
    if (times.length === 0 || times.some((time) => time === null)) continue;
    const timeIndex = nearestTimeIndex(times, target);
    const vectors = [];
    for (const altitudeMetresMsl of WIND_LEVELS_METRES_MSL) {
      const speeds = entry.hourly[`wind_speed_${altitudeMetresMsl}m`];
      const directions = entry.hourly[`wind_direction_${altitudeMetresMsl}m`];
      const speedKmh = Number(Array.isArray(speeds) ? speeds[timeIndex] : NaN);
      const fromDegrees = Number(Array.isArray(directions) ? directions[timeIndex] : NaN);
      if (!Number.isFinite(speedKmh) || speedKmh < 0 || !Number.isFinite(fromDegrees)) continue;
      vectors.push({
        altitudeMetresMsl,
        speedKmh,
        fromDegrees: ((fromDegrees % 360) + 360) % 360,
      });
    }
    if (vectors.length === 0) continue;
    validAt ??= times[timeIndex];
    columns.push({ position, vectors });
  }

  if (columns.length === 0 || validAt === null) {
    throw new Error("Open-Meteo returned no usable wind profiles for this time and place.");
  }
  return { columns, validAt, requestedAt: target };
}

function components(vector) {
  const towardRadians = (((vector.fromDegrees + 180) % 360) * Math.PI) / 180;
  const speedMetresPerSecond = vector.speedKmh / 3.6;
  return {
    eastMetresPerSecond: speedMetresPerSecond * Math.sin(towardRadians),
    northMetresPerSecond: speedMetresPerSecond * Math.cos(towardRadians),
  };
}

function vectorFromComponents(altitudeMetresMsl, eastMetresPerSecond, northMetresPerSecond) {
  const speedMetresPerSecond = Math.hypot(eastMetresPerSecond, northMetresPerSecond);
  const towardDegrees =
    ((Math.atan2(eastMetresPerSecond, northMetresPerSecond) * 180) / Math.PI + 360) % 360;
  return {
    altitudeMetresMsl,
    speedKmh: speedMetresPerSecond * 3.6,
    fromDegrees: (towardDegrees + 180) % 360,
  };
}

export function vectorAtAltitude(column, requestedAltitudeMetresMsl) {
  const altitude = finiteNumber(requestedAltitudeMetresMsl, "wind altitude");
  const vectors = [...(column?.vectors ?? [])].sort(
    (first, second) => first.altitudeMetresMsl - second.altitudeMetresMsl,
  );
  if (vectors.length === 0) return null;
  if (altitude <= vectors[0].altitudeMetresMsl) return vectors[0];
  if (altitude >= vectors.at(-1).altitudeMetresMsl) return vectors.at(-1);
  for (let index = 0; index < vectors.length - 1; index += 1) {
    const below = vectors[index];
    const above = vectors[index + 1];
    if (altitude > above.altitudeMetresMsl) continue;
    const fraction =
      (altitude - below.altitudeMetresMsl) /
      (above.altitudeMetresMsl - below.altitudeMetresMsl);
    const belowComponents = components(below);
    const aboveComponents = components(above);
    return vectorFromComponents(
      altitude,
      belowComponents.eastMetresPerSecond +
        (aboveComponents.eastMetresPerSecond - belowComponents.eastMetresPerSecond) * fraction,
      belowComponents.northMetresPerSecond +
        (aboveComponents.northMetresPerSecond - belowComponents.northMetresPerSecond) * fraction,
    );
  }
  return vectors.at(-1);
}

export function distanceMetres(first, second) {
  const a = validPoint(first, "first point");
  const b = validPoint(second, "second point");
  const dLatitude = ((b.latitude - a.latitude) * Math.PI) / 180;
  const dLongitude = ((b.longitude - a.longitude) * Math.PI) / 180;
  const firstLatitude = (a.latitude * Math.PI) / 180;
  const secondLatitude = (b.latitude * Math.PI) / 180;
  const haversine =
    Math.sin(dLatitude / 2) ** 2 +
    Math.cos(firstLatitude) * Math.cos(secondLatitude) * Math.sin(dLongitude / 2) ** 2;
  return 2 * EARTH_RADIUS_METRES * Math.asin(Math.sqrt(haversine));
}

export function vectorAtPosition(field, position, altitudeMetresMsl) {
  const columns = field?.columns ?? [];
  if (columns.length === 0) return null;
  const nearest = columns.reduce((best, candidate) =>
    distanceMetres(candidate.position, position) < distanceMetres(best.position, position)
      ? candidate
      : best,
  );
  return vectorAtAltitude(nearest, altitudeMetresMsl);
}

export function altitudeForFlightFraction({
  fraction,
  launchElevationMetresMsl,
  maximumAltitudeMetresMsl,
}) {
  const progress = Math.max(0, Math.min(1, finiteNumber(fraction, "flight fraction")));
  const launch = finiteNumber(launchElevationMetresMsl, "launch elevation");
  const maximum = Math.max(launch, finiteNumber(maximumAltitudeMetresMsl, "maximum altitude"));
  if (progress <= 0.2) return launch + (maximum - launch) * (progress / 0.2);
  if (progress <= 0.7) return maximum;
  return launch + (maximum - launch) * ((1 - progress) / 0.3);
}

export function altitudeForStrategyFraction({
  fraction,
  launchElevationMetresMsl,
  firstCruiseAltitudeMetresMsl,
  secondCruiseAltitudeMetresMsl,
}) {
  const progress = Math.max(0, Math.min(1, finiteNumber(fraction, "flight fraction")));
  const launch = finiteNumber(launchElevationMetresMsl, "launch elevation");
  const first = Math.max(
    launch,
    finiteNumber(firstCruiseAltitudeMetresMsl, "first cruise altitude"),
  );
  const second = Math.max(
    launch,
    finiteNumber(secondCruiseAltitudeMetresMsl, "second cruise altitude"),
  );
  if (progress <= 0.2) return launch + (first - launch) * (progress / 0.2);
  if (progress <= 0.45) return first;
  if (progress <= 0.55) return first + (second - first) * ((progress - 0.45) / 0.1);
  if (progress <= 0.7) return second;
  return launch + (second - launch) * ((1 - progress) / 0.3);
}

export function moveWithWind(position, vector, seconds) {
  const origin = validPoint(position);
  const elapsed = finiteNumber(seconds, "elapsed seconds");
  const wind = components(vector);
  const latitudeDelta =
    ((wind.northMetresPerSecond * elapsed) / EARTH_RADIUS_METRES) * (180 / Math.PI);
  const latitudeRadians = (origin.latitude * Math.PI) / 180;
  const longitudeScale = Math.max(0.01, Math.cos(latitudeRadians));
  const longitudeDelta =
    ((wind.eastMetresPerSecond * elapsed) / (EARTH_RADIUS_METRES * longitudeScale)) *
    (180 / Math.PI);
  return {
    latitude: Math.max(-90, Math.min(90, origin.latitude + latitudeDelta)),
    longitude: Math.max(-180, Math.min(180, origin.longitude + longitudeDelta)),
  };
}

function forecastTrackWithAltitudeProfile({
  field,
  launch,
  durationMinutes,
  altitudeAtFraction,
  stepSeconds = DEFAULT_STEP_SECONDS,
}) {
  let position = validPoint(launch, "launch point");
  const durationSeconds = Math.round(finiteNumber(durationMinutes, "flight duration") * 60);
  const step = Math.round(finiteNumber(stepSeconds, "forecast step"));
  if (durationSeconds < 600 || durationSeconds > 6 * 60 * 60 || step < 10) {
    throw new RangeError("Flight duration or forecast step is outside the supported range.");
  }
  const points = [];
  for (let elapsedSeconds = 0; elapsedSeconds <= durationSeconds; elapsedSeconds += step) {
    const fraction = elapsedSeconds / durationSeconds;
    const altitudeMetresMsl = altitudeAtFraction(fraction);
    const vector = vectorAtPosition(field, position, altitudeMetresMsl);
    if (!vector) throw new Error("The wind field does not cover the forecast flight.");
    points.push({ ...position, altitudeMetresMsl, elapsedSeconds, wind: vector });
    if (elapsedSeconds < durationSeconds) {
      position = moveWithWind(position, vector, Math.min(step, durationSeconds - elapsedSeconds));
    }
  }
  return Object.freeze(points);
}

export function forecastFlightTrack({
  field,
  launch,
  launchElevationMetresMsl,
  maximumAltitudeMetresMsl,
  durationMinutes,
  stepSeconds = DEFAULT_STEP_SECONDS,
}) {
  return forecastTrackWithAltitudeProfile({
    field,
    launch,
    durationMinutes,
    stepSeconds,
    altitudeAtFraction: (fraction) =>
      altitudeForFlightFraction({
        fraction,
        launchElevationMetresMsl,
        maximumAltitudeMetresMsl,
      }),
  });
}

export function forecastAltitudeStrategyTrack({
  field,
  launch,
  launchElevationMetresMsl,
  firstCruiseAltitudeMetresMsl,
  secondCruiseAltitudeMetresMsl,
  durationMinutes,
  stepSeconds = DEFAULT_STEP_SECONDS,
}) {
  return forecastTrackWithAltitudeProfile({
    field,
    launch,
    durationMinutes,
    stepSeconds,
    altitudeAtFraction: (fraction) =>
      altitudeForStrategyFraction({
        fraction,
        launchElevationMetresMsl,
        firstCruiseAltitudeMetresMsl,
        secondCruiseAltitudeMetresMsl,
      }),
  });
}

function strategyAltitudes(launchElevationMetresMsl, maximumAltitudeMetresMsl) {
  const launch = finiteNumber(launchElevationMetresMsl, "launch elevation");
  const maximum = finiteNumber(maximumAltitudeMetresMsl, "maximum altitude");
  if (maximum < launch) throw new RangeError("Maximum altitude must not be below launch.");
  return [...new Set([launch, maximum, ...WIND_LEVELS_METRES_MSL])]
    .filter((altitude) => altitude >= launch && altitude <= maximum)
    .sort((first, second) => first - second);
}

function convexHull(points) {
  const unique = [
    ...new Map(
      points.map((point) => [
        `${point.longitude.toFixed(8)},${point.latitude.toFixed(8)}`,
        validPoint(point),
      ]),
    ).values(),
  ].sort(
    (first, second) =>
      first.longitude - second.longitude || first.latitude - second.latitude,
  );
  if (unique.length <= 2) return unique;
  const cross = (origin, first, second) =>
    (first.longitude - origin.longitude) * (second.latitude - origin.latitude) -
    (first.latitude - origin.latitude) * (second.longitude - origin.longitude);
  const lower = [];
  for (const point of unique) {
    while (lower.length >= 2 && cross(lower.at(-2), lower.at(-1), point) <= 0) lower.pop();
    lower.push(point);
  }
  const upper = [];
  for (const point of [...unique].reverse()) {
    while (upper.length >= 2 && cross(upper.at(-2), upper.at(-1), point) <= 0) upper.pop();
    upper.push(point);
  }
  return [...lower.slice(0, -1), ...upper.slice(0, -1)];
}

export function forecastLandingEnvelope({
  field,
  launch,
  launchElevationMetresMsl,
  maximumAltitudeMetresMsl,
  durationMinutes,
  stepSeconds = DEFAULT_STEP_SECONDS,
}) {
  const altitudes = strategyAltitudes(
    launchElevationMetresMsl,
    maximumAltitudeMetresMsl,
  );
  const candidates = [];
  for (const firstCruiseAltitudeMetresMsl of altitudes) {
    for (const secondCruiseAltitudeMetresMsl of altitudes) {
      const track = forecastAltitudeStrategyTrack({
        field,
        launch,
        launchElevationMetresMsl,
        firstCruiseAltitudeMetresMsl,
        secondCruiseAltitudeMetresMsl,
        durationMinutes,
        stepSeconds,
      });
      candidates.push({
        firstCruiseAltitudeMetresMsl,
        secondCruiseAltitudeMetresMsl,
        track,
        landing: track.at(-1),
      });
    }
  }
  return Object.freeze({
    candidates: Object.freeze(candidates),
    boundary: Object.freeze(convexHull(candidates.map((candidate) => candidate.landing))),
  });
}

export function planWindRouteToDestination({
  field,
  launch,
  destination,
  launchElevationMetresMsl,
  maximumAltitudeMetresMsl,
  durationMinutes,
  stepSeconds = DEFAULT_STEP_SECONDS,
  toleranceMetres,
}) {
  const target = validPoint(destination, "destination");
  const envelope = forecastLandingEnvelope({
    field,
    launch,
    launchElevationMetresMsl,
    maximumAltitudeMetresMsl,
    durationMinutes,
    stepSeconds,
  });
  const ranked = envelope.candidates
    .map((candidate) => ({
      ...candidate,
      missDistanceMetres: distanceMetres(candidate.landing, target),
    }))
    .sort((first, second) => first.missDistanceMetres - second.missDistanceMetres);
  const best = ranked[0];
  const directDistanceMetres = distanceMetres(launch, target);
  const acceptedMissDistanceMetres = Number.isFinite(Number(toleranceMetres))
    ? Math.max(100, Number(toleranceMetres))
    : Math.max(1_000, Math.min(3_000, directDistanceMetres * 0.1));
  return Object.freeze({
    ...best,
    destination: target,
    directDistanceMetres,
    acceptedMissDistanceMetres,
    reachesDestination: best.missDistanceMetres <= acceptedMissDistanceMetres,
    boundary: envelope.boundary,
    candidateCount: envelope.candidates.length,
  });
}

export function circlePolygon(center, radiusMetres, segments = 48) {
  const origin = validPoint(center, "circle centre");
  const radius = finiteNumber(radiusMetres, "circle radius");
  if (radius <= 0 || segments < 8) throw new RangeError("Circle dimensions are invalid.");
  const coordinates = [];
  for (let index = 0; index <= segments; index += 1) {
    const bearing = (index / segments) * 2 * Math.PI;
    const north = Math.cos(bearing) * radius;
    const east = Math.sin(bearing) * radius;
    const latitude = origin.latitude + (north / EARTH_RADIUS_METRES) * (180 / Math.PI);
    const longitude =
      origin.longitude +
      (east / (EARTH_RADIUS_METRES * Math.max(0.01, Math.cos((origin.latitude * Math.PI) / 180)))) *
        (180 / Math.PI);
    coordinates.push([longitude, latitude]);
  }
  return coordinates;
}

function escapeXml(value) {
  return String(value).replace(/[<>&'\"]/g, (character) => {
    const replacements = {
      "<": "&lt;",
      ">": "&gt;",
      "&": "&amp;",
      "'": "&apos;",
      '\"': "&quot;",
    };
    return replacements[character];
  });
}

function waypointXml(point, name, symbol) {
  return `<wpt lat="${point.latitude.toFixed(7)}" lon="${point.longitude.toFixed(7)}">` +
    `<name>${escapeXml(name)}</name><sym>${escapeXml(symbol)}</sym></wpt>`;
}

export function buildFlightPlanGpx({
  name,
  track,
  departureAt,
  launch,
  forecastLanding,
  intendedLanding,
}) {
  if (!Array.isArray(track) || track.length < 2) throw new Error("A forecast track is required.");
  const departure = departureAt instanceof Date ? departureAt : new Date(departureAt);
  if (Number.isNaN(departure.getTime())) throw new TypeError("Departure time is invalid.");
  const safeName = String(name || "Balloon forecast flight plan").trim().slice(0, 200);
  const points = track
    .map((point) => {
      const time = new Date(departure.getTime() + point.elapsedSeconds * 1000).toISOString();
      return `<trkpt lat="${point.latitude.toFixed(7)}" lon="${point.longitude.toFixed(7)}">` +
        `<ele>${point.altitudeMetresMsl.toFixed(1)}</ele><time>${time}</time></trkpt>`;
    })
    .join("");
  return (
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<gpx version="1.1" creator="Balloon Crumbs pilot planner" ' +
    'xmlns="http://www.topografix.com/GPX/1/1">' +
    `<metadata><name>${escapeXml(safeName)}</name><desc>` +
    "Forecast-only wind drift. Not a controllable route or an aviation briefing." +
    "</desc></metadata>" +
    waypointXml(validPoint(launch), "Launch", "Launch") +
    waypointXml(validPoint(forecastLanding), "Forecast landing", "Forecast landing") +
    waypointXml(validPoint(intendedLanding), "Pilot intended landing area", "Landing area") +
    `<trk><name>${escapeXml(safeName)}</name><type>balloon-flight-forecast</type>` +
    `<trkseg>${points}</trkseg></trk></gpx>`
  );
}

export function forecastDistanceMetres(track) {
  let total = 0;
  for (let index = 1; index < track.length; index += 1) {
    total += distanceMetres(track[index - 1], track[index]);
  }
  return total;
}
