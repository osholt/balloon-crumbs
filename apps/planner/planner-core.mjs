export const WIND_LEVELS_METRES_MSL = Object.freeze([
  20, 50, 100, 150, 200, 300, 400, 500, 600, 800, 1000, 1250, 1500, 2000,
]);

const EARTH_RADIUS_METRES = 6_371_000;
const DEFAULT_STEP_SECONDS = 60;
export const WIND_GRID_SIDE_POINTS = 5;
export const WIND_GRID_SPAN_METRES = 120_000;
export const ROUTE_SEARCH_LIMITS = Object.freeze({
  minimumDurationMinutes: 10,
  maximumDurationMinutes: 180,
  altitudeCeilingMetresMsl: 2000,
  acceptedMissDistanceMetres: 100,
});
export const ROUTE_CONTROL_FRACTIONS = Object.freeze([0, 0.2, 0.4, 0.6, 0.8, 1]);

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
  const halfSpanMetres = WIND_GRID_SPAN_METRES / 2;
  const stepMetres = WIND_GRID_SPAN_METRES / (WIND_GRID_SIDE_POINTS - 1);
  const longitudeScale = Math.max(0.01, Math.cos((origin.latitude * Math.PI) / 180));
  const points = [];
  for (let northIndex = 0; northIndex < WIND_GRID_SIDE_POINTS; northIndex += 1) {
    const northMetres = -halfSpanMetres + northIndex * stepMetres;
    const latitude = Math.max(
      -90,
      Math.min(90, origin.latitude + (northMetres / EARTH_RADIUS_METRES) * (180 / Math.PI)),
    );
    for (let eastIndex = 0; eastIndex < WIND_GRID_SIDE_POINTS; eastIndex += 1) {
      const eastMetres = -halfSpanMetres + eastIndex * stepMetres;
      const longitude = Math.max(
        -180,
        Math.min(
          180,
          origin.longitude +
            (eastMetres / (EARTH_RADIUS_METRES * longitudeScale)) * (180 / Math.PI),
        ),
      );
      points.push({ latitude, longitude });
    }
  }
  return Object.freeze(points);
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
  const slicesByTime = new Map();

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
    for (let timeIndex = 0; timeIndex < times.length; timeIndex += 1) {
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
      const epoch = times[timeIndex].getTime();
      const slice = slicesByTime.get(epoch) ?? { validAt: times[timeIndex], columns: [] };
      slice.columns.push({ position, vectors });
      slicesByTime.set(epoch, slice);
    }
  }

  const timeSlices = [...slicesByTime.values()]
    .filter((slice) => slice.columns.length > 0)
    .sort((first, second) => first.validAt - second.validAt);
  if (timeSlices.length === 0) {
    throw new Error("Open-Meteo returned no usable wind profiles for this time and place.");
  }
  const selected = timeSlices[nearestTimeIndex(timeSlices.map((slice) => slice.validAt), target)];
  return {
    columns: selected.columns,
    validAt: selected.validAt,
    requestedAt: target,
    timeSlices,
  };
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

function vectorInColumns(columns, position, altitudeMetresMsl) {
  if (columns.length === 0) return null;
  let nearest = columns[0];
  let nearestDistance = distanceMetres(nearest.position, position);
  for (let index = 1; index < columns.length; index += 1) {
    const candidateDistance = distanceMetres(columns[index].position, position);
    if (candidateDistance >= nearestDistance) continue;
    nearest = columns[index];
    nearestDistance = candidateDistance;
  }
  return vectorAtAltitude(nearest, altitudeMetresMsl);
}

export function interpolatedVectorAtPosition(field, position, altitudeMetresMsl) {
  const candidates = (field?.columns ?? [])
    .map((column) => ({
      distanceMetres: distanceMetres(column.position, position),
      vector: vectorAtAltitude(column, altitudeMetresMsl),
    }))
    .filter((candidate) => candidate.vector)
    .sort((first, second) => first.distanceMetres - second.distanceMetres)
    .slice(0, 4);
  if (candidates.length === 0) return null;
  if (candidates[0].distanceMetres < 1) return candidates[0].vector;
  let totalWeight = 0;
  let eastMetresPerSecond = 0;
  let northMetresPerSecond = 0;
  for (const candidate of candidates) {
    const weight = 1 / candidate.distanceMetres ** 2;
    const candidateComponents = components(candidate.vector);
    totalWeight += weight;
    eastMetresPerSecond += candidateComponents.eastMetresPerSecond * weight;
    northMetresPerSecond += candidateComponents.northMetresPerSecond * weight;
  }
  return vectorFromComponents(
    altitudeMetresMsl,
    eastMetresPerSecond / totalWeight,
    northMetresPerSecond / totalWeight,
  );
}

export function vectorAtPosition(field, position, altitudeMetresMsl, elapsedSeconds = 0) {
  const slices = field?.timeSlices ?? [];
  if (slices.length === 0) {
    return vectorInColumns(field?.columns ?? [], position, altitudeMetresMsl);
  }
  const requestedAt = field.requestedAt instanceof Date ? field.requestedAt : field.validAt;
  const targetTime = requestedAt.getTime() + finiteNumber(elapsedSeconds, "elapsed seconds") * 1000;
  let upperIndex = slices.findIndex((slice) => slice.validAt.getTime() >= targetTime);
  if (upperIndex < 0) upperIndex = slices.length - 1;
  const lowerIndex = Math.max(0, upperIndex - 1);
  const lower = slices[lowerIndex];
  const upper = slices[upperIndex];
  const lowerVector = vectorInColumns(lower.columns, position, altitudeMetresMsl);
  const upperVector = vectorInColumns(upper.columns, position, altitudeMetresMsl);
  if (!lowerVector) return upperVector;
  if (!upperVector || lowerIndex === upperIndex) return lowerVector;
  const interval = upper.validAt.getTime() - lower.validAt.getTime();
  const fraction =
    interval <= 0
      ? 0
      : Math.max(0, Math.min(1, (targetTime - lower.validAt.getTime()) / interval));
  const lowerComponents = components(lowerVector);
  const upperComponents = components(upperVector);
  return vectorFromComponents(
    altitudeMetresMsl,
    lowerComponents.eastMetresPerSecond +
      (upperComponents.eastMetresPerSecond - lowerComponents.eastMetresPerSecond) * fraction,
    lowerComponents.northMetresPerSecond +
      (upperComponents.northMetresPerSecond - lowerComponents.northMetresPerSecond) * fraction,
  );
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

export function altitudeForProfileFraction({
  fraction,
  launchElevationMetresMsl,
  controlAltitudesMetresMsl,
}) {
  const progress = Math.max(0, Math.min(1, finiteNumber(fraction, "flight fraction")));
  const launch = finiteNumber(launchElevationMetresMsl, "launch elevation");
  if (!Array.isArray(controlAltitudesMetresMsl) || controlAltitudesMetresMsl.length !== 4) {
    throw new RangeError("An altitude profile requires four in-flight control heights.");
  }
  const altitudes = [
    launch,
    ...controlAltitudesMetresMsl.map((altitude, index) =>
      Math.max(launch, finiteNumber(altitude, `control altitude ${index + 1}`)),
    ),
    launch,
  ];
  if (progress >= 1) return launch;
  const segment = Math.min(4, Math.floor(progress / 0.2));
  const segmentProgress = (progress - ROUTE_CONTROL_FRACTIONS[segment]) / 0.2;
  return altitudes[segment] + (altitudes[segment + 1] - altitudes[segment]) * segmentProgress;
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
  let elapsedSeconds = 0;
  while (true) {
    const fraction = elapsedSeconds / durationSeconds;
    const altitudeMetresMsl = altitudeAtFraction(fraction);
    const vector = vectorAtPosition(field, position, altitudeMetresMsl, elapsedSeconds);
    if (!vector) throw new Error("The wind field does not cover the forecast flight.");
    points.push({ ...position, altitudeMetresMsl, elapsedSeconds, wind: vector });
    if (elapsedSeconds >= durationSeconds) break;
    const nextElapsedSeconds = Math.min(durationSeconds, elapsedSeconds + step);
    position = moveWithWind(position, vector, nextElapsedSeconds - elapsedSeconds);
    elapsedSeconds = nextElapsedSeconds;
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

export function forecastAltitudeProfileTrack({
  field,
  launch,
  launchElevationMetresMsl,
  controlAltitudesMetresMsl,
  durationMinutes,
  stepSeconds = DEFAULT_STEP_SECONDS,
}) {
  return forecastTrackWithAltitudeProfile({
    field,
    launch,
    durationMinutes,
    stepSeconds,
    altitudeAtFraction: (fraction) =>
      altitudeForProfileFraction({
        fraction,
        launchElevationMetresMsl,
        controlAltitudesMetresMsl,
      }),
  });
}

function strategyAltitudes(launchElevationMetresMsl, altitudeCeilingMetresMsl) {
  const launch = finiteNumber(launchElevationMetresMsl, "launch elevation");
  const ceiling = finiteNumber(altitudeCeilingMetresMsl, "altitude ceiling");
  if (ceiling < launch) throw new RangeError("Altitude ceiling must not be below launch.");
  return [...new Set([launch, ceiling, ...WIND_LEVELS_METRES_MSL])]
    .filter((altitude) => altitude >= launch && altitude <= ceiling)
    .sort((first, second) => first - second);
}

function routeDurations(minimumDurationMinutes, maximumDurationMinutes, stepMinutes = 10) {
  const minimum = finiteNumber(minimumDurationMinutes, "minimum route duration");
  const maximum = finiteNumber(maximumDurationMinutes, "maximum route duration");
  const step = finiteNumber(stepMinutes, "route duration step");
  if (minimum < 10 || maximum > 180 || minimum > maximum || step <= 0) {
    throw new RangeError("Route duration search is outside the supported range.");
  }
  const durations = [];
  for (let duration = minimum; duration <= maximum; duration += step) durations.push(duration);
  if (durations.at(-1) !== maximum) durations.push(maximum);
  return durations;
}

function profileIsFeasible({
  controlAltitudesMetresMsl,
  launchElevationMetresMsl,
  altitudeCeilingMetresMsl,
  durationMinutes,
  maximumVerticalRateMetresPerSecond,
}) {
  const launch = finiteNumber(launchElevationMetresMsl, "launch elevation");
  const ceiling = finiteNumber(altitudeCeilingMetresMsl, "altitude ceiling");
  const segmentSeconds = (finiteNumber(durationMinutes, "flight duration") * 60) / 5;
  const altitudes = [launch, ...controlAltitudesMetresMsl, launch];
  if (
    altitudes.some(
      (altitude) => !Number.isFinite(altitude) || altitude < launch || altitude > ceiling,
    )
  ) {
    return false;
  }
  return altitudes.slice(1).every(
    (altitude, index) =>
      Math.abs(altitude - altitudes[index]) / segmentSeconds <=
      maximumVerticalRateMetresPerSecond,
  );
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

function coarseLandingCandidates({
  field,
  launch,
  launchElevationMetresMsl,
  destination,
  minimumDurationMinutes,
  maximumDurationMinutes,
  altitudeCeilingMetresMsl,
  maximumVerticalRateMetresPerSecond,
  stepSeconds = DEFAULT_STEP_SECONDS,
}) {
  const target = destination ? validPoint(destination, "destination") : null;
  const altitudes = strategyAltitudes(launchElevationMetresMsl, altitudeCeilingMetresMsl);
  const durations = routeDurations(
    minimumDurationMinutes,
    maximumDurationMinutes,
  );
  const candidates = [];
  for (const durationMinutes of durations) {
    for (const firstAltitude of altitudes) {
      for (const secondAltitude of altitudes) {
        const controlAltitudesMetresMsl = [
          firstAltitude,
          firstAltitude,
          secondAltitude,
          secondAltitude,
        ];
        if (
          !profileIsFeasible({
            controlAltitudesMetresMsl,
            launchElevationMetresMsl,
            altitudeCeilingMetresMsl,
            durationMinutes,
            maximumVerticalRateMetresPerSecond,
          })
        ) {
          continue;
        }
        const track = forecastAltitudeProfileTrack({
          field,
          launch,
          launchElevationMetresMsl,
          controlAltitudesMetresMsl,
          durationMinutes,
          stepSeconds,
        });
        const landing = track.at(-1);
        candidates.push({
          durationMinutes,
          controlAltitudesMetresMsl,
          peakAltitudeMetresMsl: Math.max(launchElevationMetresMsl, ...controlAltitudesMetresMsl),
          landing,
          ...(target ? { missDistanceMetres: distanceMetres(landing, target) } : {}),
        });
      }
    }
  }
  return candidates;
}

function routeSearchSettings(options) {
  const minimumDurationMinutes =
    options.minimumDurationMinutes ?? ROUTE_SEARCH_LIMITS.minimumDurationMinutes;
  const maximumDurationMinutes =
    options.maximumDurationMinutes ?? ROUTE_SEARCH_LIMITS.maximumDurationMinutes;
  const altitudeCeilingMetresMsl =
    options.altitudeCeilingMetresMsl ?? ROUTE_SEARCH_LIMITS.altitudeCeilingMetresMsl;
  const maximumVerticalRateMetresPerSecond = options.maximumVerticalRateMetresPerSecond ?? 5;
  routeDurations(minimumDurationMinutes, maximumDurationMinutes);
  if (altitudeCeilingMetresMsl < options.launchElevationMetresMsl) {
    throw new RangeError("Altitude ceiling must not be below launch.");
  }
  return {
    minimumDurationMinutes,
    maximumDurationMinutes,
    altitudeCeilingMetresMsl,
    maximumVerticalRateMetresPerSecond,
  };
}

export function forecastLandingEnvelope(options) {
  const settings = routeSearchSettings(options);
  const candidates = coarseLandingCandidates({ ...options, ...settings });
  return Object.freeze({
    candidates: Object.freeze(candidates),
    boundary: Object.freeze(convexHull(candidates.map((candidate) => candidate.landing))),
    ...settings,
  });
}

function routeCandidateKey(durationMinutes, controlAltitudesMetresMsl) {
  return `${Math.round(durationMinutes * 60)}:${controlAltitudesMetresMsl
    .map((altitude) => Math.round(altitude))
    .join(",")}`;
}

function bestUniqueCandidates(candidates, limit) {
  const unique = new Map();
  for (const candidate of candidates) {
    const key = routeCandidateKey(candidate.durationMinutes, candidate.controlAltitudesMetresMsl);
    const existing = unique.get(key);
    if (!existing || candidate.missDistanceMetres < existing.missDistanceMetres) {
      unique.set(key, candidate);
    }
  }
  return [...unique.values()]
    .sort((first, second) => first.missDistanceMetres - second.missDistanceMetres)
    .slice(0, limit);
}

export function planWindRouteToDestination(options) {
  const {
    field,
    launch,
    destination,
    launchElevationMetresMsl,
    stepSeconds = DEFAULT_STEP_SECONDS,
  } = options;
  const target = validPoint(destination, "destination");
  const settings = routeSearchSettings(options);
  const coarseCandidates = coarseLandingCandidates({
    ...options,
    ...settings,
    destination: target,
    stepSeconds,
  });
  if (coarseCandidates.length === 0) {
    throw new Error("No feasible altitude profiles were available inside the route-search limits.");
  }
  const altitudeLevels = strategyAltitudes(
    launchElevationMetresMsl,
    settings.altitudeCeilingMetresMsl,
  );
  const evaluationCache = new Map();
  const evaluate = (durationMinutes, controlAltitudesMetresMsl) => {
    const boundedDurationMinutes = Math.max(
      settings.minimumDurationMinutes,
      Math.min(settings.maximumDurationMinutes, Math.round(durationMinutes * 60) / 60),
    );
    const boundedAltitudes = controlAltitudesMetresMsl.map((altitude) =>
      Math.max(
        launchElevationMetresMsl,
        Math.min(settings.altitudeCeilingMetresMsl, Math.round(altitude)),
      ),
    );
    const key = routeCandidateKey(boundedDurationMinutes, boundedAltitudes);
    if (evaluationCache.has(key)) return evaluationCache.get(key);
    if (
      !profileIsFeasible({
        controlAltitudesMetresMsl: boundedAltitudes,
        launchElevationMetresMsl,
        altitudeCeilingMetresMsl: settings.altitudeCeilingMetresMsl,
        durationMinutes: boundedDurationMinutes,
        maximumVerticalRateMetresPerSecond: settings.maximumVerticalRateMetresPerSecond,
      })
    ) {
      evaluationCache.set(key, null);
      return null;
    }
    const track = forecastAltitudeProfileTrack({
      field,
      launch,
      launchElevationMetresMsl,
      controlAltitudesMetresMsl: boundedAltitudes,
      durationMinutes: boundedDurationMinutes,
      stepSeconds,
    });
    const landing = track.at(-1);
    const candidate = {
      durationMinutes: boundedDurationMinutes,
      controlAltitudesMetresMsl: boundedAltitudes,
      peakAltitudeMetresMsl: Math.max(launchElevationMetresMsl, ...boundedAltitudes),
      track,
      landing,
      missDistanceMetres: distanceMetres(landing, target),
    };
    evaluationCache.set(key, candidate);
    return candidate;
  };

  let beam = bestUniqueCandidates(coarseCandidates, 10)
    .map((candidate) =>
      evaluate(candidate.durationMinutes, candidate.controlAltitudesMetresMsl),
    )
    .filter(Boolean);
  for (let pass = 0; pass < 2; pass += 1) {
    for (let controlIndex = 0; controlIndex < 4; controlIndex += 1) {
      const expanded = [...beam];
      for (const seed of beam) {
        for (const altitude of altitudeLevels) {
          const controlAltitudes = [...seed.controlAltitudesMetresMsl];
          controlAltitudes[controlIndex] = altitude;
          const candidate = evaluate(seed.durationMinutes, controlAltitudes);
          if (candidate) expanded.push(candidate);
        }
      }
      beam = bestUniqueCandidates(expanded, 10);
    }
  }

  const refinementScales = [
    [300, 200],
    [120, 100],
    [60, 50],
    [30, 20],
    [10, 10],
    [5, 5],
    [1, 1],
  ];
  const refined = [];
  for (const seed of beam.slice(0, 4)) {
    let best = seed;
    for (const [durationStepSeconds, altitudeStepMetres] of refinementScales) {
      for (let attempt = 0; attempt < 6; attempt += 1) {
        const neighbours = [best];
        for (const direction of [-1, 1]) {
          const durationCandidate = evaluate(
            best.durationMinutes + (direction * durationStepSeconds) / 60,
            best.controlAltitudesMetresMsl,
          );
          if (durationCandidate) neighbours.push(durationCandidate);
          for (let controlIndex = 0; controlIndex < 4; controlIndex += 1) {
            const controlAltitudes = [...best.controlAltitudesMetresMsl];
            controlAltitudes[controlIndex] += direction * altitudeStepMetres;
            const altitudeCandidate = evaluate(best.durationMinutes, controlAltitudes);
            if (altitudeCandidate) neighbours.push(altitudeCandidate);
          }
        }
        const nextBest = bestUniqueCandidates(neighbours, 1)[0];
        if (nextBest.missDistanceMetres >= best.missDistanceMetres - 0.01) break;
        best = nextBest;
      }
    }
    refined.push(best);
  }
  const best = bestUniqueCandidates([...beam, ...refined], 1)[0];
  const directDistanceMetres = distanceMetres(launch, target);
  const acceptedMissDistanceMetres = ROUTE_SEARCH_LIMITS.acceptedMissDistanceMetres;
  return Object.freeze({
    ...best,
    destination: target,
    directDistanceMetres,
    acceptedMissDistanceMetres,
    reachesDestination: best.missDistanceMetres <= acceptedMissDistanceMetres,
    boundary: Object.freeze(convexHull(coarseCandidates.map((candidate) => candidate.landing))),
    candidateCount: coarseCandidates.length,
    evaluatedCandidateCount: [...evaluationCache.values()].filter(Boolean).length,
    ...settings,
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
