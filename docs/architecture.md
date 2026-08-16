# Target Architecture

## Starting point

The copied baseline is Flutter with thin Swift/Kotlin platform bridges plus a
FastAPI/PostgreSQL relay. State-changing actions are appended to an idempotent
SQLite event journal before relay. Nearby and HTTPS are transport adapters, not
the source of truth.

```text
Pilot/chaser UI -> Flight controller -> local event journal
                                          |-> nearby relay
                                          |-> bounded HTTPS relay

Telemetry -> quality/filtering -> flight events -> read models
Road router <- intercept selector <- recent balloon motion
Map renderer <- balloon/chaser read models + altitude trail + route target
Voice guidance <- road route, staleness, and recalculation events
```

## Domain migration

The inherited implementation calls a session a `ride` and uses Dart/Python
packages named `ride_relay`. Keep those internal names until the core domain
boundaries are covered by tests; a broad rename is not a product feature.

Target concepts:

| Target concept | Inherited basis | Required change |
|---|---|---|
| Flight operation | Ride session/lifecycle | Balloon roles and pilot authority |
| Balloon telemetry | Rider location events | Altitude source/accuracy and vertical trend |
| Chase vehicles | Rider roster/trails | Vehicle identity and multi-chaser views |
| Altitude ground track | Ridden trail renderer | Per-segment altitude styling and legend |
| Chase target | Route/rejoin planner | Safe road-accessible moving intercept selector |
| Voice guidance | Spoken guidance | Moving-target/staleness announcements |
| Weather/airspace | Discovery/hazard providers | New licensed, timestamped provider contracts |
| Flight recap | Ride recap/GPX | Balloon metrics and opt-in precise-track export |

## State and event model

The canonical session is one flight operation with one authoritative balloon
stream and many participant devices. Suggested new event types include
`flightStarted`, `telemetryObserved`, `chaseTargetSelected`, `crewMessage`,
`landingAreaNoted`, and `flightEnded`. Events include schema version, operation
and device IDs, timestamps, expiry, typed payload, and authentication.

Telemetry read models must preserve measurement time separately from receipt
time. Altitude carries a datum/source and optional accuracy; no conversion may
erase those fields. A segment can be coloured only when both endpoint samples
have valid altitude under the documented policy.

## Dynamic chase routing

Routing has three explicit layers:

1. Estimate a bounded future balloon area from recent valid motion and optional
   forecast context. This is a prediction with age and uncertainty.
2. Select candidate points on the legal road network near that area, filtering
   restricted/private access where provider data permits.
3. Ask the road router for a vehicle route and choose a stable rendezvous using
   travel time, target age, access confidence, and hysteresis.

If any layer is unavailable, the app shows the balloon and last route separately
and states why guidance is stale. It does not turn a raw balloon coordinate into
a driving instruction.

## Views

- **Pilot:** minimal status, chase positions/messages, end sharing, emergency
  privacy control.
- **Chase driver:** heading-up road guidance with voice and a small balloon/team
  context map.
- **Chase crew/coordinator:** full altitude trail, telemetry, target rationale,
  weather, and participant viewpoint switching.
- **Observer:** time-bounded read-only last-known state with reduced capabilities.

## Provider boundaries

Maps, road routing, geocoding, weather/wind, airspace/NOTAM, and notification
delivery sit behind provider interfaces. Each implementation records attribution,
licence/caching policy, request timestamp, response validity, and failure mode.
No production provider or real domain is configured in this scaffold.

## Safety and verification gates

- Simulator/replay tests for motion, altitude, clock skew, stale fixes, route
  hysteresis, duplicated events, and reconnect.
- Physical iOS/Android tests for GPS/altitude behaviour, background delivery,
  nearby transport, battery, thermal behaviour, audio interruption, and driving.
- Accessibility test of altitude representation without colour dependence.
- Security/privacy threat model and per-device authority before public release.
- Provider and data-licence review before checking in or caching any dataset.
