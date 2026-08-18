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
3. **Road ratings**, **personal heatmap** and the **discovery layers** —
   **done on the client**. Scoring roads for fun, curated motorcycling roads
   (`twistyHighlight`, `mountainPass`, `goodBikingRoad`) and a scraped
   bike-and-brew place list. Deleting the discovery layers also removed **13.8 MB
   of bundled assets** — a 13.7 MB catalogue of 1,100 good biking roads, 944
   twisty highlights and 37 mountain passes, plus 141 KB of biker cafés — which
   was the largest thing in the bundle and was read on every map open.

   `route_twistiness` deliberately stays: it is the engine behind `RouteStyle`'s
   twisty bias, and that bias is a person's choice which WP7 has to rule on.
   Deleting the engine while leaving the choice on screen is worse than doing
   both or neither.

   **The server side is now gone too, in two deliberate halves.** First the
   reversible one: five routes (`/api/v1/discovery/features`, `/suggestions`,
   `/road-ratings`, and two `/api/v1/admin/discovery/...` endpoints), the
   moderation queue, an admin token and its rate limits, and the
   `road-ratings-v1` advertisement. Then the irreversible one, migration 0011:
   the four tables (`discovery_suggestions`, `discovery_moderation_events`,
   `discovery_features`, `discovery_road_ratings`) and the wire schemas that
   described their request bodies.

   The split was the point. Withdrawing an API can be undone by reverting a
   commit; dropping the rows it wrote cannot, and two of those tables held
   user-contributed text with the moderation reasoning behind each decision.
   Deleting that as a side effect of a client change would have been the wrong
   shape of change even with the same end state. Confirmed with the owner that
   no deployed Balloon Crumbs database held anything worth exporting; the drop
   also cannot reach Tail End Charlie's data, because every Compose project runs
   its own Postgres in its own namespaced volume and the only `external: true`
   in `deploy/` is the proxy network rather than storage.

   `downgrade` rebuilds all four tables with their original indexes, unique
   constraint and foreign keys, verified against a throwaway Postgres 17 with
   rows planted so the drop met real referential integrity. It restores zero
   rows, which is stated rather than implied: structure is recoverable from the
   migration, data only from a backup taken before it ran.
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
- [x] No `marker`, `rejoin`, `road rating` or `heatmap` code remains
- [x] Deviation detection and off-route alerting are gone with them
- [ ] No user-facing string says rider, bike or ride — **deferred by design**, see
      "the craft model has no creation path" below: the rename waits for the
      surfaces to move onto crafts so it happens once
- [x] Test count drops honestly — deleted features lose their tests, nothing else does

#### Landed: the marker system, route planning and rejoin routing are deleted

Done in one cut, as the measurement below predicted it had to be. The measured
148 analyzer errors were the marker files alone; the finished cut touched 60
files and removed about 9,900 lines of the motorcycle domain.

Deleted: the seven marker files, `RideRole.marker`, the three marker event
types, `RideCoordinationMode.secondBikeDropOff`, decision-point extraction,
route review, waypoint editing, route reshaping, the junction-marker map overlay
and its CarPlay card, the Ride Lab marker simulation, `route_rejoin_planner`,
`rejoin_route_share`, `rejoinRouteShared` and the `rejoin-route-sharing-v1`
capability on both client and relay.

Deviation detection and off-route alerting followed in a second commit, because
they are a subsystem of their own rather than a tail of the marker cut:
`route_deviation_detector`, `route_alert.dart`, `leader_ride_status`,
`leader_track_exemption`, `routeDeviationChanged` / `routeAlertAcknowledged`,
the leader's off-course banner, the roster's off-course attention label, the
CarPlay route-alert channel, the awareness screen's route-status card and
riders-needing-attention list, `RiderTrailKind.offRoute` and its dashed pink
line, and the relay's off-course push.

Three things survived that cut too:

- **The roster's Attention filter**, now meaning a rider whose position has gone
  quiet rather than one off a planned line. That is the half of it a chase crew
  still needs, and it is the same signal WP7's availability model is about.
- **The leader trail**, which was an input to the off-course exemption but is
  also the group's ground truth on the map and in the flight log.
- **`ride_connectivity_summary`'s 90-second stale threshold**, which used to be
  tied to the detector's coordinator-stale band. The comment now says so, and
  says WP7 should hold its availability model against that number rather than
  inventing another one.

Four things were kept that a naive cut would have taken with it, each because
the deleted feature was not their only reason to exist:

- **A route confirmation gate.** Route review was the only thing standing between
  a candidate route and the authoritative group route, and the flows it guarded
  survive: GPX import, destination planning, the demo route, and the traffic
  alternative. `route_confirmation_sheet.dart` replaces it — name, distance,
  duration, turn count, warnings, cancel or confirm. No map preview, no stop
  editing, no reshaping; WP7 builds chase-plan sketching from a clean sheet.
- **`routeLengthMeters` and `materialRouteChangeWarning`**, which lived in the
  review screen and are now `services/route_length.dart`. The second is the
  "this route is 40% longer than your current one" warning, which is exactly the
  kind of thing a confirmation gate exists to say.
- **`RiderTrailKind.rejoin`**, renamed `routeStartConnector`. The advisory rejoin
  line was not its only user: the route-start connector (#133) draws in the same
  channel and inherited its cyan dashed styling.
- **`route_origin_bearing.dart`**, renamed off its `rejoin*` prefixes to
  `originBearingForTravel` / `originBearing*`. Sending the vehicle's heading with
  a routing request (#444) is the router's problem, not rejoin's, and WP7's
  engine needs it.

One deliberate behaviour change worth knowing: `_spokenAudioMode` used to drop
to alerts-only while off route, because turn-by-turn for a route the rider is not
on names junctions that are not coming (#415). Nothing computes "off route" any
more, so the rider's chosen mode simply stands. If WP7's divergence model wants
to quieten guidance when the crew stops trusting the landing zone, that is a new
rule with a new input, not this one restored.

Two notes for whoever reads the diff:

- `MarkerPlanReview` went with the marker system, and with it the
  `tec:marker-review` GPX extension. An older file carrying that block still
  imports; the block is simply ignored.
- `tailEndCharlie` is still accepted by the relay's role schema and reducer.
  WP1 deleted the role but deliberately kept parsing it so an older peer's sync
  is not rejected wholesale; `marker` now degrades to `rider` by the same rule.

The measurement that drove the sequencing is kept below, because it is the
argument for why this was one cut rather than four.

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

#### Decided: what replaces route planning for a chase crew

The blocker above is a product question, so here is the answer rather than a
deferral.

The inherited model is: a leader plans a GPX route in advance, riders follow it,
markers are placed at its decision points, and anyone who leaves it is flagged
off-route. **Every one of those four assumptions fails for a balloon chase.** The
balloon has no route — it goes where the wind takes it. The crew's route is
computed continuously toward a target that is moving and not on a road. A chase
vehicle is never "off route"; it is en route to a rendezvous that changed thirty
seconds ago.

So pre-planned-route-following is not the chase crew's tool, and the following
goes with the marker system:

- **Decision-point extraction** — exists solely to find junctions worth placing a
  marker at.
- **Route review** (1,385 lines) — the pre-flight "check the route and place your
  markers" flow.
- **Deviation detection and off-route alerting** — measures distance from a
  planned line that will not exist.
- **Waypoint editing and route reshaping** — editing a route the group will
  follow. WP7 rebuilds whatever chase-plan sketching turns out to be worth
  having, rather than inheriting an editor built for a different job.

What survives, and why:

- **GPX import/export** stays. It is how crews exchange landing-field access,
  gate locations and previous flight tracks, and how a flight log leaves the app.
  Importing a *track* is useful; following a *route* is not.
- **The road router** stays and becomes WP7's engine.
- **The map, tiles and offline cache** stay — they were never route-specific.

Sequencing, now unblocked: the marker deletion may proceed on this decision, and
should take decision-point extraction, route review, deviation detection and
waypoint editing with it in one cut. That is a bigger single change than the 148
errors measured above, so it wants a session of its own with nothing else in it.

WP7 then starts from a clean sheet: a target that moves, a road network, and
hysteresis — not a planned line with riders scattered around it.

#### What the chase crew is actually routed to

Not the balloon's current position, and not a pre-planned line. **The primary
routing target is the pilot's intended landing zone** — a real place, on the
ground, reachable by road, which the crew can be sent to long before the balloon
gets there. That is the difference between arriving with the balloon and arriving
twenty minutes after it.

But the intended zone is a guess by someone who is flying, so it cannot be the
only input. Alongside the route, the crew needs the **gap to the balloon** —
distance, bearing, and whether it is opening or closing — and, crucially, whether
the balloon is **diverging from the zone it said it was heading for**. When those
disagree, the crew decides; the app does not silently re-route them on a stale
intention, and it does not hide the disagreement to look confident.

This is decision support, not automation. Three things on screen at once:

1. the road route to the intended landing zone;
2. the gap to the balloon and its trend;
3. the divergence between the two — "the balloon is 4 km north of where it is
   heading, and pulling away".

**The mini-map carries this.** A crew cannot read three numbers while moving, but
they can read one small picture showing balloon, intended zone, and their own
vehicle in relation to both. The inherited balloon/chase mini-map is already in
PLAN.md's requirements and it becomes load-bearing here rather than decorative:
it is the surface on which "we should stop trusting the landing zone" becomes
obvious.

Two notes for whoever builds it:

- The **availability model from the deleted TEC gap card is the right shape** and
  worth rebuilding for the balloon: `none` / `awaitingLocation` / `stale` /
  `tracking`, branched on explicitly so "nobody is reporting" can never render as
  a zero gap, and a stale fix can never render as a live one. The code was deleted
  in WP1 and is in git history; the model is what matters, and `CraftFixAbsence`
  in `craft_telemetry_election.dart` already starts it.
- Divergence must be measured against the **age** of the intended zone, not just
  its position. A zone set two minutes ago that the balloon is drifting from means
  something different from one set twenty-five minutes and nine kilometres ago —
  the second is stale intention rather than a balloon going off plan.

Two smaller deletions are genuinely self-contained and can land independently:
road ratings and the personal heatmap.

Migration note found in the same pass, and now done: `RideCoordinationMode.fromName`
defaulted to `secondBikeDropOff` for any unrecognised value, because that was the
only mode before the choice existed. The fallback is now `keepTogether`, not
`solo` — falling back to solo would silently strip a stored flight of its join
code and its crew. `ride_coordination_mode_test.dart` holds it shut.

#### Measured: the craft model has no creation path, so the surfaces cannot move yet

The intention was to rewrite the surfaces onto crafts inside the WP4 cut, so they
were rewritten once rather than twice. That is the right instinct and it is still
the right sequencing, but it cannot happen yet, and the reason is worth recording
because it moves work between packages.

**Nothing in production ever creates a craft.** `registerCraft`,
`attachLocalDeviceToCraft` and `nominateCraftPrimaryDevice` are called only from
`ride_controller_craft_test.dart` and `craft_roster_test.dart`. `FlightRole` is
read only by `ride_controller.dart`. Grepped after the WP4 cut landed: no file
under `lib/features/**` mentions `CraftRoster`, `CraftState` or `FlightRole` at
all.

So `resolveCraftRoster()` returns an empty roster for every real flight, and will
until something offers the pilot a way to say "this is the balloon" and a chase
crew a way to say "this is our vehicle, and we are chasing that balloon". A
surface rewritten onto crafts today would render an empty map.

That flow is not a WP4 refactor. Registering the balloon is pilot authority
(WP6); a vehicle registering itself and choosing its target is vehicle assignment
(WP7). The read model was deliberately built ahead of them — WP3's point was to
get the shape right before anything depended on it — but the surfaces have to
follow the flow, not lead it.

Revised sequencing:

1. **WP6/WP7 build craft registration**, because they own the authority rules
   that decide who may register what.
2. **The surfaces move onto crafts as part of that**, not before it. `RideRole`
   (`lead` / `rider`) keeps driving them until then.
3. **The vocabulary rename comes last**, so `rider` → `crew` happens once against
   craft-based surfaces rather than twice. This is the same argument
   `docs/backlog.md` already makes for WP3 before WP4; it extends to the
   surfaces, not just the model.

Issue #18 (craft map icons) sits with step 2 rather than step 1: keying a marker
to `CraftKind` is only meaningful once a craft exists to key it to.

**Decided for #18 when it happens:** the icon keys on `CraftKind` alone — one
balloon silhouette, one vehicle silhouette — with no sub-type field on `Craft`
and no change to the `craftRegistered` payload. The four vehicle sub-types #18
proposes would be four identical placeholders until the artwork exists, which is
an invisible and untestable distinction; per-craft tinting already carries the
"Vehicle 2 from Vehicle 3" legibility the issue asks to keep; "who has the
trailer" can live in the craft label until there is an icon for it; and adding
`vehicleType` later is an additive payload field, which this migration has done
cleanly several times. The point is not to design a journalled field around
artwork nobody has seen.

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

#### What the chase routes toward, and when to stop trusting it

Routing has a **primary destination and a divergence check**, and the second is
what makes it usable rather than merely correct.

**Primary: the pilot's intended landing area** (WP6). It is the only statement of
intent anyone has, it comes from the person who can see the wind they are
actually in, and it is a far better destination than a projection from the last
few minutes of track. So the default road target is a road-accessible point
serving that area.

**The divergence check.** An intended area is a guess made earlier, and a balloon
that has found a different wind layer will leave it. So the app continuously
compares the balloon's actual position and recent track against the area it is
supposed to be heading for, and surfaces that gap as a first-class number — the
same role the old distance-to-back-marker card played, pointed at something that
now matters. Concretely:

- Distance from the balloon to the intended area, and whether that distance is
  **opening or closing**. Closing means the plan is holding. Opening means it is
  not.
- Whether the balloon's recent track, extended, still intersects the area at all.
  A balloon eight kilometres out and tracking away from it has left the plan
  regardless of what the distance says.
- How old the intended area is, because a twenty-minute-old guess that the
  balloon has drifted out of is worse than no guess.

**When it diverges, the app hands the decision to the crew rather than making
it.** It should not silently re-target: the crew know things the app does not —
which lanes flood, which farmer is fine about it, where the trailer can turn
round. It says clearly that the plan and the balloon no longer agree, offers the
projected alternative alongside the pilot's area, and lets a crew member choose.
Voice says it once; it does not nag a driver.

#### The mini-map is the decision surface

This divergence is a *spatial* judgement and cannot be made from a distance
readout. The crew need to see, at a glance and without leaving the guidance
screen, the balloon, its recent track, the intended area, and their own vehicles
in one frame. The mini-map is therefore not decoration — it is where the decision
gets made, and it should be sized and placed accordingly, with the whole picture
in view rather than a zoomed-in road view.

For a passenger it can be interactive; for a driver it must be glanceable and
never require a touch.

Acceptance:
- [ ] The default road target serves the pilot's intended area
- [ ] Distance to the area, and whether it is opening or closing, are always visible
- [ ] A balloon tracking away from the area is called out, not just measured
- [ ] Divergence offers a choice; the app never silently re-targets
- [ ] The mini-map shows balloon, track, intended area and own vehicles together
- [ ] Nothing on the divergence path requires the driver to touch the screen

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
