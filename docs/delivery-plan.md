# Delivery Plan

Engineering plan for turning the inherited Tail End Charlie baseline into
Balloon Crumbs. [PLAN.md](../PLAN.md) states the product requirements; this
document states the order of work against the code that actually exists.

## Survey findings

Measured on the scaffold commit, `apps/mobile/lib` (80,180 lines of Dart) and
`apps/mobile/test` (62,856 lines):

| Signal | Count | Reading |
|---|---:|---|
| `altitude` / `elevation` (telemetry sense) | **0** | The headline feature has no foundation |
| `pilot` | **0** | No balloon role exists |
| `burner` | **0** | No balloon domain exists |
| `rider` | 3,889 across 169 files | The domain language is motorcycling |
| `marker` | 1,231 across 61 files | Drop-off marker system, motorcycle-only |
| `hazard` | 704 across 37 files | Road hazard/traffic, partly reusable |
| `enforcement` | 183 across 15 files | Speed-camera alerts, motorcycle-only |
| `tailEndCharlie` | 106 across 40 files | Sweep-rider role, deleted in WP1 |

The load-bearing conclusion: `LocationSample` in
[rider_location.dart](../apps/mobile/lib/domain/rider_location.dart) carries
position, time, accuracy, speed and heading — **but no altitude, no altitude
source, and no vertical trend**. `RiderLocation` carries a `MotorcycleIconStyle`.
Every balloon feature in PLAN.md depends on changing this type, and 169 files
touch its surrounding vocabulary.

This is therefore a **domain-layer rewrite with selective infrastructure reuse**,
not a rename-and-adapt exercise. Planning it as the latter is what would put a
motorcycle safety model underneath an aviation-adjacent product.

## Reuse boundary

**Keep — domain-neutral infrastructure, genuinely valuable:**

- SQLite event journal, idempotency, deduplication, replay
- Six-digit session codes, QR bootstrap, anonymous membership lifecycle
- Nearby transport bridge (iOS/Android) and the bounded HTTPS relay + server
- Location capture plumbing, background delivery, permission flows
- Map rendering, tiles, style repository, offline fallback
- GPX import/export, diagnostics recorder, simulation harness, CI

**Replace — same shape, wrong domain:**

- `LocationSample` → balloon-capable telemetry sample (WP2)
- `RideRole` → `FlightRole` (WP3)
- Trail renderer → altitude-coloured ground track (WP4)
- Route/rejoin planner → moving rendezvous selector (WP6)

**Delete — motorcycle concepts with no balloon meaning:**

- Tail End Charlie sweep role (WP1, agreed)
- Drop-off marker system — a second bike holding a junction (needs decision)
- Speed-camera / enforcement alerts (needs decision)
- Overtake, junction-passing, and bike-specific iconography (needs decision)

Deleting rather than adapting is deliberate: a balloon does not have a back
marker, and carrying the concept forward would keep its assumptions alive in the
roster, relay, CarPlay bridge, and server capability negotiation.

## Work packages

Ordered. Each lands with tests green and `flutter analyze` clean.

### WP1 — Delete the Tail End Charlie role *(backlog #1, done)*

`RideRole.tailEndCharlie` and everything reachable from it is gone: the role
assignment service, gap-trend service, CarPlay TEC status, the leader
request/accept/decline event types, the roster request flow, the "No Hot
Pursuit" start warning, the leader's gap card, the CarPlay and Android Auto
surfaces, and the `tec-role-assignment-v1` relay capability on both client and
server.

Acceptance:
- [x] No `tailEndCharlie`, `tec`, or `Hot Pursuit` identifier remains in `lib/`
- [x] Full Flutter suite (1810) and server suite (145) green; analyzer clean
- [x] Server compatibility tests updated for the removed capability
- [x] No dead branches left behind in the roster or CarPlay bridges

#### Decisions taken during the cut

**Rejoin routing falls back to the ride leader.** `route_rejoin_planner.dart`
sent a massively off-course rider to the back-marker when its fix was
trustworthy. The file's own documentation already named the leader as the
fallback for every other case, so with no back-marker the leader is now the only
target. `RouteRejoinTarget.tailEndCharlie` is gone.

**The marker system lost its "back of the group is through" signal.**
`marker_statistics.dart` set `tecPassedAt` when a rider whose role was
`tailEndCharlie` passed the marker; that is how a marker knew it could ride off.
With the role gone the field could never be set again, so leaving it in place
would have meant a marker silently waiting forever for a signal that no longer
exists. `tecPassedAt`, `tecPassageCount` and `tecPassedCurrentMarker` were
removed, and the marker surfaces now report verified passes only. **This is a
behaviour change to the drop-off marker system**, and it strengthens the case
for deleting that system outright — see Decisions needed.

**The simulator's back rider is now identified by id, not by role.** Ride Lab
modelled the marker interaction as "wait for the TEC". The concept it actually
needs is "the last rider in the group", so `tecRiderId` became `backRiderId` and
the marker phases were renamed to match. The TEC viewpoint was dropped from the
Ride Lab perspective picker.

**An unknown role name degrades instead of throwing.** `RideRole.values.byName`
throws on a name this build does not know. The journal reducers already guarded
it, but `RiderLocation.fromJson`, `RideSession.fromJson`,
`CompletedRide.fromJson` and the marker-assistance controller did not — so a
peer on an older build, or an install that predates this change, would have
failed to parse rather than degrade. Those four now use `rideRoleFromName`,
covered by `test/domain/ride_role_compatibility_test.dart`.

#### Deliberately left in place

- **`tec:` in `gpx_exporter.dart`** is the GPX XML namespace prefix for this
  app's route extensions. It is a file format that already-exported GPX files
  carry, not the role, and renaming it would orphan them.
- **Dead TEC rendering in `CarPlaySceneDelegate.swift`** (`CarPlayTecBadge`, the
  `isTec` rider flag). Dart no longer publishes `tec`, `tecRequest` or `isTec`,
  so these read as absent/false and draw nothing. Removing them means editing
  CarPlay layout code that cannot be exercised by the Dart test suite, so it is
  left for a pass that can be verified in a car or the CarPlay simulator.

### WP2 — Balloon-capable telemetry *(prerequisite for the product; in progress)*

Extend the position sample with `altitudeMeters`, `altitudeSource`
(`gnss` / `barometric` / `unknown`), `altitudeAccuracyMeters`, and
`verticalSpeedMetersPerSecond`. Capture real altitude on both platforms. Reject
impossible jumps. Never interpolate missing altitude into measured data.

Wire compatibility: additive optional fields with a schema version bump, so an
older peer degrades to no-altitude rather than failing to parse.

Acceptance:
- [x] JSON round-trip preserves source and accuracy; no conversion erases them
- [x] Measurement time stays distinct from receipt time
- [x] Missing altitude is representable, never silently zero
- [ ] Missing altitude is *visually* distinct (needs the WP4 renderer)
- [ ] Simulator emits ascent, level flight, descent, and GNSS loss

#### Landed so far

`LocationSample` now carries `altitudeMeters`, `altitudeSource`
(`gnss` / `barometric` / `unknown`), `altitudeAccuracyMeters` and
`verticalSpeedMetersPerSecond`, with the constructor refusing a source or an
accuracy that has no reading behind it. The wire form is additive and writes no
altitude keys at all when there is no reading, so an absent altitude never
reaches a peer as an explicit null that later reads as a measurement. An
unrecognised `altitudeSource` degrades to `unknown` rather than throwing, on the
same reasoning as `rideRoleFromName`.

**The trap this had to avoid:** both platforms report `altitude == 0.0` when
they have none, and a balloon in the launch field genuinely reports `0.0`. The
reading cannot separate the two. `DeviceLocationSource` therefore gates on the
*vertical accuracy* — CoreLocation documents a non-positive `verticalAccuracy`
as "altitude invalid", and Android only reports one when it has it — so a fix
without a positive vertical accuracy carries no altitude rather than a
measurement of ground level. Covered by
`test/domain/location_sample_altitude_test.dart`.

#### Still to do in WP2

- Feed altitude into the recorded track so flight GPX gets `<ele>`. The
  travelled track is stored as an `ImportedRoute`, whose points already have
  `elevationMeters` and whose exporter already writes `<ele>` — the gap is the
  conversion from `LocationSample` into that type. This is the second half of
  issue #16.
- Altitude source and accuracy in the GPX extension namespace (stock GPX 1.1
  has nowhere to put either).
- Reject impossible vertical jumps.
- Simulator ascent/descent/GNSS-loss profiles.

### WP3 — Flight roles and pilot authority *(backlog #2)*

Replace `RideRole` with `FlightRole { pilot, balloonCrew, chaseDriver, chaseCrew,
observer }`. Establish one authoritative balloon telemetry stream and resolve the
blocking question of which device speaks for the balloon when several phones are
in the basket. Role-specific view gating.

### WP4 — Altitude-coloured ground track *(backlog #3 — the "crumbs")*

Per-segment altitude styling with a documented palette, a non-colour cue, a
legend that tracks metric/imperial, and a colouring policy that requires valid
altitude at both segment endpoints.

### WP5 — Multiple chase vehicles and viewpoints *(backlog #4)*

### WP6 — Safe moving rendezvous and road routing *(backlog #5)*

### WP7 — Voice guidance for a moving target *(backlog #6)*

### WP8 — Simulator and replay matrix *(backlog #7)*

## Decisions needed

1. **Marker system, enforcement alerts, speed limits** — delete or keep? They are
   1,400+ lines of motorcycle-specific behaviour with no balloon equivalent.
   Recommendation: delete in a WP1 follow-up, before WP2 changes the telemetry
   type underneath them.
2. **Bundle identifiers and internal package names — done.** The bundle ID is
   `dev.osholt.ballooncrumbs`, the Dart package `balloon_crumbs`, the Python
   package `balloon_crumbs_server`, and the relay env prefix
   `BALLOON_CRUMBS_`. iOS signing moved to automatic, because a new bundle ID
   has no manual profile and Apple will not issue one automatically for the
   CarPlay entitlements the project used to declare.
3. **CarPlay entitlements are removed** so the app can be signed and installed
   without an Apple-approved CarPlay profile. The CarPlay code is untouched and
   inert. Restoring it means re-adding
   `com.apple.developer.carplay-driving-task` and
   `com.apple.developer.carplay-maps` to both entitlements files and creating a
   matching profile in the developer console — which is backlog item 12's
   problem, not something a local build can solve.

## Risks

- **Scale.** 80k lines of Dart written for a different sport. Every work package
  must land green, or the baseline stops being a usable reference.
- **Safety framing.** The inherited copy speaks to riders about road hazards. Any
  string surfacing to a pilot or driver must be re-reviewed, not translated.
- **Provider licensing.** Weather, wind, airspace, and NOTAM data remain blocked
  on the licence review in PLAN.md; no dataset should be cached before it.
