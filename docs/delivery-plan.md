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
| Speed-camera / enforcement alerts | 183 | 15 | delete |
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

**Introduce a craft.** One flight has exactly one balloon and zero or more
vehicles. Devices attach to a craft; a craft has one position, contributed by
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
2. **Speed-camera and enforcement alerting** (183 hits). Road-riding feature,
   legally sensitive, irrelevant to a chase crew and actively wrong to show a
   pilot.
3. **Rejoin routing** (466 hits). Routes a separated rider back onto a shared
   GPX route. A chase vehicle is never "off route" — it is on a road network
   heading for a moving target. Replaced wholesale by rendezvous selection.
4. **Road ratings** and **personal heatmap**. Scoring roads for fun.
5. **Motorcycle iconography** — `motorcycle_icon.dart`, rider symbols, bike
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
- [ ] No `marker`, `enforcement`, `rejoin`, `road rating` or `heatmap` code remains
- [ ] No user-facing string says rider, bike or ride
- [ ] Test count drops honestly — deleted features lose their tests, nothing else does

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

### WP6 — The pilot view

Deliberately austere. Big type, few controls, works with gloves.

- Height, climb rate, and "the crew can see you" / "nobody has your position".
- Intended landing area, set with one gesture, relayed to every vehicle.
- Start/end sharing, and a privacy stop.
- No routing, no hazards, no chase detail — the pilot is flying.

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

### WP11 — Context: weather, wind, airspace

Blocked on provider licensing (issues #13, #17) and should stay blocked until it
is resolved. Wind at altitude is the single most valuable addition for a chase
crew — it is what makes prediction credible — which is exactly why the licence
question deserves a real answer rather than a quick integration.

### WP12 — Release evidence

Security and privacy review, per-device authority replacing the inherited group
HMAC, retention, battery and background testing, accessibility of the altitude
representation without colour, mixed-device field matrix.

## Decisions I need from you

1. **Speed-limit display** — delete with the rest of the road-riding features, or
   keep it for the chase driver? It is genuinely useful to a driver and not
   motorcycle-specific. My recommendation: keep the display, delete the camera
   alerting.
2. **CarPlay / Android Auto** — currently inert and unentitled. A chase driver is
   the ideal CarPlay user, so this may be worth more here than it was for riding.
   Revisit after WP8, not before.
3. **Multiple balloons** — one club event, several balloons, shared crews. The
   craft model in WP3 makes this cheap later, but designing for it now costs
   time. Recommendation: build one-balloon, keep the model open.
4. **Intended landing area** — how much should a pilot be able to say, and how
   strongly should the app present it? It is a guess by a person who is flying,
   and the crew will treat it as fact.

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
