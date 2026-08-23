# Role-specific live flight experience

Status: **Implemented technical foundation — product priority superseded**

Date: 23 August 2026

Scope: iOS and Android live-flight experience, its shared domain state, and the
contract used to bring web-planner forecasts into a running flight.

The launch-to-recovery field observation documented in
[field operations and recovery coordination](field-operations-recovery-plan.md)
supersedes this document where priorities conflict. Roles, crafts, shared tracks
and route-state separation remain required architecture. Planning and pilot
interaction are no longer the core workflow; crew assembly, recovery mapping,
CarPlay, crew-led release and landing confirmation are.

## Executive summary

Balloon Crumbs currently has pieces of a balloon product, but the production
journey still runs through Tail End Charlie's two-role `lead` / `rider` session.
The proper `FlightRole` and `Craft` models exist, yet no production create or
join flow registers a balloon, registers a chase vehicle, attaches a device to
a craft, or persists its flight role. As a result, real users do not reliably
reach different balloon and chase experiences, and legacy terminology remains
visible.

The implementation must begin with the domain and assignment flow, not another
layer of screen conditionals. Once every device has a real flight role and a
craft, the app will provide four deliberately different live experiences:

1. **Pilot:** an austere flight deck with actual telemetry, current forecast
   wind, airspace context, the altitude-coloured track, the planned altitude
   profile, landing intent and flight authority.
2. **Balloon crew:** the same airborne information with more room for inspection
   and communication, but without pilot-authority actions.
3. **Chase driver:** voice-first road navigation, road safety information and a
   glanceable flight context, without airborne planning controls.
4. **Chase crew:** a tactical ground view containing the balloon, every chase
   vehicle, all shared tracks, landing intent, possible landing areas, and the
   controls for the vehicle's chosen chase target.

The web planner remains the pre-flight planning surface. Its output must become
a structured flight plan rather than only a GPX line so the mobile app can show
the start window, altitude stages, wind provenance, landing envelope,
operational boundaries and planning constraints. During a live flight the app
will preserve that original plan, show actual progress separately, and—when a
fresh Open-Meteo forecast is available—calculate a clearly labelled live
projection from the balloon's current position and altitude.

## Problem statement

The current app does not give a user confidence that it knows whether they are
flying the balloon, assisting in the basket, driving a chase vehicle, or working
as chase crew. It still exposes inherited `leader`, `rider`, `ride` and road
concepts because the live surfaces are driven by the legacy session role rather
than the new flight-role and craft models.

This is more than a wording problem. Forecast geometry and a vehicle's road
route are both held in the same active-route slot, and the useful data produced
by the web planner is reduced to a GPX track during sharing. Without separating
those concepts, the pilot can be offered road behaviours and the chaser can lose
their personal navigation when the shared balloon plan changes.

## Evidence in the current repository

- `FlightRole` already defines pilot, balloon crew, chase driver, chase crew and
  observer, including authority and road-furniture rules.
- `Craft` and the craft-roster reducer already model one balloon and several
  vehicles, including several devices attached to one craft and deterministic
  craft telemetry election.
- Production features do not currently create those craft/role events. The
  production `resolveCraftRoster()` is therefore normally empty.
- The live shell decides balloon versus chase presentation from `localCraft`,
  but falls back to the inherited `RideRole.lead` in simulation and many
  authority, roster and copy paths still consume `RideRole` directly.
- The server plan directory stores only an encrypted GPX string. GPX preserves
  geometry, time and elevation, but loses the web planner's departure window,
  altitude ceiling, ascent/descent limits, altitude control stages, landing
  envelope, wind model metadata and operational boundaries.
- One `_activeRoute` currently represents both a shared forecast plan and a
  device-local chase road route. These have different owners, lifetimes,
  consumers and safety rules and must not share a state slot.
- Open-Meteo wind, OpenAIP chart context, altitude telemetry, landing intent,
  dynamic chase target selection and craft-track reducers already exist in
  partial form. The plan should compose and complete them rather than replace
  them.

## Goals

1. Every live device has an explicit `FlightRole` and is attached to exactly one
   craft before entering the live-flight shell.
2. No user-facing production string uses `ride`, `rider`, `leader`, `bike` or
   `motorcycle` for the balloon workflow.
3. Airborne roles never see speed limits, road hazards, turn-by-turn directions
   or road-route progress.
4. Chase roles never mistake forecast balloon geometry for their road route.
5. The pilot and balloon crew can compare the original forecast, actual flight,
   current forecast wind and a live possible-landing projection without any of
   those being presented as measured certainty or aircraft control.
6. Each chase vehicle can independently choose either the pilot's current
   intended landing area or a road rendezvous near the latest fresh balloon fix,
   and receive lawful road guidance that dynamically recalculates.
7. Balloon and vehicle locations and actual tracks converge across all flight
   devices after temporary connectivity loss, with source, age and freshness
   visible.
8. Planner and app calculations remain behaviourally compatible through shared
   versioned fixtures and contract tests.

## Non-goals

- The app will not claim to provide certified aviation navigation, clearance,
  terrain clearance, NOTAM completeness or an official aviation briefing.
- The altitude profile will not be phrased as a command to climb or descend.
  It is a forecast strategy that a qualified pilot may compare with conditions.
- A chase route will never terminate at a raw airborne coordinate or direct a
  vehicle off-road. “Near balloon” means a validated road-network rendezvous.
- Open-Meteo will not be described as measured “live wind”. It is numerical
  forecast data valid for the displayed time and altitude.
- The first implementation will not optimise several chase vehicles into a
  fleet strategy or support several balloons in one flight.
- Observer and public tracking experiences are not part of this delivery, but
  the role and event model must continue to degrade observers safely.
- Official UK flight-plan generation or filing is not included.

## Canonical terminology

| Concept | Meaning | User-facing term |
|---|---|---|
| Flight | One private balloon operation from pre-launch to end | Flight |
| Person | A human participant | Person or crew member |
| Device | One phone participating in the flight | Device |
| Craft | One balloon or one chase vehicle | Balloon / vehicle label |
| Pilot | The person with flight authority | Pilot |
| Balloon crew | A non-pilot person in the balloon | Balloon crew |
| Chase driver | The person currently driving a chase vehicle | Driver |
| Chase crew | A non-driving person in a chase vehicle | Chase crew |
| Flight plan | Original advisory web-planner output | Forecast plan |
| Actual track | Where a craft was measured to have travelled | Track |
| Live projection | Recalculation from current telemetry and forecast wind | Live projection |
| Intended landing area | The pilot's current stated intent | Intended landing area |
| Road rendezvous | A router-validated road endpoint serving a target | Road rendezvous |

`RideRole`, `RideSession`, `riderId` and related API fields may remain as
temporary internal compatibility identifiers while old builds are supported.
They must not leak into visible labels, accessibility text, notifications,
diagnostics intended for testers, release notes or exported flight summaries.

## Personas and role permissions

### Permission matrix

| Capability | Pilot | Balloon crew | Chase driver | Chase crew |
|---|:---:|:---:|:---:|:---:|
| Start/end flight | Yes | No | No | No |
| Transfer pilot role | Yes | Accept only | No | No |
| Set/replace intended landing area | Yes | No | No | No |
| Declare commitment to landing | Yes | No | No | No |
| Register the balloon | Yes | No | No | No |
| Nominate balloon telemetry device | Yes | No | No | No |
| Inspect altitude profile/wind/airspace | Yes | Yes | Glanceable context only | Yes |
| Change wind display altitude locally | Yes | Yes | No | Yes |
| Create/select a chase vehicle | No | No | Yes | Yes |
| Select that vehicle's chase target | No | No | Yes when stopped | Yes |
| Edit that vehicle's road preferences | No | No | Yes when stopped | Yes |
| Receive turn guidance and road alerts | No | No | Yes | Optional overview, no alerts by default |
| Add ground/access notes | No | No | Voice/quick action | Yes |
| Send/receive flight messages | Yes | Yes | Voice/quick action | Yes |

The pilot is the sole flight authority in the first release. Balloon crew may
operate local inspection controls and may be elected as the balloon's telemetry
source, but cannot silently change flight intent. A later delegated-authority
capability can be additive if field testing proves it is needed.

### User stories

#### Pilot

- As the pilot, I want the app to enter a flight-specific cockpit view so road
  speed and turn information cannot distract me.
- As the pilot, I want my altitude, vertical trend, telemetry age and quality at
  a glance so I know what the team is actually receiving.
- As the pilot, I want to see forecast wind at my current altitude and inspect
  other levels so I can compare the plan with current forecast conditions.
- As the pilot, I want the planned altitude stages and their times visible so I
  can understand what produced the forecast track.
- As the pilot, I want to replace or clear the intended landing area during the
  flight so every chase vehicle receives my latest intent.
- As the pilot, I want actual, planned and live-projected tracks to look
  different so I cannot confuse forecast geometry with measured travel.

#### Balloon crew

- As balloon crew, I want the same airborne map, altitude profile, wind and
  airspace context as the pilot, with room to inspect details and communicate.
- As balloon crew, I want my phone to contribute telemetry without creating a
  second balloon or a second track.
- As balloon crew, I want authority-only actions visibly identified as pilot
  actions rather than disabled without explanation.

#### Chase driver

- As a driver, I want voice-first lawful road guidance while keeping the
  balloon, intended area and other vehicles visible in a small context map.
- As a driver, I want to choose whether my vehicle is pursuing the intended
  landing area or a road rendezvous near the balloon while safely stopped.
- As a driver, I want speed limits and road alerts but no altitude-planning
  controls or editable tactical panels while moving.
- As a driver, I want a clear spoken warning when the pilot changes the intended
  area, the balloon fix becomes stale, or the selected target materially moves.

#### Chase crew

- As chase crew, I want a tactical all-team map showing the balloon, its actual
  and projected tracks, the intended and possible landing areas, every vehicle
  and every actual vehicle track.
- As chase crew, I want to select and review my vehicle's target and route so I
  can support the driver without changing another vehicle's guidance.
- As chase crew, I want to see whether the balloon is closing on or diverging
  from the intended area so I can make a deliberate retargeting decision.

## Role and craft assignment journey

The live-flight shell must not render until assignment is complete.

### Creating a flight

1. The creator is explicitly told: **“You are creating this flight as the
   pilot.”**
2. The app creates the flight and dual-writes the legacy creator role only for
   mixed-version compatibility.
3. It registers one balloon craft with a stable flight-scoped ID and label.
4. It assigns `FlightRole.pilot` to the device and attaches the device to the
   balloon.
5. It nominates this device as the initial preferred telemetry source, without
   preventing the existing quality election from choosing a better usable
   device later.
6. Only after those local journal events commit does the pilot enter the
   pre-launch pilot view and receive the join invitation.

### Joining a flight

After the code or QR is validated, the person answers two short questions:

1. **Where are you?**
   - In the balloon
   - In a chase vehicle
2. **What are you doing?**
   - Balloon: Balloon crew
   - Vehicle: Driving / Chase crew

Vehicle participants then select an existing vehicle or create a named vehicle
such as “Land Rover” or “Van”. Creating a vehicle registers it and attaches the
device atomically from the user's perspective. The first release supports role
changes between driver and chase crew for devices attached to the same vehicle,
but only while the app considers the vehicle stopped.

A second pilot cannot be selected during ordinary join. Pilot handover is an
explicit pilot-authorised flow that writes a role transfer and updates flight
authority after the recipient accepts.

### Resume and recovery

- Device assignment and `FlightRole` are stored with the local session and
  recoverable from the journal.
- A resumed device reattaches to the same craft idempotently.
- If its craft no longer exists, it is stopped at an assignment-repair screen;
  it is never silently treated as a chase vehicle.
- A legacy flight with no craft events receives a one-time migration gate. The
  legacy creator is offered Pilot; every other participant must choose balloon
  crew or a chase vehicle before continuing.
- Mixed-version peers remain visible, but an unassigned old device is labelled
  “Unassigned device” and cannot be elected as the balloon merely because it
  once held `lead`.

## View selection and information architecture

View selection is derived from `FlightRole` plus `CraftKind`. It is not a manual
theme toggle and is not inferred from the legacy leader flag.

```text
No assignment          -> assignment/recovery gate
Pilot + balloon        -> pilot flight deck
Balloon crew + balloon -> airborne crew view
Driver + vehicle       -> chase driver navigation
Chase crew + vehicle   -> chase tactical view
Observer               -> existing restricted observer view
Invalid combination    -> repair gate, never a guessed view
```

A person may change map framing inside their allowed view—for example, balloon,
own vehicle or all team—but that never changes their role or reveals controls
belonging to another role.

### Common shell

Every live view contains:

- current local time at the top;
- flight status: pre-launch, live, paused, landing inferred, landed or ended;
- local role and craft label, for example “Pilot · Balloon” or “Driver · Land
  Rover”;
- connectivity state and last successful relay time;
- emergency and leave controls appropriate to the role;
- a participant/vehicle count that opens a craft-based roster.

The navigation destination is named **Flight**, not Ride. Roster rows are
grouped by craft, then show people/devices aboard. Craft location and freshness
are primary; duplicate device fixes are not drawn as duplicate craft markers.

### Pilot flight deck

Primary surface: a wide, north-up or track-up aeronautical map with restrained
chrome.

Always visible:

- balloon altitude, datum, source, accuracy and fix age;
- vertical speed and trend arrow;
- ground speed and track only as flight telemetry, never in a road speed-limit
  treatment;
- “Crew can see this fix” / “Position has not relayed” state;
- actual altitude-coloured ground track;
- current intended landing area and its age;
- current forecast wind vector at balloon position and altitude, with valid
  time and model source.

One-tap or one-sheet actions:

- update/clear intended landing area;
- declare commitment to landing;
- open forecast altitude profile;
- show/hide wind and choose wind altitude;
- show/hide OpenAIP chart and open its key/limitations;
- inspect chase vehicles and messages;
- end or privacy-stop sharing.

Never present:

- speed limits, enforcement/camera alerts, turn banners, lane guidance, road
  ETA, route progress, “off route”, road target selection or CarPlay actions.

### Balloon crew view

The balloon crew view uses the same map semantics as the pilot view, including
no road controls. It can use a denser bottom sheet because a crew member may be
the person holding the phone.

Additional inspection:

- full planned altitude-stage table;
- actual-versus-plan telemetry history;
- time-by-altitude wind table;
- possible landing areas and the evidence used to calculate them;
- all chase craft, tracks, target choices and ETA summaries;
- message composition and operational-boundary detail.

Pilot-only actions remain visible only where their absence would be confusing,
and explain “Only the pilot can publish a new intended area” rather than using
leader/coordinator language.

### Chase driver navigation

Primary surface: heading-up road navigation with spoken instructions and large,
glanceable controls.

Always visible while guidance is active:

- next manoeuvre, road name, distance and route ETA;
- mapped speed limit and the driver's GPS speed;
- selected target: intended landing area or road rendezvous near balloon;
- target age/freshness and road-endpoint separation;
- a mini-map containing own vehicle, balloon, recent balloon track, intended
  area and other chase vehicles;
- rerouting/stale state in words.

While moving, target changes and route preferences are voice or passenger
actions only. Touch editing reappears when stopped. Wind and airspace layers are
off by default and the altitude profile is not placed in the driving hierarchy.

### Chase crew tactical view

Primary surface: an interactive all-team map plus a collapsible vehicle route
panel.

The map shows:

- latest balloon location, altitude and freshness;
- actual altitude-coloured balloon track;
- original planned forecast track;
- live projected track and possible landing envelope when available;
- pilot intended landing area with revision age;
- every chase vehicle, its fresh/stale state and its actual shared track;
- this vehicle's selected road rendezvous and route;
- other vehicles' selected target category and rendezvous summary, without
  copying their full turn geometry.

The tactical panel provides target selection, route rationale, divergence from
the intended area, vehicle constraints, road ETA, access notes and messages.

## Visual language for tracks and areas

The app and planner use one shared altitude palette:

| Altitude MSL | Colour |
|---:|---|
| 0 m | `#00C8FF` cyan |
| 500 m | `#00F5A0` green |
| 1,000 m | `#FFE600` yellow |
| 2,000 m | `#FF245D` red |

Values interpolate continuously between stops. The legend follows the selected
altitude unit, while the underlying calculation remains metres MSL. Unknown or
incompatible altitude is grey and never treated as zero.

Geometry is distinguished by more than colour:

| Geometry | Style |
|---|---|
| Actual balloon track | Solid altitude gradient, strong casing, direction arrows |
| Original forecast track | Dashed altitude gradient, thinner casing |
| Live projected track | Dotted/faded altitude gradient with forecast timestamp |
| Chase vehicle track | Solid craft identity colour, vehicle direction arrows |
| Intended landing area | Green outline/fill, labelled “Pilot intent” and aged |
| Original landing envelope | Purple dashed boundary, labelled with plan validity |
| Live possible-landing envelope | Amber dotted boundary, labelled with forecast validity |
| Road rendezvous | Blue road pin connected to its target by a faint straight evidence line |

The non-colour differences and accessible descriptions are mandatory. An
altitude-gradient renderer must be shared by actual and forecast paths in both
FlutterMap and MapLibre so one renderer cannot silently fall back to one colour.

## Web-planner capability map

“Bring planner features into the app” means preserving the planning evidence
and making the relevant parts live. It does not mean placing every pre-flight
editing control over an active pilot map.

| Web-planner capability | Mobile pre-launch | Mobile live flight |
|---|---|---|
| Place search | Open planning mode / planner | Not on primary live surfaces |
| Draggable launch/destination | Review/edit before launch | Original points locked; pilot updates intended area separately |
| Departure date/start window | Review and import | Show original window and actual launch time |
| Launch elevation | Import with datum | Compare with actual launch reference |
| Maximum altitude | Import constraint | Show planned ceiling and actual max; never auto-command |
| Max ascent/descent rates | Import constraints | Show beside planned/actual vertical rate |
| Optimised altitude stages | Import structured stages | Highlight current planned stage and actual deviation |
| Forecast track | Import | Preserve as original dashed altitude-coloured line |
| Landing envelope | Import polygon | Preserve original; optionally add live envelope |
| Destination reachability/miss | Import result | Show as pre-flight evidence, not a live promise |
| Wind altitude slider/toggle | Available | Pilot/balloon crew/chase crew; role-specific defaults |
| Wind grid | Import metadata, fetch locally | Re-centre on balloon/viewport and interpolate for displayed time |
| OpenAIP chart/key | Available | Default on for airborne roles, optional for chase crew, off for driver |
| Operational boundaries | Import/share | Draw, age and alert without claiming official restriction data |
| Light/dark map | Same preference | Same preference and renderer parity |
| Plan code | Load structured plan | Plan remains attached to flight and available offline |
| Timed flight profile | Import | Live stage list with original and actual times separated |

## Structured forecast-plan contract

GPX remains an export and backward-compatible fallback. It is not the canonical
contract for a Balloon Crumbs planner plan.

Introduce a versioned `ForecastPlan` document with these bounded fields:

```text
ForecastPlan
  schemaVersion
  id, name, createdAt, expiresAt
  source = Balloon Crumbs web planner
  launch { point, elevationMsl, datum }
  destination? { point, toleranceMetres }
  intendedLandingArea { centre, radius/polygon, updatedAt }
  forecastLanding { point }
  departure { selectedAt, matchingWindowStart?, matchingWindowEnd? }
  constraints {
    altitudeCeilingMsl
    maximumAscentRateMps
    maximumDescentRateMps
    minimum/maximumDurationMinutes
  }
  altitudeStages[] { fraction, plannedAt, altitudeMsl, changeRateMps }
  plannedTrack[] { point, altitudeMsl, elapsedSeconds }
  landingEnvelope[]
  wind {
    provider, model, requestedAt, validFrom, validTo
    attribution, licence, forecastOnly = true
    fieldDigest
  }
  operationalBoundaries[]
  result { kind, reachesDestination?, missDistanceMetres? }
  gpxFallback
```

Bounds must cover maximum byte size, points, stages, polygon vertices, string
lengths and timestamps. Unknown additive fields are ignored; unknown schema
major versions are rejected with a readable error. Exact plan contents remain
encrypted at rest as today.

### API compatibility and rollout

1. Relay accepts and returns both existing GPX-only plans and structured plans.
2. Web planner writes `ForecastPlan` plus GPX fallback after server support is
   deployed.
3. Mobile reads structured plans first and falls back to typed GPX semantics.
4. Old mobile builds continue receiving a valid GPX field.
5. Once the supported tester population has migrated, GPX-only plan creation
   can be deprecated but not removed from file import/export.

## Planned altitude profile in real time

The airborne profile sheet lists the same six control positions as the web
planner: Launch, 20%, 40%, 60%, 80% and Landing. Each row contains:

- planned local time;
- planned altitude and datum;
- change from the previous stage;
- planned rate, constrained by the imported ascent/descent limits;
- forecast wind direction and speed used at that stage;
- whether the row is past, current or future.

Above the table the app shows original plan start, actual launch time, original
landing time, elapsed time, planned ceiling and actual maximum altitude. Actual
altitude and vertical rate are adjacent but never overwrite the plan.

If the flight starts outside the matching window, the original plan is marked
out of window. The user can request **Reforecast from current position** while
stationary/pre-launch or from the balloon crew inspection sheet. Reforecasting
creates a new live projection revision; it does not mutate history or relabel
the original plan as current.

## Wind grid and forecast freshness

- Open-Meteo UKMO remains the selected advisory forecast provider for tester
  builds.
- The field is a 5 × 5 grid spanning approximately 120 km, matching the planner.
- In planning mode it is centred on launch. During flight it re-centres when the
  balloon approaches the useful edge or after a material displacement, with
  request throttling and cancellation of superseded requests.
- Airborne views default to **Follow balloon altitude**. The slider can inspect
  20–2,000 m MSL without making another request because the complete vertical
  profile is held in memory.
- Chase crew may inspect wind; the driver view does not render the grid.
- Every display includes provider, model, requested/fetched time, valid time,
  altitude, speed unit and “forecast model—not an aviation briefing”.
- If refresh fails, the last field remains only with an explicit age/stale
  state. It is not extended beyond its validity and no guessed wind is used for
  a real live projection.
- A plan's original track remains available offline even when live reforecasting
  is unavailable.

The plan deliberately calls this “forecast wind valid now”, not “current wind”.
Observed balloon drift is not a direct wind measurement and is not promoted to
one in this scope.

## Live projection and possible landing areas

Three forecast products coexist and must remain named:

1. **Original forecast:** immutable planner output from the planned launch,
   start time and constraints.
2. **Live projection:** recomputed from the latest usable balloon fix, its
   current altitude, the remaining planning constraints and a fresh forecast
   field.
3. **Actual track:** measured craft telemetry after filtering/election.

The live projection:

- starts only from a usable fresh balloon fix;
- uses measurement time, not relay receipt time;
- uses the same altitude interpolation, wind interpolation, rate constraints
  and feasibility rules as the web planner;
- displays its forecast/model validity and computation time;
- stops updating when telemetry or wind is stale;
- never replaces the pilot's intended landing area;
- produces a live possible-landing envelope rather than claiming a landing
  site is safe, permitted or accessible.

The mobile forecast engine will be a Dart implementation because live operation
must not depend on running browser JavaScript. Planner-core JSON fixtures become
language-neutral golden tests consumed by JavaScript and Dart. The two engines
must agree within documented tolerances for track points, stage altitudes,
landing envelopes, reachability, duration and miss distance before the live
projection ships.

## Airspace and operational context

- OpenAIP is advisory chart context, not authoritative airspace or NOTAM data.
- The chart defaults on for pilot and balloon crew, is optional for chase crew,
  and is absent from the chase driver hierarchy.
- Its attribution, build/configuration age and limitations remain in the map
  information sheet; the chart key is accessible without covering telemetry.
- A stale/missing OpenAIP configuration produces a clear unavailable state and
  never leaves an unlabelled blank layer.
- Planner operational boundaries are carried in the structured plan and shared
  into the flight journal. They retain name, source, update time, geometry,
  optional altitude band and datum.
- Boundary alerts state source and age and are advisory. Official temporary
  restrictions and current NOTAM briefing remain an external pilot task.

## Intended landing area and landing state

The following remain distinct:

- **Planner intended area:** intent saved before the flight.
- **Current pilot intended area:** latest pilot-published revision during the
  flight; this supersedes planner intent for chase decisions.
- **Original landing envelope:** all feasible forecast endpoints calculated
  pre-flight.
- **Live possible-landing envelope:** endpoints calculated from current state.
- **Declared landing:** pilot says the balloon is committing to land.
- **Inferred landing:** telemetry indicates sustained descent/stopping.

The pilot edits an area, not a precision point. Every revision includes author,
measurement/update time and radius/polygon, commits locally first, then relays.
All chase devices update the area immediately on replay. The UI shows its age,
distance from the balloon and whether recent balloon travel is closing on or
opening from it.

## Chase target and dynamic road guidance

Target choice is **per chase vehicle** and shared between devices attached to
that vehicle. It is not one group route.

### Target choices

1. **Intended landing area** — default when the pilot has published a valid
   area. Route to a legal road endpoint serving the area.
2. **Road rendezvous near balloon** — use a fresh balloon fix as the evidence
   target, then validate a legal road endpoint near it. The UI never says it is
   routing directly to the airborne balloon.

Changing one vehicle's target does not change another vehicle. The latest
authorised target event for that craft wins; both driver and chase crew attached
to the craft see who changed it and when.

### Rerouting policy

Initial bounded policy values remain:

- balloon fix must be no more than 45 seconds old to create a new near-balloon
  target;
- ordinary moving-target reroutes require at least two minutes since the last
  request and at least 300 m target movement;
- a pilot landing-area revision, an explicit target change, or recovery from a
  stale fix can force immediate reconsideration;
- a road endpoint for a balloon target must be within 1,200 m of the evidence
  point;
- a landing-area endpoint must be within the area's radius plus a 500 m road
  margin.

These values are field-test defaults, not hidden constants. Route rationale
must record them so simulation and diagnostics can reproduce the decision.

The road router must use the selected vehicle profile, legal road network,
provider travel speeds and current traffic only when that provider legitimately
supplies it. It must not simulate progress at an arbitrary constant speed in a
live session. If the route cannot be built or its endpoint fails validation,
the previous route freezes and the app states why.

The driver receives one spoken announcement for a material target change or
stale state. The app does not nag and does not silently switch from pilot intent
to near-balloon pursuit when divergence grows.

## Shared location, tracks and intent

### Shared event/read-model contract

| State | Producer | Shared scope | Notes |
|---|---|---|---|
| Craft registration | Pilot or vehicle crew | Flight | One balloon, many vehicles |
| Device attachment | Local device | Flight | Idempotent; latest attachment wins |
| Flight-role assignment | Creator/pilot for authority; participant for own non-pilot role | Flight | Driver/crew changes require the vehicle to be stopped |
| Device location sample | Each device | Flight | Locally journalled before relay |
| Elected craft telemetry | Derived on every peer | Flight read model | One marker/track per craft |
| Forecast plan revision | Pilot | Flight | Structured plan plus GPX fallback |
| Intended landing revision | Pilot | Flight | Latest valid revision wins |
| Vehicle target choice | Driver/chase crew aboard vehicle | Vehicle + flight summary | Per craft |
| Vehicle road route | Each vehicle device | Device local | Full manoeuvres are not group authority |
| Road rendezvous/ETA summary | Vehicle guidance controller | Flight | Allows team awareness without route copying |
| Operational boundary | Pilot | Flight | Advisory source/age retained |
| Message/ground note | Permitted participant | Flight or addressed craft | Existing bounded event model |

Actual tracks are derived from accepted location events; they are not a second
independent stream that can disagree with telemetry. Every peer runs the same
craft election and track reducer. Several phones in one basket therefore create
one balloon track, while several chase vehicles create distinct vehicle tracks.

### Track retention and rendering

- Continue locally journalling the complete active-flight evidence within the
  configured privacy window.
- Render a performance-bounded recent window by default, with an explicit
  whole-flight view when stopped.
- Never drop older points merely because the vehicle has travelled beyond a
  short fixed distance.
- A stale craft keeps its last marker and completed track with a stale visual;
  it does not extend the track until a newer accepted fix arrives.
- Track sharing follows the existing offline-first relay/replay path, including
  deduplication and measurement-versus-receipt timestamps.

## State and controller separation

Replace the single active-route concept with explicit state owners:

```text
SharedForecastPlanController
  original structured plan
  planner geometry/profile/envelope
  current pilot plan revision

LiveFlightProjectionController
  fresh telemetry + fresh wind
  projected track + possible landing envelope
  source/validity/failure state

VehicleGuidanceController (one per local vehicle)
  selected target mode
  resolved road rendezvous
  device-local road route and manoeuvres
  reroute policy, ETA and failure state

CraftFlightState
  craft roster, elected telemetry, actual tracks, freshness

FlightAuthorityController
  pilot role, start/end, landing intent and handover
```

The map receives a role-specific presentation model rather than a collection of
booleans such as `isBalloonView`. The large active shell should be decomposed
around these state owners so forecast updates cannot replace road navigation
and a UI rebuild cannot change authority.

## P0 requirements and acceptance criteria

### P0.1 Production roles and crafts

- [x] Creating a flight writes pilot role, balloon registration and device
      attachment before opening the flight view.
- [x] Joining requires an airborne/vehicle assignment and a compatible role.
- [x] Vehicle creation/selection is idempotent and persists through restart.
- [x] Three devices in one balloon produce one craft marker and track.
- [x] Invalid role/craft combinations open a repair flow, never a guessed view.
- [x] Pilot handover is explicit, accepted and journalled.

### P0.2 Vocabulary migration

- [x] A test scans all production user-visible strings and fails on whole-word
      `ride`, `rider`, `leader`, `bike` or `motorcycle`, excluding documented
      compatibility/debug fixtures.
- [x] Navigation labels, dialogs, snackbars, notifications, accessibility text,
      CarPlay/Android projections and exports use flight/craft roles.
- [x] Internal legacy field names are documented and cannot be accidentally
      rendered directly.

### P0.3 Distinct live experiences

- [x] Pilot and balloon crew never render speed limits, road alerts, turn
      guidance, road progress or navigation export.
- [x] Pilot can update landing intent; balloon crew sees it without authority.
- [x] Driver view keeps road instructions and speed information reachable at a
      glance and hides airborne editing controls.
- [x] Chase crew sees the full tactical map and can control only its attached
      vehicle's target.
- [x] Role change updates the shell without losing flight or craft state.

### P0.4 Shared craft telemetry and tracks

- [x] Balloon and every chase vehicle location appears on every authorised
      device with fix age and live/relayed/stale/unknown state.
- [x] Each craft's actual track is shared and survives disconnect/reconnect.
- [x] Balloon track segments use the common altitude palette; missing altitude
      is grey and described accessibly.
- [x] Chase tracks use craft identity styling and never inherit altitude colour.
- [x] Out-of-order or duplicate fixes cannot regress a craft position or track.

### P0.5 Structured planner plan

- [x] Relay and mobile remain backward-compatible with GPX-only plan codes.
- [x] Structured plans retain all web-planner inputs, stages, envelopes, source
      metadata and operational boundaries.
- [x] The app displays original forecast, profile and limitations offline after
      one successful import.
- [x] Unknown schema versions fail safely and do not activate partial geometry.

### P0.6 Airborne forecast context

- [x] Pilot/balloon crew see actual track, original forecast and intended area
      with distinct non-colour styles.
- [x] Wind defaults to the balloon's altitude and can be changed/hidden.
- [x] Wind source, model, fetch/valid time, altitude, units and forecast warning
      remain visible.
- [x] Planned altitude stages list time, height and rate and highlights the
      current stage without issuing a control command.
- [x] OpenAIP is role-gated, attributed and explicitly advisory/unavailable.

### P0.7 Per-vehicle chase guidance

- [ ] Each chase vehicle independently selects intended-area or near-balloon
      road guidance.
- [ ] A pilot landing-area update reaches every vehicle and triggers bounded
      route reconsideration for vehicles following that area.
- [ ] Near-balloon mode refuses a stale balloon fix and never routes to a raw
      airborne coordinate.
- [ ] Reroutes use provider road geometry, speeds and vehicle constraints and
      preserve the last valid route on failure.
- [ ] Target selection, road endpoint, target age and reroute reason are visible.

## P1 requirements

- Live projected track and possible-landing envelope from current telemetry and
  fresh wind are implemented in mobile; JavaScript/Dart golden parity remains.
- Actual-versus-planned altitude chart and time-by-altitude wind table.
- Intended-area divergence trend and explicit alternative comparison.
- Landing inference and declared/inferred state presentation.
- Ground/access notes associated with landing/rendezvous areas.
- Whole-flight multi-craft replay with wind/plan/target revisions time-aligned.
- Physical CarPlay/Android Auto driver companion after role/view separation.

## P2 and explicitly deferred work

- Restricted observer and revocable public-tracking views built on the same
  craft read model.
- Multi-balloon operations, shared vehicle pools and dynamic reassignment.
- Fleet-level chase optimisation across several vehicles.
- Delegated landing-intent authority for balloon crew, if field evidence shows
  that pilot-only publication creates too much workload.
- Certified or official aviation briefing, NOTAM and flight-plan integration;
  these require separate provider, regulatory and liability decisions.

## Implementation slices and dependency order

Each slice must be independently reviewable, keep mixed-version behaviour safe,
and end with a tester-observable outcome.

### Slice 0 — Contract and migration scaffolding

- Add `FlightRole` to persisted session and event projection.
- Define dual-write/read compatibility with `RideRole`.
- Add assignment validation and a role/craft presentation model.
- Introduce string-lint allowlists for internal compatibility names.

Exit: production code can represent every target persona without changing the
existing screens yet.

### Slice 1 — Production craft/role assignment

- Implement create, join, resume, repair, vehicle selection and pilot handover.
- Register/attach crafts through the existing journal APIs.
- Move roster and local-view selection to craft state.

Exit: one balloon with multiple devices and several vehicles is correctly
formed in a real flight and survives restart/replay.

### Slice 2 — Separate forecast and road state

- Introduce shared forecast-plan and per-vehicle guidance controllers.
- Migrate landing intent and operational boundaries to flight authority.
- Ensure forecast changes cannot replace vehicle road routes.
- Include the forecast-purpose import fix if it has not already merged.

Exit: a pilot can load/change a forecast while a chaser retains independent
road guidance.

### Slice 3 — Role-specific shells and terminology

- Build pilot, balloon crew, chase driver and chase crew compositions.
- Replace user-facing legacy vocabulary and craft-inappropriate icons.
- Add role contract widget tests and small-screen/landscape overlap tests.

Exit: testers can identify their role from the first screen and no role sees an
inappropriate control.

### Slice 4 — Structured planner parity

- Version the plan API and encrypted storage.
- Extend the web planner writer and mobile reader.
- Persist altitude stages, constraints, envelopes, wind metadata and boundaries.
- Add GPX fallback and mixed-client contract tests.

Exit: one plan code reproduces the web planner's complete evidence in the app.

### Slice 5 — Airborne live-flight information

- Use the shared altitude renderer for original and actual paths.
- Build profile, wind-grid, airspace and landing-area layers for airborne roles.
- Add current-stage and actual-versus-plan presentation.
- Add Dart planner-core parity fixtures and the live projection behind a tester
  feature flag.

Exit: the pilot/balloon crew can understand original plan, actual flight and
fresh forecast context without road UI.

### Slice 6 — Chase target and tactical workflow

- Make target choice vehicle-scoped and shared between its devices.
- Complete dynamic road routing, endpoint validation, route rationale and ETA.
- Add chase mini-map/tactical map, all craft tracks and landing divergence.
- Add moving/stale/landing-revision voice events.

Exit: two chase vehicles can choose different targets and reroute independently
while sharing their positions and tracks.

### Slice 7 — Replay, failure and field evidence

- Extend simulator and flight archive to all roles, crafts, tracks, wind and
  target revisions.
- Exercise offline recovery, stale providers, clock skew, role changes and
  mixed app versions.
- Validate on physical iOS/Android devices and in a moving vehicle where lawful.

Exit: the acceptance matrix passes and the feature is ready for tester rollout.

## Test strategy

### Unit and contract tests

- Role/craft compatibility, authority and handover.
- Event replay, idempotent registration, attachment and migration.
- Craft telemetry election and complete track reduction.
- Forecast-plan schema bounds and backward compatibility.
- JavaScript/Dart forecast golden fixtures across wind direction wrap,
  interpolation, ascent/descent constraints, start windows and impossible
  destinations.
- Landing intent revisions, divergence and reroute hysteresis.
- Road endpoint separation and stale-fix refusal.

### Widget tests

For every role, portrait/landscape and small/large phone:

- required controls exist;
- forbidden controls do not exist;
- critical controls do not overlap;
- map legend and source/freshness information are reachable;
- driver moving mode cannot expose touch-heavy editing;
- role changes preserve shared state and select the correct shell.

### Integration and simulation matrix

Minimum simulated flight:

- pilot plus two balloon-crew phones attached to one balloon;
- two chase vehicles, each with driver and chase-crew devices;
- ascent, two level wind layers, descent and landing;
- pilot landing-area revision mid-flight;
- one vehicle follows intended area and one follows near-balloon rendezvous;
- relay loss/recovery, stale balloon fix, stale wind, route provider failure and
  out-of-order events;
- distinct shared tracks for the balloon and both vehicles;
- restart one device of every role and verify assignment recovery.

### Physical field gates

- iOS and Android background location and altitude behaviour.
- Battery/thermal behaviour over a representative two-hour operation.
- Voice interruption, Bluetooth and vehicle audio.
- Real routing speed/ETA behaviour and safe road endpoints.
- Glove/sunlight/readability checks for pilot controls.
- Driver distraction review and physical CarPlay/Android Auto only when enabled.
- OpenAIP/Open-Meteo attribution and stale/unavailable states without network.

## Success metrics

Leading indicators:

- 100% of tester devices enter a view matching their explicit role/craft.
- Zero role-contract failures in automated UI tests.
- Zero user-visible forbidden legacy terms in the production string scan.
- 95% of accepted craft fixes reach a connected peer within 10 seconds.
- 100% of balloon fixes from several basket devices resolve to one craft track.
- At least 95% of structured plans reproduce planner stages and geometry within
  documented tolerances on both mobile platforms.
- Fewer than one unnecessary automatic chase reroute per five minutes in the
  reference simulation.

Field-test indicators:

- At least 90% of testers identify their role and main action without help.
- At least 80% of pilots/balloon crew rate plan-versus-actual distinction 4/5.
- At least 80% of chase crews rate target/rendezvous clarity 4/5.
- No report of an airborne role receiving road directions or a chaser treating
  forecast geometry as its road route.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Legacy and new roles disagree in mixed builds | Dual-write, deterministic migration and mixed-version tests |
| Several phones create duplicate craft tracks | Craft-level telemetry election and one reducer per craft |
| Forecast and road route overwrite one another | Separate controllers and storage contracts before UI work |
| JavaScript and Dart forecast engines drift | Shared golden fixtures and explicit numeric tolerances |
| Forecast wind is mistaken for observation | Persistent provider/validity/forecast-only labels |
| Original and live forecasts are confused | Immutable original plan plus named, revisioned live projection |
| Pilot controls become crowded again | Role-specific shells, one primary action band, sheet-based inspection and overlap tests |
| Driver becomes distracted by tactical features | Separate driver/crew roles; moving lockout and voice-first design |
| Stale landing intent is trusted | Age, distance/divergence and explicit degradation |
| OpenAIP is treated as official/current NOTAM data | Advisory label, configuration validity and official briefing reminder |
| Provider loss removes all context | Original plan remains offline; stale state freezes rather than guesses |

## Decisions required before implementation

The following recommended decisions make the plan implementable without later
re-cutting authority or state ownership:

1. **Pilot authority:** only the pilot publishes landing intent and starts/ends
   the flight. Balloon crew inspect and communicate but do not mutate authority.
   **Recommendation: accept.**
2. **Vehicle target ownership:** driver and chase crew aboard the same vehicle
   share one vehicle target; the latest valid choice wins and identifies its
   author. **Recommendation: accept.**
3. **Wind wording:** Open-Meteo is displayed as forecast wind valid for the
   current time, never measured live wind. **Recommendation: accept.**
4. **Forecast preservation:** always show the immutable original plan separately
   from any live projection. **Recommendation: accept.**
5. **Forecast implementation:** port the calculation core to Dart and enforce
   parity with shared fixtures rather than depend on browser JavaScript or a
   network calculation service during flight. **Recommendation: accept.**
6. **Scope of “all planner features”:** pre-flight editing remains in planning
   mode; active views receive the plan evidence and real-time adaptations, not
   place search and draggable launch controls over the live map.
   **Recommendation: accept.**
7. **First release roles:** deliver pilot, balloon crew, chase driver and chase
   crew; keep observer behaviour unchanged. **Recommendation: accept.**

## Ready-to-implement checklist

Implementation can start when:

- [x] The seven decisions above are accepted or amended.
- [x] The role and permission matrix is accepted.
- [x] The four view definitions are accepted.
- [x] The structured `ForecastPlan` boundary is accepted.
- [x] The original/actual/live visual language is accepted.
- [x] The per-vehicle target model and initial reroute thresholds are accepted.
- [x] The slice order and P0/P1 boundary are accepted.
