import assert from "node:assert/strict";
import test from "node:test";

import {
  WIND_LEVELS_METRES_MSL,
  altitudeForFlightFraction,
  altitudeForProfileFraction,
  altitudeForStrategyFraction,
  buildFlightPlanGpx,
  circlePolygon,
  forecastAltitudeProfileTrack,
  forecastLandingEnvelope,
  forecastFlightTrack,
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

test("wind request mirrors the app's bounded UKMO grid and height levels", () => {
  const centre = { latitude: 51.5, longitude: -2.5 };
  assert.equal(windForecastGrid(centre).length, 9);
  const url = openMeteoRequestUrl({ endpoint: "/weather/v1/forecast", center: centre });
  assert.equal(url.pathname, "/weather/v1/forecast");
  assert.equal(url.searchParams.get("models"), "ukmo_seamless");
  assert.equal(url.searchParams.get("forecast_days"), "3");
  assert.equal(url.searchParams.get("latitude").split(",").length, 9);
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
