# Balloon Crumbs — Product Requirements and Delivery Plan

Status: concept scaffold

Working title: **Balloon Crumbs**

Platforms: iOS and Android
Initial users: UK hot-air-balloon pilots, ground crew, and chase drivers

## Problem statement

Balloon chase teams need a shared, rapidly changing picture of an aircraft that
does not follow roads and may cross areas with weak data coverage. The pilot
needs to publish a trustworthy, low-effort flight state; chase drivers need safe
road guidance and voice instructions; and the wider crew needs an honest view of
where every participant was last observed without creating accounts before a
flight.

## Product principles

1. **Eyes up, hands off.** Pilot and driver interactions are glanceable,
   voice-first, and designed for use before moving or while safely stopped.
2. **Offline is ordinary.** Every important event is committed locally before it
   is relayed over nearby or internet transport.
3. **No false certainty.** Position, altitude, weather, and routing display a
   source, fix time, freshness, and uncertainty where available.
4. **No account required.** A six-digit code or QR creates temporary,
   operation-scoped membership for all participants.
5. **The road and the balloon are different systems.** Chase guidance chooses a
   legal road-accessible rendezvous; it never asks a vehicle to follow the raw
   airborne coordinate.
6. **Privacy lands with the flight.** Precise tracks expire after a short recovery
   window unless a participant deliberately exports or retains their own copy.

## Goals

- A pilot can create a flight and two chase vehicles can join in under two
  minutes without an email address or password.
- Participating phones converge on balloon and chase state after temporary data
  loss without duplicate events or manual repair.
- A chase driver can start voice guidance to a safe, road-accessible intercept
  and receive a clear recalculation when the projected target moves.
- A crew member can understand the last 30 minutes of balloon movement from an
  altitude-coloured ground track and see fix age, speed, heading, and trend.
- In field tests, at least 95% of valid balloon fixes reach an internet-connected
  chaser within 10 seconds and stale data is never labelled live.

## Non-goals for the first field-test release

- Certified aviation navigation, air-traffic separation, or regulatory
  compliance tooling.
- Automated launch, landing, burner, or flight-control decisions.
- Navigation to private land or an assurance that a predicted landing point is
  accessible, permitted, or safe.
- Automatic emergency-service contact.
- Public flight discovery, permanent profiles, social feeds, or historical
  public tracking.
- A promise of continuous operation after a user force-quits the app.

## Personas and user stories

### Pilot / balloon device

- As a pilot, I want to start a private flight and share a short code so the
  chase team can connect quickly.
- As a pilot, I want my location, GNSS altitude, heading, speed, and vertical
  trend published with freshness and accuracy so crew can judge the data.
- As a pilot, I want a minimal view of chase vehicles and messages so I can keep
  attention on flying.

### Chase driver

- As a chase driver, I want voice guidance to a safe moving rendezvous so I do
  not need to operate the phone while driving.
- As a chase driver, I want the app to distinguish the balloon location from my
  road destination so I understand why the route may end elsewhere.
- As a chaser, I want to see other chase vehicles so the team can split routes
  and avoid unnecessary duplication.

### Ground crew / coordinator

- As ground crew, I want an altitude-coloured ground track and telemetry cards
  so I can understand the balloon's recent movement.
- As a coordinator, I want to switch between balloon and chase viewpoints and
  see all participants on a mini-map.
- As a participant, I want delayed or relayed state labelled honestly so I do
  not mistake an old fix for the current position.

## Requirements

### P0 — private field-test release

#### Flight lifecycle and anonymous membership

- Create, join, resume, leave, and end a flight with a six-digit code or QR.
- Roles: pilot, balloon crew, chase driver, chase crew, and observer.
- One balloon identity with one or more active chasers; duplicate display names
  do not merge devices.
- The pilot explicitly starts and ends location sharing.

Acceptance:

- [ ] Five phones can join the same pre-flight session in under two minutes.
- [ ] A restarted phone resumes the same role without creating a ghost member.
- [ ] Ending a flight stops publication and begins the retention timer.
- [ ] Code enumeration is rate-limited and membership secrets are not logged.

#### Balloon telemetry and altitude trail

- Publish latitude/longitude, timestamp, horizontal accuracy, altitude and its
  source/accuracy when available, ground speed, heading, and vertical trend.
- Render the balloon's ground track with a documented, accessible altitude
  colour scale; provide a non-colour cue and selectable units.
- Reject impossible jumps and label degraded/missing altitude without silently
  interpolating it as measured data.

Acceptance:

- [ ] Each displayed fix exposes age and quality on demand.
- [ ] Colour thresholds and the legend update consistently between metric and
  imperial units.
- [ ] Missing altitude does not break the trail and is visually distinct.
- [ ] Simulator tests cover ascent, level flight, descent, GPS loss, and replay.

#### Multiple chase vehicles and role-specific views

- Show balloon, current device, and every permitted chase vehicle with distinct
  symbols, labels, direction, and freshness.
- Provide balloon-focused, current-chaser, all-team, and split/mini-map framing.
- The pilot view suppresses driver-only controls; the chase view suppresses
  pilot-only actions.

Acceptance:

- [ ] Three chasers moving independently remain identifiable at all zoom levels.
- [ ] A user can switch viewpoints without changing their role or shared state.
- [ ] Stale members remain visible but cannot appear live.

#### Safe dynamic chase guidance

- Generate road routes to safe road-accessible intercept/rendezvous candidates,
  using recent balloon motion and a bounded prediction horizon.
- Recalculate only after configurable movement/time thresholds to avoid constant
  instruction churn; explain the active target and its age.
- Speak manoeuvres, recalculation, loss-of-fix, and arrival/stop guidance.
- Never route across private tracks, fields, restricted roads, or directly to an
  airborne coordinate without a road-access validation step.

Acceptance:

- [ ] The UI separately marks balloon position, predicted area, and road target.
- [ ] Losing balloon fixes freezes the last route, announces staleness, and does
  not invent a new target.
- [ ] A driver can mute guidance and safely stop guidance in one action.
- [ ] Route decisions and provider responses are reproducible in simulation.

#### Offline, security, privacy, and diagnostics

- Retain Tail End Charlie's local journal, deduplication, bounded relay, QR
  bootstrap, diagnostics, and explicit stale states.
- Replace the inherited group-HMAC trust model with per-device authority and
  encrypted payloads before public release.
- Default precise server-side data retention to the active flight plus a short,
  documented recovery period.

Acceptance:

- [ ] Replayed and duplicated events produce one canonical state.
- [ ] Connectivity loss and recovery require no repair screen.
- [ ] Logs redact codes, secrets, exact tracks, and provider credentials.
- [ ] A participant can leave and delete their local flight data.

### P1 — useful after the core loop works

- Weather and wind layers with timestamps, forecast age, source attribution,
  selectable altitude/time, and an explicit observed-versus-forecast distinction.
- Airspace/NOTAM context from a provider whose licence and update cadence permit
  the intended display; informational only.
- Landing-area annotations, crew notes, gates/access points, and landowner/contact
  workflow without asserting permission or safety.
- CarPlay and Android Auto chase companion, subject to platform eligibility,
  distraction rules, entitlement/review, and physical-car testing.
- Revocable browser observer link with reduced precision and bounded lifetime.
- Flight recap and GPX/KML export with opt-in retention.

### P2 — future considerations

- External balloon tracker and flight-instrument integrations.
- Fleet/club operations with several balloons in one event.
- Collaborative landing prediction using forecast wind profiles.
- Optional satellite messenger bridge where an official integration exists.

## Success metrics

Leading indicators:

- 80% of invited field-test devices join successfully on their first attempt.
- Median create-to-ready time below two minutes for a pilot plus two chasers.
- 95% of usable internet-relayed position events displayed within 10 seconds.
- Fewer than one unnecessary chase-route recalculation per five minutes in a
  representative simulated flight.
- Zero stale fixes presented with the live visual state in automated replay tests.

Lagging indicators:

- 70% of test flights that start sharing reach a deliberate end-flight action.
- Fewer than 5% of field-test flights require a manual session reset.
- At least 80% of chase testers rate route-target clarity 4/5 or better.

## Open questions

- **Blocking — product/safety:** Which person/device is authoritative for balloon
  telemetry when several phones are in the basket?
- **Blocking — engineering/licensing:** Which road-routing, map, weather, wind,
  airspace, and NOTAM providers permit caching and redistribution in this app?
- **Blocking — product:** What prediction horizon and recalculation cadence are
  acceptable to experienced UK chase crews?
- **Blocking — privacy:** Exact retention durations and observer precision.
- **Non-blocking — design:** Final altitude palette and simultaneous non-colour cue.
- **Non-blocking — release:** Final product name, domains, and permanent bundle IDs.

## Delivery phases

1. **Foundation:** isolate the derivative, settle domain model, remove motorcycle
   UI/data, and keep inherited CI green.
2. **Core field-test slice:** anonymous flight session, telemetry, altitude trail,
   multi-chaser map, safe moving road target, voice guidance, and simulator.
3. **Context:** weather/wind, airspace/NOTAM decision, landing notes, observer,
   and exports.
4. **Release evidence:** security protocol, privacy review, licences, battery and
   background tests, mixed-device field matrix, accessibility, and store review.
