# Delivery Plan

How Balloon Crumbs becomes useful to a balloon pilot and a retrieve crew, from
the Tail End Charlie baseline it was scaffolded from. [PLAN.md](../PLAN.md) is
the product requirement; this is the engineering order of work.

## Where the code actually is

Measured on `apps/mobile/lib` (~80,000 lines of Dart):

| Motorcycle concept | Hits | Files | Verdict |
|---|---:|---:|---|
| Drop-off marker system | 1,201 | 61 | delete |
| Road hazards | 702 | 36 | repurpose as ground notes |
| Rejoin routing | 466 | 26 | delete, replaced by rendezvous |
| Junction logic | 240 | 34 | delete with the marker system |
| Speed-camera / enforcement alerts | 183 | 15 | keep, retarget at the chase driver |
| Speed-limit display | 17 | 9 | keep, retarget at the chase driver |
| Road ratings ("twisty road" scoring) | 12 | 8 | delete |
| Personal ride heatmap | 81 | 2 | delete |
| `rider` as the domain noun | 3,889 | 169 | rename to crew/participant |

Against that, the balloon domain is close to empty: before WP2, `altitude`
appeared **zero** times and `pilot` still does. This is a domain-layer rewrite
with infrastructure reuse, not an adaptation — and the motorcycle code is
currently the larger half of the app.

### Already done

- **WP1** — the Tail End Charlie sweep role is deleted, on both client and relay.
- **WP2 (part)** — `LocationSample` carries altitude, altitude source, vertical
  accuracy and vertical speed; capture gates on vertical accuracy so a missing
  altitude is never presented as a measured zero; Ride Lab flies a real climb /
  cruise / descent profile.
- The product, bundle identifiers, packages and icon are renamed.

## Who the app is for

Three jobs, and the current app serves none of them. Every work package below
should be readable as "which of these got better".

**The pilot.** Flies with gloves on, one hand on the burner, in noise and cold,
often solo in the basket. Cannot type, cannot read a paragraph, must not be
asked to make a decision to keep the app working. Wants: publish where I am and
whether I am climbing, see that the crew has me, tell them roughly where I intend
to land, and nothing else.

**The balloon crew.** One or more people in the basket, and frequently *they*
hold the phone because the pilot is flying. This is why the app cannot assume
one device per craft, and cannot assume the pilot's device is the one reporting.

**The chase crew.** One to four vehicles on the road, each with a driver who must
not touch the phone while moving, plus passengers who can. Wants: where is the
balloon now, where will it be, which road gets me there, which of us goes where,
and at the end — how do we reach a field with a trailer.

## The architectural decision this all rests on

The inherited model has a flat list of `rider`s, each with its own position. That
breaks immediately for ballooning in two directions at once: several phones in
one basket become several "riders" sitting on top of each other, and the chase
crew has no way to ask "where is *the balloon*".

**Introduce a craft.** One flight has one balloon and zero or more vehicles
today, and the model must not assume that number is one forever — see
"Designed-for, not built-yet" below. Devices attach to a craft; a craft has one position, contributed by
its devices. That single change answers both of the requirements that prompted
this plan:

- Several crew in the basket → several devices on the balloon craft → **one**
  balloon track, and the crew all see the same thing.
- Several chase vehicles → several vehicle crafts → one track each, individually
  addressable ("Vehicle 2, take the B4039").

It also stops the pilot's phone dying from being the single point of telemetry:
any device on the craft can carry the stream.

**Which device speaks for a craft** must be resolved deterministically from the
journal, so every peer computes the same answer without negotiation — the same
discipline the deleted TEC resolution used, and the reason it was worth studying
before deleting it. Proposed rule, in order: freshest fix inside a quality
threshold, then the device the pilot marked as primary, then lowest device id as
a tie-break; with hysteresis so the balloon's track does not visibly jump
between two phones sitting side by side. A craft with no usable fix reports
*unknown*, never a stale position dressed as current.

### Designed-for, not built-yet: multiple balloons

A club event has several balloons and a pool of vehicles, and a vehicle may
switch which balloon it is chasing mid-flight as distances and winds change.
That is a genuinely different product and it is **backlogged**, not being built
now. But it constrains WP3 today, cheaply, and those constraints are worth
paying for while the model is being written:

- **A flight holds a set of crafts, not a balloon field plus a vehicle list.**
  "The balloon" is a lookup over crafts of kind balloon, not a dedicated slot.
  One balloon is then a cardinality the UI enforces, not an assumption baked
  into every read model.
- **A vehicle's chase assignment is its own journalled fact**, separate from
  membership. A vehicle *belongs to the flight* and *is currently chasing craft
  X*. With one balloon that assignment is implicit and invisible; with several it
  becomes the interesting state, and reassignment is just a new event rather than
  a schema change.
- **Guidance takes a target craft as a parameter**, never reads a global balloon.

That is roughly a day of extra care in WP3 and it avoids re-cutting the data
model later. What is explicitly *not* being built: the assignment UI, the
distance/wind optimiser that suggests which vehicle should switch, and per-balloon
crew rosters.

## What gets deleted

These are motorcycle-group-riding concepts with no ballooning equivalent.
Deleting beats translating: a renamed concept keeps its assumptions alive in the
roster, the relay and the map.

1. **The drop-off marker system** (1,201 hits, 61 files, 7 dedicated files plus
   junction logic). A second bike holds a junction until the group passes. There
   is no junction and no group to hold it for. This is the single biggest
   deletion and it has already been partly forced: WP1 removed its "the back of
   the group is through" signal, so the marker currently waits for something
   that can never arrive.
2. **Rejoin routing** (466 hits). Routes a separated rider back onto a shared
   GPX route. A chase vehicle is never "off route" — it is on a road network
   heading for a moving target. Replaced wholesale by rendezvous selection.
3. **Road ratings** and **personal heatmap** — **done**. Scoring roads for fun.
   The client feature and its relay capability are gone; the server's
   `/api/v1/discovery/road-ratings` endpoints and their `road-ratings-v1`
   advertisement remain and should go with the next server pass, since removing
   public API surface deserves its own change rather than riding along with a
   client deletion.
4. **Motorcycle iconography** — `motorcycle_icon.dart`, rider symbols, bike
   styles — replaced by craft iconography (balloon, vehicle).

## What gets kept

Genuinely valuable, domain-neutral, and expensive to rebuild:

- The **SQLite event journal** with idempotency, dedup and replay. This is the
  best thing in the inherited codebase and the reason offline-first works at a
  rural landing site with no signal.
- **Six-digit codes and QR bootstrap**, anonymous membership lifecycle.
- The **nearby transport** and the **bounded HTTPS relay plus server**.
- **Location capture**, background delivery, permission flows, battery discipline.
- **Map rendering**, tiles, style repository, offline fallback.
- **GPX** import/export, diagnostics recorder, the simulator harness, CI.
- **Quick messages** (crew comms) and **emergency contact sharing** — arguably
  more important in an aviation-adjacent context than they were for riding.
- **Observer sharing** — a bounded read-only link is exactly what a balloon
  operation wants for family watching from home.
- **Speed-limit display, speed-camera and enforcement alerts** — kept and
  retargeted at the chase driver, who is doing exactly the road driving these
  were built for. They must appear only in the chase-driver view: a pilot has no
  use for a camera warning and showing one in the basket is noise.
- **CarPlay and Android Auto** — kept for the chase driver, who is a better fit
  for a head unit than a motorcyclist ever was. Currently inert: the entitlements
  and the scene declaration were removed so the app could be signed and installed
  without an Apple-approved CarPlay profile. Restoring it means re-adding both
  entitlement keys, the `CPTemplateApplicationSceneSessionRoleApplication` scene
  declaration, and a matching console profile — all three together, or the app
  crashes on device while working in the simulator.
- The **hazard machinery, repurposed**: the ability to drop a categorised,
  relayed, expiring point on a map is precisely what ground notes need (locked
  gate, impassable track, power lines, landowner contacted, crop in field). This
  is reuse of ~700 hits of working code, not a rewrite.

## Work packages

Ordered by dependency. Each lands with the analyzer clean and both suites green.

### WP3 — The craft model, flight roles and pilot authority

The keystone. Nothing else is honest until this exists.

- `Craft { id, kind: balloon | vehicle, label }`; one balloon per flight.
- `FlightRole { pilot, balloonCrew, chaseDriver, chaseCrew, observer }`, held by
  a device, attached to a craft.
- Deterministic per-craft telemetry election with hysteresis (above).
- Pilot authority: only the pilot can start/end the flight and set the balloon's
  primary device; a pilot handover is explicit and journalled.
- Craft-level read models replace rider-level ones on every surface.

Acceptance:
- [ ] Three phones in one basket produce one balloon track, not three
- [ ] Handing the phone between two crew does not make the balloon's track jump
- [ ] Four vehicles are individually identifiable and addressable at every zoom
- [ ] A craft with no usable fix reports unknown; no surface shows a stale fix as live
- [ ] A restarted phone rejoins its craft in its role without a ghost member

### WP4 — Delete the motorcycle domain

Best done immediately after WP3, while the new model is fresh and before more
code is written on top of the old one. Everything in "What gets deleted",
plus the vocabulary rename (`ride` → `flight`, `rider` → `crew`) done **once**,
into the shape WP3 established rather than twice.

Acceptance:
- [ ] No `marker`, `rejoin`, `road rating` or `heatmap` code remains
- [ ] No user-facing string says rider, bike or ride
- [ ] Test count drops honestly — deleted features lose their tests, nothing else does

#### Measured: the marker cut is wider than the marker files

A trial deletion was made and reverted; the tree is green. Removing the seven
marker files, `RideRole.marker`, the three marker event types and
`RideCoordinationMode.secondBikeDropOff` produces **148 analyzer errors**:

| File | Errors |
|---|---:|
| `features/map/ride_map_feature.dart` | 22 |
| `features/map/route_review_screen.dart` | 20 |
| `controllers/ride_controller.dart` | 16 |
| `features/ride/ride_dashboard.dart` | 11 |
| `services/route_decision_point_extractor.dart` | 10 |
| `features/ride/active_ride_shell.dart` | 9 |
| `controllers/ride_simulation_controller.dart` | 6 |
| `services/route_reshape_planner.dart` | 5 |
| `features/home/home_screen.dart` | 5 |
| others (tests, reducers) | 44 |

Almost all are references to deleted symbols, so mechanical. **The finding that
matters is which files they are in.** `route_marker_plan.dart` is not a leaf: the
route-*planning* layer depends on it —
`route_decision_point_extractor`, `route_reshape_planner`,
`route_waypoint_editor` and the 1,385-line `route_review_screen` all consume
`MarkerPlanPointKind`, `DecisionPointSource` and `RouteMarkerPlanAnalyzer`.

So the cut is: marker system **plus** the decision-point extraction that exists
only to place markers on a planned route. Route review and waypoint editing then
need a decision of their own — a chase crew does not review a planned route
before a flight the way a ride leader did, because the balloon has no route. My
reading is that route review goes with the marker system and waypoint editing
survives only if GPX-based chase planning survives, which WP7 should answer
first.

Sequencing that follows from this: **do WP7's rendezvous design before the marker
deletion**, or the deletion will strip route planning with nothing decided about
what replaces it.

Two smaller deletions are genuinely self-contained and can land independently:
road ratings and the personal heatmap.

Migration note found in the same pass: `RideCoordinationMode.fromName` defaults
to `secondBikeDropOff` for any unrecognised value, because that was the only mode
before the choice existed. When it is deleted the fallback must become
`keepTogether`, not `solo` — falling back to solo would silently strip a stored
flight of its join code and its crew.

### WP5 — Altitude, the ground track, and the crumb trail

The feature the product is named after. Finishes WP2.

- Altitude into the recorded track so flight GPX carries `<ele>` (issue #16);
  altitude source and accuracy in the GPX extension namespace.
- Ground track coloured by altitude, with a documented palette, a non-colour cue
  and a legend that tracks metric/imperial.
- A segment may only be coloured when both endpoints have valid altitude.
- Telemetry card: height, climb/descent rate, fix age, source, ground speed,
  track. Every number carries its age.
- Reject impossible vertical jumps rather than smoothing them away.

### WP6 — The pilot view and the landing intent model

Deliberately austere. Big type, few controls, works with gloves.

- Height, climb rate, and "the crew can see you" / "nobody has your position".
- Start/end sharing, and a privacy stop.
- No routing, no hazards, no camera alerts, no chase detail — the pilot is flying.

#### Landing intent

Three separate things, and conflating them is the failure mode:

1. **Intended landing area** — the pilot draws an area on the map (not a point;
   a balloon lands in a region, and a point implies a precision nobody has).
   Editable at any time; each edit supersedes the last in the journal. Relayed to
   every vehicle.
2. **Committed to landing** — a single large button meaning "I am landing, near
   where I am now". Available always, but the view should surface it prominently
   once descent is detected, because that is when it is true and when a pilot has
   least attention to spare.
3. **Inferred landing** — what the app works out on its own.

**The chase crew must never depend on the button.** A pilot with both hands on
the burner will forget it, and a crew that has learned to wait for it will sit
still while the balloon is on the ground. So the app infers the landing phase
independently, from telemetry it already has after WP2: sustained descent over a
window, falling height, collapsing ground speed, and finally a stationary fix.
Guidance escalates on the *inference*; the button only raises confidence sooner.

Every surface must show **which** it is looking at — declared or inferred — and
never present one as the other. A declared landing with the balloon still at
600 m climbing is a mis-tap, and the app should say so rather than send four
vehicles to a field.

**Staleness is the real hazard here.** An intended area drawn twenty minutes and
eight kilometres ago is worse than no area, because the crew will trust it. Every
presentation of the area carries its age and the balloon's current distance from
it, and it degrades visibly once the balloon has drifted outside it.

Acceptance:
- [ ] Pilot draws, edits and clears an area; every vehicle sees the current one
- [ ] Landing is inferred with the button never pressed, and guidance escalates
- [ ] Pressing the button while high and climbing is shown as inconsistent, not obeyed
- [ ] Every area display carries its age and distance from the balloon
- [ ] An area the balloon has drifted out of is visibly degraded, not silently kept

### WP6b — Landing-phase mapping

A road map is the wrong map once the balloon is down in a field. The last few
hundred metres are about field boundaries, tracks, gates and footpaths, and the
road network stops being the useful layer.

- A second basemap for the landing phase — Ordnance Survey style topographic
  and/or aerial imagery — switched to automatically once the landing phase is
  inferred, and switchable by hand at any time.
- Field boundaries and access tracks matter more than road classification.
- Offline caching of the landing-area tiles matters more here than anywhere else
  in the app: landing fields are exactly where there is no signal.

**Licensing gates this.** OS Open data (for example OS Open Zoomstack) is Open
Government Licence and usable with attribution; the OS Leisure 1:25k raster that
crews actually recognise is a paid OS Data Hub product with its own terms, and
aerial imagery is licensed separately again. Decide the source before building
the layer, and cache nothing before the licence is read.

### WP7 — Multiple chase vehicles and rendezvous

Where the chase crew gets its value.

- Bounded prediction of where the balloon will be, with age and uncertainty
  shown, never presented as certainty.
- Road-accessible rendezvous candidates on the legal network, with hysteresis so
  the target does not churn.
- **Vehicle assignment**: with several vehicles, the app should help them spread
  rather than all converge on one gate — suggest one ahead of the projected
  track, one trailing, and never route two vehicles to the same point without
  saying so.
- Explicit separation of balloon position, predicted area, and road target.
- Losing balloon fixes freezes the last target and says so.

### WP8 — Voice-first chase guidance

- Spoken manoeuvres, recalculation, loss of fix, arrival.
- Mute and stop in one action; nothing requires a driver to look.
- Announcements when the balloon's state changes materially (started descending).

### WP9 — Ground notes and the retrieve

The end of a flight is the hardest part and the inherited app has nothing for it.

- Repurposed hazard machinery: gates, tracks, power lines, crop, landowner
  contacted, permission refused.
- Landing site: who is there, who has the trailer, what access exists.
- Explicitly **never** asserts that access is permitted or safe.

### WP10 — Simulator and replay matrix

- Balloon profiles: climb, level, descent, GNSS loss, barometric vs GNSS.
- Multi-craft: one balloon plus three vehicles, clock skew, reconnect.
- Several devices in one basket, to exercise the WP3 election directly.

### WP10b — Pilot aeronautical context and flight documentation

Distinct from WP11's chase-crew weather layer: this is for the person in the
basket, and it is the one place the app talks to an aviator about aviation.

- Airspace the pilot cares about: controlled airspace, ATZs and MATZs, danger and
  prohibited areas, gliding and parachute sites, and the temporary restrictions
  that only exist on the day.
- Notices to aviators, surfaced with their validity window, not as a static list.
- Attaching a filed flight plan or notification to the flight so the crew — and
  an observer — can see it alongside the track.

**Two things I do not know and must not guess.** First, the exact regulatory
mechanism for UK balloon flights: whether a given flight requires a filed flight
plan at all, what notification is expected for particular airspace, and what
form any of it takes. VFR balloon flying is not the same as an airliner filing
an ICAO plan, and this plan should not pretend otherwise. Second, whether any
of it can be *generated* rather than merely attached — that depends on whether
the CAA or NATS offers a filing interface a third-party app may use, which needs
checking rather than assuming.

So this package starts as research, not code: confirm with the CAA and the BBAC
what a UK balloon pilot is actually required and able to do, then decide whether
the app attaches a document, links to an official service, or generates anything
at all. **Generating a flight plan the pilot then relies on is a safety claim**,
and it needs the regulatory position understood before a line is written.

Airspace and notice data are subject to the same licensing gate as everything
else in WP11 — and the currency requirement is stricter, because out-of-date
airspace shown confidently to a pilot is worse than showing nothing. Any layer
must display its effective date and refuse to present stale data as current.

### WP11 — Context: weather, wind, airspace

Blocked on provider licensing (issues #13, #17) and should stay blocked until it
is resolved. Wind at altitude is the single most valuable addition for a chase
crew — it is what makes prediction credible — which is exactly why the licence
question deserves a real answer rather than a quick integration.

### WP12 — Release evidence

Security and privacy review, per-device authority replacing the inherited group
HMAC, retention, battery and background testing, accessibility of the altitude
representation without colour, mixed-device field matrix.

## Decisions taken

1. **Speed limits, camera and enforcement alerts — kept**, retargeted at the
   chase driver and confined to the chase-driver view.
2. **CarPlay / Android Auto — kept** for the chase driver. Inert until the
   entitlement is restored; see "What gets kept" for the three things that have
   to go back together.
3. **Multiple balloons — backlogged** (items 22, 23) but constraining WP3 now.
4. **Landing intent — three separate things**, with the chase crew depending on
   the inferred landing rather than the pilot's button. See WP6.
5. **Landing-phase map — a second basemap**, OS topographic or aerial, switched
   automatically once landing is inferred. Licence decided before it is built.

Still open, and needing an answer before its package starts:

- **Landing map source.** OS Open Zoomstack (OGL, free, attribution) versus the
  paid OS Leisure 1:25k raster crews actually recognise, versus aerial imagery
  licensed separately again.
- **The UK flight plan / notification position**, which is research before code.

## Risks

- **Scale.** 80,000 lines written for a different sport. Every package must land
  green or the baseline stops being a usable reference.
- **Safety framing.** The inherited copy talks to riders about road hazards.
  Every string that reaches a pilot or a driver needs rewriting, not translating.
  This is the risk most likely to be underestimated.
- **The pilot is flying an aircraft.** Anything that asks for attention in the
  basket is worse than nothing. The pilot view should be judged by how little it
  asks.
- **Provider licensing** gates the highest-value feature (wind), and no dataset
  should be cached before its licence is reviewed.
