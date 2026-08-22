import assert from "node:assert/strict";
import test from "node:test";

import {
  WIND_GRID_SIDE_POINTS,
  WIND_GRID_SPAN_METRES,
  WIND_LEVELS_METRES_MSL,
  altitudeForFlightFraction,
  altitudeForProfileFraction,
  altitudeForStrategyFraction,
  buildFlightPlanGpx,
  circlePolygon,
  forecastAltitudeProfileTrack,
  forecastLandingEnvelope,
  forecastRepresentativeRoute,
  forecastFlightTrack,
  interpolatedVectorAtPosition,
  moveWithWind,
  openMeteoRequestUrl,
  parseOpenMeteoForecast,
  planWindRouteToDestination,
  vectorAtAltitude,
  vectorAtPosition,
  windForecastGrid,
} from "./planner-core.mjs";

function payload({ direction = 270, speed = 36 } = {}) {
  const hourly = { time: ["2026-08-21T08:00", "2026-08-21T09:00"] };
  for (const altitude of WIND_LEVELS_METRES_MSL) {
    hourly[`wind_speed_${altitude}m`] = [speed, speed];
    hourly[`wind_direction_${altitude}m`] = [direction, direction];
  }
  return { latitude: 51.5, longitude: -2.5, hourly };
}

test("wind request covers a bounded wide-area UKMO grid and height levels", () => {
  const centre = { latitude: 51.5, longitude: -2.5 };
  const grid = windForecastGrid(centre);
  assert.equal(grid.length, WIND_GRID_SIDE_POINTS ** 2);
  assert.equal(WIND_GRID_SPAN_METRES, 120_000);
  assert.ok(grid.some((point) => point.latitude === centre.latitude));
  assert.ok(grid.some((point) => point.longitude === centre.longitude));
  assert.ok(
    Math.max(...grid.map((point) => point.latitude)) -
      Math.min(...grid.map((point) => point.latitude)) >
      1,
  );
  assert.ok(
    Math.max(...grid.map((point) => point.longitude)) -
      Math.min(...grid.map((point) => point.longitude)) >
      1.5,
  );
  const url = openMeteoRequestUrl({ endpoint: "/weather/v1/forecast", center: centre });
  assert.equal(url.pathname, "/weather/v1/forecast");
  assert.equal(url.searchParams.get("models"), "ukmo_seamless");
  assert.equal(url.searchParams.get("forecast_days"), "3");
  assert.equal(url.searchParams.get("latitude").split(",").length, 25);
  assert.match(url.searchParams.get("hourly"), /wind_speed_500m/);
  assert.match(url.searchParams.get("hourly"), /wind_direction_2000m/);
});

test("forecast parser chooses the hour nearest the pilot's departure", () => {
  const source = payload();
  source.hourly.wind_speed_500m = [12, 28];
  const field = parseOpenMeteoForecast(source, new Date("2026-08-21T08:52:00Z"));
  assert.equal(field.validAt.toISOString(), "2026-08-21T09:00:00.000Z");
  assert.equal(vectorAtAltitude(field.columns[0], 500).speedKmh, 28);
});

test("wind vectors interpolate between hourly forecast slices during the flight", () => {
  const source = payload();
  source.hourly.wind_direction_500m = [270, 180];
  const field = parseOpenMeteoForecast(source, new Date("2026-08-21T08:00:00Z"));
  const vector = vectorAtPosition(
    field,
    { latitude: 51.5, longitude: -2.5 },
    500,
    30 * 60,
  );
  assert.ok(Math.abs(vector.fromDegrees - 225) < 0.1);
  assert.ok(Math.abs(vector.speedKmh - 25.46) < 0.1);
});

test("spatially interpolated display vectors follow the chosen start time", () => {
  const source = payload();
  source.hourly.wind_direction_500m = [270, 180];
  const field = parseOpenMeteoForecast(source, new Date("2026-08-21T08:00:00Z"));
  const vector = interpolatedVectorAtPosition(
    field,
    { latitude: 51.5, longitude: -2.5 },
    500,
    30 * 60,
  );
  assert.ok(Math.abs(vector.fromDegrees - 225) < 0.1);
  assert.ok(Math.abs(vector.speedKmh - 25.46) < 0.1);
});

test("vertical interpolation crosses north without wrapping south", () => {
  const vector = vectorAtAltitude(
    {
      vectors: [
        { altitudeMetresMsl: 100, speedKmh: 36, fromDegrees: 350 },
        { altitudeMetresMsl: 200, speedKmh: 36, fromDegrees: 10 },
      ],
    },
    150,
  );
  assert.ok(vector.fromDegrees < 1 || vector.fromDegrees > 359);
  assert.ok(Math.abs(vector.speedKmh - 35.45) < 0.1);
});

test("wind display interpolates direction and speed between nearby source points", () => {
  const field = {
    columns: [
      [-0.1, -0.1, 270],
      [0.1, -0.1, 180],
      [-0.1, 0.1, 270],
      [0.1, 0.1, 180],
    ].map(([latitude, longitude, fromDegrees]) => ({
      position: { latitude, longitude },
      vectors: [{ altitudeMetresMsl: 500, speedKmh: 36, fromDegrees }],
    })),
  };
  const vector = interpolatedVectorAtPosition(
    field,
    { latitude: 0, longitude: 0 },
    500,
  );
  assert.ok(Math.abs(vector.fromDegrees - 225) < 0.1);
  assert.ok(Math.abs(vector.speedKmh - 25.46) < 0.1);
});

test("flight profile climbs, cruises and returns to launch elevation", () => {
  const settings = { launchElevationMetresMsl: 80, maximumAltitudeMetresMsl: 1000 };
  assert.equal(altitudeForFlightFraction({ fraction: 0, ...settings }), 80);
  assert.equal(altitudeForFlightFraction({ fraction: 0.2, ...settings }), 1000);
  assert.equal(altitudeForFlightFraction({ fraction: 0.6, ...settings }), 1000);
  assert.ok(Math.abs(altitudeForFlightFraction({ fraction: 1, ...settings }) - 80) < 1e-9);
});

test("destination strategy can use two different cruise wind layers and still land", () => {
  const settings = {
    launchElevationMetresMsl: 100,
    firstCruiseAltitudeMetresMsl: 300,
    secondCruiseAltitudeMetresMsl: 900,
  };
  assert.equal(altitudeForStrategyFraction({ fraction: 0, ...settings }), 100);
  assert.equal(altitudeForStrategyFraction({ fraction: 0.3, ...settings }), 300);
  assert.equal(altitudeForStrategyFraction({ fraction: 0.5, ...settings }), 600);
  assert.equal(altitudeForStrategyFraction({ fraction: 0.6, ...settings }), 900);
  assert.equal(altitudeForStrategyFraction({ fraction: 1, ...settings }), 100);
});

test("multi-stage altitude profiles interpolate four controls and return to launch", () => {
  const settings = {
    launchElevationMetresMsl: 100,
    controlAltitudesMetresMsl: [300, 700, 500, 900],
  };
  assert.equal(altitudeForProfileFraction({ fraction: 0, ...settings }), 100);
  assert.equal(altitudeForProfileFraction({ fraction: 0.1, ...settings }), 200);
  assert.equal(altitudeForProfileFraction({ fraction: 0.2, ...settings }), 300);
  assert.equal(altitudeForProfileFraction({ fraction: 0.4, ...settings }), 700);
  assert.equal(altitudeForProfileFraction({ fraction: 0.8, ...settings }), 900);
  assert.equal(altitudeForProfileFraction({ fraction: 1, ...settings }), 100);
});

test("forecast track follows wind while maintaining its own altitude profile", () => {
  const field = parseOpenMeteoForecast(payload(), new Date("2026-08-21T08:00:00Z"));
  const track = forecastFlightTrack({
    field,
    launch: { latitude: 51.5, longitude: -2.5 },
    launchElevationMetresMsl: 100,
    maximumAltitudeMetresMsl: 900,
    durationMinutes: 30,
  });
  assert.equal(track.length, 31);
  assert.ok(track.at(-1).longitude > track[0].longitude);
  assert.ok(Math.abs(track.at(-1).latitude - track[0].latitude) < 0.001);
  assert.equal(track[0].altitudeMetresMsl, 100);
  assert.ok(Math.abs(track.at(-1).altitudeMetresMsl - 100) < 1e-9);
});

test("forecast track can start from a later wind slice on the selected day", () => {
  const source = payload();
  for (const altitude of WIND_LEVELS_METRES_MSL) {
    source.hourly[`wind_direction_${altitude}m`] = [270, 180];
  }
  const field = parseOpenMeteoForecast(source, new Date("2026-08-21T08:00:00Z"));
  const track = forecastFlightTrack({
    field,
    launch: { latitude: 51.5, longitude: -2.5 },
    launchElevationMetresMsl: 100,
    maximumAltitudeMetresMsl: 100,
    durationMinutes: 10,
    departureOffsetSeconds: 60 * 60,
  });
  assert.ok(track.at(-1).latitude > track[0].latitude);
  assert.ok(Math.abs(track.at(-1).longitude - track[0].longitude) < 0.001);
});

test("launch-only forecast reports a representative track and flight details", () => {
  const field = parseOpenMeteoForecast(payload(), new Date("2026-08-21T08:00:00Z"));
  const route = forecastRepresentativeRoute({
    field,
    launch: { latitude: 51.5, longitude: -2.5 },
    launchElevationMetresMsl: 100,
    departureOffsetMinutes: 60,
  });
  assert.equal(route.kind, "representative");
  assert.equal(route.departureAt.toISOString(), "2026-08-21T09:00:00.000Z");
  assert.equal(route.durationMinutes, 60);
  assert.equal(route.peakAltitudeMetresMsl, 500);
  assert.equal(route.track.length, 61);
  assert.deepEqual(route.landing, route.track.at(-1));
  assert.ok(route.landing.longitude > route.track[0].longitude);
});

test("representative forecast respects independent ascent and descent limits", () => {
  const field = parseOpenMeteoForecast(payload(), new Date("2026-08-21T08:00:00Z"));
  const route = forecastRepresentativeRoute({
    field,
    launch: { latitude: 51.5, longitude: -2.5 },
    launchElevationMetresMsl: 100,
    durationMinutes: 60,
    cruiseAltitudeMetresMsl: 1000,
    maximumAscentRateMetresPerSecond: 0.2,
    maximumDescentRateMetresPerSecond: 0.1,
  });
  assert.equal(route.peakAltitudeMetresMsl, 208);
  assert.equal(route.maximumAscentRateMetresPerSecond, 0.2);
  assert.equal(route.maximumDescentRateMetresPerSecond, 0.1);
});

test("maximum altitude constrains the representative track and landing envelope", () => {
  const source = payload();
  for (const altitude of WIND_LEVELS_METRES_MSL) {
    source.hourly[`wind_direction_${altitude}m`] =
      altitude <= 100 ? [270, 270] : [180, 180];
  }
  const field = parseOpenMeteoForecast(source, new Date("2026-08-21T08:00:00Z"));
  const launch = { latitude: 51.5, longitude: -2.5 };
  const representative = forecastRepresentativeRoute({
    field,
    launch,
    launchElevationMetresMsl: 100,
    altitudeCeilingMetresMsl: 300,
  });
  assert.equal(representative.peakAltitudeMetresMsl, 300);
  assert.ok(
    representative.track.every((point) => point.altitudeMetresMsl <= 300),
  );

  const lowEnvelope = forecastLandingEnvelope({
    field,
    launch,
    launchElevationMetresMsl: 100,
    altitudeCeilingMetresMsl: 100,
    minimumDurationMinutes: 40,
    maximumDurationMinutes: 40,
  });
  const highEnvelope = forecastLandingEnvelope({
    field,
    launch,
    launchElevationMetresMsl: 100,
    altitudeCeilingMetresMsl: 1000,
    minimumDurationMinutes: 40,
    maximumDurationMinutes: 40,
  });
  assert.ok(lowEnvelope.candidates.every((candidate) => candidate.peakAltitudeMetresMsl <= 100));
  assert.ok(highEnvelope.candidates.some((candidate) => candidate.peakAltitudeMetresMsl > 100));
  assert.notDeepEqual(lowEnvelope.boundary, highEnvelope.boundary);
  const constrainedRoute = planWindRouteToDestination({
    field,
    launch,
    destination: highEnvelope.candidates.at(-1).landing,
    launchElevationMetresMsl: 100,
    altitudeCeilingMetresMsl: 300,
    minimumDurationMinutes: 40,
    maximumDurationMinutes: 40,
  });
  assert.ok(constrainedRoute.peakAltitudeMetresMsl <= 300);
  assert.ok(constrainedRoute.controlAltitudesMetresMsl.every((altitude) => altitude <= 300));
});

test("landing envelope applies adjustable ascent and descent limits independently", () => {
  const field = parseOpenMeteoForecast(payload(), new Date("2026-08-21T08:00:00Z"));
  const settings = {
    field,
    launch: { latitude: 51.5, longitude: -2.5 },
    launchElevationMetresMsl: 100,
    altitudeCeilingMetresMsl: 1000,
    minimumDurationMinutes: 10,
    maximumDurationMinutes: 10,
  };
  const ascentLimited = forecastLandingEnvelope({
    ...settings,
    maximumAscentRateMetresPerSecond: 0.5,
    maximumDescentRateMetresPerSecond: 10,
  });
  const descentLimited = forecastLandingEnvelope({
    ...settings,
    maximumAscentRateMetresPerSecond: 10,
    maximumDescentRateMetresPerSecond: 0.5,
  });
  const segmentSeconds = 120;
  const rates = (candidate) => {
    const altitudes = [100, ...candidate.controlAltitudesMetresMsl, 100];
    return altitudes.slice(1).map(
      (altitude, index) => (altitude - altitudes[index]) / segmentSeconds,
    );
  };
  assert.ok(
    ascentLimited.candidates.every((candidate) =>
      rates(candidate).every((rate) => rate <= 0.5 + Number.EPSILON),
    ),
  );
  assert.ok(
    ascentLimited.candidates.some((candidate) =>
      rates(candidate).some((rate) => rate < -0.5),
    ),
  );
  assert.ok(
    descentLimited.candidates.every((candidate) =>
      rates(candidate).every((rate) => rate >= -0.5 - Number.EPSILON),
    ),
  );
  assert.ok(
    descentLimited.candidates.some((candidate) =>
      rates(candidate).some((rate) => rate > 0.5),
    ),
  );
  assert.throws(
    () =>
      forecastLandingEnvelope({
        ...settings,
        maximumAscentRateMetresPerSecond: 0,
      }),
    /greater than zero/,
  );
});

test("wind routing chooses duration automatically and refines a reachable endpoint within 100 m", () => {
  const launch = { latitude: 51.5, longitude: -2.5 };
  const vector = { altitudeMetresMsl: 100, speedKmh: 36, fromDegrees: 270 };
  const field = {
    columns: [
      {
        position: launch,
        vectors: [vector, { ...vector, altitudeMetresMsl: 1000 }],
      },
    ],
  };
  const destination = moveWithWind(launch, vector, 1000);
  const result = planWindRouteToDestination({
    field,
    launch,
    destination,
    launchElevationMetresMsl: 100,
    minimumDurationMinutes: 10,
    maximumDurationMinutes: 30,
    altitudeCeilingMetresMsl: 1000,
  });
  assert.equal(result.reachesDestination, true);
  assert.equal(result.acceptedMissDistanceMetres, 100);
  assert.ok(result.missDistanceMetres < 1);
  assert.ok(Math.abs(result.durationMinutes - 1000 / 60) < 0.02);
  assert.equal(result.controlAltitudesMetresMsl.length, 4);
  assert.equal(result.track.at(-1).elapsedSeconds, 1000);
});

test("wind routing changes a multi-stage altitude profile and reports impossible targets", () => {
  const launch = { latitude: 51.5, longitude: -2.5 };
  const field = {
    columns: [
      {
        position: launch,
        vectors: [
          { altitudeMetresMsl: 100, speedKmh: 36, fromDegrees: 270 },
          { altitudeMetresMsl: 1000, speedKmh: 36, fromDegrees: 180 },
        ],
      },
    ],
  };
  const settings = {
    field,
    launch,
    launchElevationMetresMsl: 100,
    minimumDurationMinutes: 40,
    maximumDurationMinutes: 100,
    altitudeCeilingMetresMsl: 1000,
  };
  const knownTrack = forecastAltitudeProfileTrack({
    field,
    launch,
    launchElevationMetresMsl: 100,
    controlAltitudesMetresMsl: [100, 1000, 100, 1000],
    durationMinutes: 73,
  });
  const envelope = forecastLandingEnvelope(settings);
  assert.ok(envelope.candidates.length > 100);
  assert.ok(envelope.boundary.length >= 3);

  const possible = planWindRouteToDestination({
    ...settings,
    destination: knownTrack.at(-1),
  });
  assert.equal(possible.reachesDestination, true);
  assert.ok(possible.missDistanceMetres < 100);
  assert.equal(possible.track.at(-1).altitudeMetresMsl, 100);
  assert.equal(possible.controlAltitudesMetresMsl.length, 4);
  assert.equal(
    possible.peakAltitudeMetresMsl,
    Math.max(100, ...possible.controlAltitudesMetresMsl),
  );

  const impossible = planWindRouteToDestination({
    ...settings,
    destination: { latitude: 51.5, longitude: -3.0 },
  });
  assert.equal(impossible.reachesDestination, false);
  assert.ok(impossible.missDistanceMetres > 20_000);
});

test("wind routing chooses a start time and reports its matching window", () => {
  const launch = { latitude: 51.5, longitude: -2.5 };
  const source = payload();
  source.hourly.time = [
    "2026-08-21T08:00",
    "2026-08-21T09:00",
    "2026-08-21T10:00",
  ];
  for (const altitude of WIND_LEVELS_METRES_MSL) {
    source.hourly[`wind_speed_${altitude}m`] = [36, 36, 36];
    source.hourly[`wind_direction_${altitude}m`] = [270, 180, 90];
  }
  const field = parseOpenMeteoForecast(source, new Date("2026-08-21T08:00:00Z"));
  const expectedTrack = forecastAltitudeProfileTrack({
    field,
    launch,
    launchElevationMetresMsl: 100,
    controlAltitudesMetresMsl: [100, 100, 100, 100],
    durationMinutes: 10,
    departureOffsetSeconds: 60 * 60,
  });
  const result = planWindRouteToDestination({
    field,
    launch,
    destination: expectedTrack.at(-1),
    launchElevationMetresMsl: 100,
    minimumDurationMinutes: 10,
    maximumDurationMinutes: 10,
    altitudeCeilingMetresMsl: 100,
    minimumDepartureOffsetMinutes: 0,
    maximumDepartureOffsetMinutes: 120,
    departureSearchStepMinutes: 60,
  });
  assert.equal(result.reachesDestination, true);
  assert.equal(result.departureOffsetMinutes, 60);
  assert.equal(result.departureAt.toISOString(), "2026-08-21T09:00:00.000Z");
  assert.ok(result.missDistanceMetres < 1);
  assert.ok(result.departureWindow);
  assert.ok(result.departureWindow.startAt <= result.departureAt);
  assert.ok(result.departureWindow.endAt >= result.departureAt);
});

test("generated GPX names the forecast and intended landing without claiming a route", () => {
  const track = [
    { latitude: 51.5, longitude: -2.5, altitudeMetresMsl: 100, elapsedSeconds: 0 },
    { latitude: 51.51, longitude: -2.48, altitudeMetresMsl: 100, elapsedSeconds: 60 },
  ];
  const gpx = buildFlightPlanGpx({
    name: "Bristol < dawn",
    track,
    departureAt: new Date("2026-08-21T08:00:00Z"),
    launch: track[0],
    forecastLanding: track[1],
    intendedLanding: { latitude: 51.512, longitude: -2.479 },
  });
  assert.match(gpx, /Bristol &lt; dawn/);
  assert.match(gpx, /Forecast-only wind drift\. Not a controllable route/);
  assert.match(gpx, /Pilot intended landing area/);
  assert.match(gpx, /<type>balloon-flight-forecast<\/type>/);
  assert.doesNotMatch(gpx, /Bristol < dawn/);
});

test("landing-area polygon is closed and bounded", () => {
  const polygon = circlePolygon({ latitude: 51.5, longitude: -2.5 }, 500, 12);
  assert.equal(polygon.length, 13);
  assert.deepEqual(polygon[0], polygon.at(-1));
  assert.ok(polygon.every(([longitude, latitude]) => longitude < -2.49 && longitude > -2.51 && latitude < 51.51 && latitude > 51.49));
});

test("operational boundaries validate several lines, areas and altitude limits", async () => {
  const { normaliseOperationalBoundary, operationalBoundariesGeoJson } = await import(
    "./planner-core.mjs"
  );
  const line = normaliseOperationalBoundary({
    id: "restricted-edge",
    label: "Restricted edge",
    kind: "line",
    source: "Pilot briefing",
    points: [
      { latitude: 51.4, longitude: -2.7 },
      { latitude: 51.5, longitude: -2.6 },
    ],
  });
  const area = normaliseOperationalBoundary({
    id: "avoid-area",
    label: "Avoid area",
    kind: "area",
    source: "Local briefing",
    points: [
      { latitude: 51.4, longitude: -2.7 },
      { latitude: 51.5, longitude: -2.6 },
      { latitude: 51.4, longitude: -2.5 },
    ],
  });
  const altitude = normaliseOperationalBoundary({
    id: "height-band",
    label: "Height band",
    kind: "altitudeBand",
    source: "Flight plan",
    points: [],
    lowerAltitudeMeters: 200,
    upperAltitudeMeters: 900,
    altitudeDatum: "wgs84Geoid",
  });
  const geoJson = operationalBoundariesGeoJson([line, area, altitude]);

  assert.equal(geoJson.features.length, 2);
  assert.equal(geoJson.features[0].geometry.type, "LineString");
  assert.equal(geoJson.features[1].geometry.type, "Polygon");
  assert.deepEqual(
    geoJson.features[1].geometry.coordinates[0][0],
    geoJson.features[1].geometry.coordinates[0].at(-1),
  );
  assert.throws(
    () => normaliseOperationalBoundary({ ...altitude, lowerAltitudeMeters: 1000 }),
    /below maximum/,
  );
});
