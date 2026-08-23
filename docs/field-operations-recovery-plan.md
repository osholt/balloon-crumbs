# Field operations and recovery coordination

Status: **Accepted — field evidence supersedes earlier product prioritisation**

Date: 23 August 2026

Evidence: one complete UK balloon setup, launch, chase, landing and recovery
observed with the current tester build.

## Problem statement

The useful job for Balloon Crumbs is not predicting where a pilot intends to
fly. In a real launch the destination is unknown, the pilot is occupied, and the
phone is primarily a shared moving picture for the recovery team. The product
must therefore optimise the pre-launch crew room, live balloon/vehicle
coordination, in-car guidance, landing confirmation and final land access.

The planner remains useful for learning and forecast exploration, but a flight
must work completely without a plan. Aviation chart context must not displace
the road and field detail the recovery crew needs.

## Goals

1. A regular crew can reopen its familiar private crew room and have every
   device ready before balloon setup begins.
2. A chase participant, not the busy pilot, can mark the release and begin the
   shared live phase.
3. CarPlay provides a glanceable two-dimensional team map and continuously
   recalculated lawful road guidance towards either the balloon or its current
   landing intent.
4. Every device sees the balloon's measured direction, speed, track, freshness
   and a clearly labelled forecast landing envelope, plus all shared vehicle
   positions and tracks.
5. The team can publish a distinct **LANDED** state and an honest best-known
   recovery location without prematurely ending tracking.
6. Crews can retain useful private land-access knowledge without creating an
   ungoverned public directory of landowners' personal information.

## Non-goals

- The live app is not a certified aviation chart, briefing or flight-control
  tool. Airspace may remain as optional planner context, not a default live
  layer.
- A forecast landing envelope is not a promise of where the balloon will land
  or that access is safe or permitted.
- A reusable human code is not itself a permanent bearer secret. Knowing a
  guessable word such as `TUCKER` must not silently grant access to future
  flights.
- The first land-access release will not publish landowner contacts to all app
  users, rank individuals, or claim that a polygon proves ownership.
- A ground declaration of landing will not invent an exact balloon coordinate
  when the declaring device has only a stale or relayed position.

## Primary user stories

- As a regular crew member, I can reopen `TUCKER` and see who is ready without
  exposing a new flight to somebody who merely guesses that word.
- As chase crew, I can mark balloon release once the basket is airborne so the
  pilot is not responsible for starting the recovery system.
- As a chase driver, I can use CarPlay to see the whole team and receive lawful
  live road guidance without handling the phone.
- As balloon or ground crew, I can declare and, if necessary, retract LANDED
  while all devices continue sharing through recovery.
- As recovery crew, I can record a field access note for my private crew and
  distinguish a remembered contact from authoritative ownership data.
- As a person named in an access note, I can have my contact details corrected
  or removed without needing a Balloon Crumbs account.

## Product decisions

### 1. Coordination is core; planning is optional

- The home hierarchy leads with **Open crew room**, **Join crew**, and the last
  active recovery. **Planner** remains available under planning/tools.
- Creating or joining a live flight never requires a forecast route, intended
  landing area, altitude plan, wind model or airspace layer.
- Planner imports remain preserved as optional context and must never overwrite
  a vehicle's local road route.

### 2. Reusable crew rooms, fresh flight operations

The user-facing reusable value is a **crew code**, not a never-ending flight.

- A coordinator chooses a normalised 5–12 character alias such as `TUCKER`.
- The alias identifies a persistent crew room and can be reused across days.
- Each launch creates a fresh operation ID, event journal, retention window and
  invite capability beneath that crew room. Old tracks never appear in a new
  launch by code reuse alone.
- Returning devices keep a private crew-room credential locally and can rejoin
  quickly. A first-time device needs a QR/private link or an explicit approval
  from a present trusted device; the memorable alias alone is insufficient.
- Alias lookup is rate-limited, does not reveal crew membership, and supports
  revocation, transfer and deletion without accounts.
- If the relay is unavailable, a QR/private link can still bootstrap nearby
  membership using the existing offline invitation path.

### 3. The crew assembles before setup

The pre-launch surface is a persistent lobby, not a temporary modal.

- It groups people by Balloon and each chase vehicle, with role, device
  freshness and readiness.
- It stays useful for tens of minutes while the balloon is prepared.
- Late joining is allowed, but the start confirmation names missing/stale
  expected devices rather than silently pretending the crew is complete.
- A person can correct their craft or role before release without recreating the
  room.

### 4. Ground crew controls release; landing is a separate phase

Lifecycle:

```text
crew room -> setting up -> released/live -> landed/recovery -> complete
```

- Chase driver and chase crew devices may publish **Balloon released / Start
  tracking**. The pilot retains a secondary recovery action but is never the
  person the primary flow waits for.
- The event records who acted, their flight role and the confirmation time.
- Pilot, balloon crew, chase driver and chase crew may declare **LANDED**.
- A declaration states its evidence: device in balloon, witnessed, radio
  confirmation, or manually marked location.
- A fresh balloon-device fix can become the confirmed landing point. A ground
  declaration using a relayed fix keeps its age/source and is labelled
  best-known until confirmed or manually corrected.
- LANDED stops route prediction growth, alerts the team and retargets recovery
  guidance, but location sharing continues until **Recovery complete**.
- A mistaken landing declaration can be retracted with an attributable event.

### 5. Live recovery map

Default live layers:

- road basemap;
- balloon marker with ground-track arrow, speed, altitude and fix age;
- altitude-coloured measured balloon track;
- each vehicle's position, direction, freshness and complete shared track;
- intended landing point when one has been published;
- forecast possible-landing envelope computed from the latest usable balloon
  fix, altitude and timestamped Open-Meteo wind inputs;
- each chaser's own lawful road route and selected target.

The user can lock the camera **North up** or **Direction up**. That preference
persists independently on phone and CarPlay. Aeronautical tiles are removed from
the default live hierarchy. A detailed Ordnance Survey layer is an optional
final-approach basemap after its API key, attribution, offline behaviour and
licence are implemented behind the existing map-provider boundary.

### 6. CarPlay is a P0 chase surface

- CarPlay shows one 2D recovery map containing the local vehicle, balloon,
  recent balloon/vehicle traces, other chase vehicles, landing intent/envelope
  and the current road route.
- Guidance continuously recalculates to the selected safe road rendezvous near
  the balloon or to the currently published landing area.
- North-up and direction-up are available as one-tap map buttons.
- Touch interactions while moving remain bounded by CarPlay templates;
  retargeting is voice-first or performed by chase crew on a phone.
- The existing native CarPlay implementation must be stripped of inherited
  ride/rider/speed-camera hierarchy that is not part of recovery.
- Shipping requires Apple's `com.apple.developer.carplay-maps` entitlement, a
  matching provisioning profile, App Store review compliance and validation in
  a physical vehicle. Simulator evidence alone is insufficient.

### 7. Privacy-first land access knowledge

The minimum useful record is a crew-private **access note**:

- user-drawn polygon or point;
- first name or role, optional phone number;
- access/gate notes;
- neutral outcome such as `permission granted`, `ask again`, `declined`, or
  `unknown` rather than a public reputation score;
- date confirmed, who recorded it, provenance and expiry/review date;
- explicit owner/contact consent status when personal details were provided.

V1 is device-local with encrypted export/import for a deliberate crew. Relay
sync or club sharing is blocked until the controller, lawful basis, privacy
notice, access controls, audit trail, retention, correction, erasure and abuse
reporting are designed and tested. The subject must have a practical removal
route even if they do not use the app.

HM Land Registry INSPIRE Index Polygons may provide an optional boundary
reference in England and Wales. They show the indicative extent of a subset of
registered freehold titles and an ID; they do not provide the owner's name or
contact details and must not be presented as proof of ownership. User-supplied
contacts remain a separate private overlay.

## Priority and phases

### P0 — next field-test loop

1. Crew-led start, shared LANDED/retract state and recovery-complete lifecycle.
2. Reusable crew-room alias and returning-device credentials.
3. Road-first live map with shared full tracks, balloon direction/speed,
   forecast landing envelope and North-up/Direction-up camera modes.
4. Recovery-specific CarPlay map, dynamic target selection and physical-car
   evidence.
5. Simulator and relay fixtures for long pre-launch waits, release, stale fixes,
   radio-confirmed landing and reconnect.

### P1 — field approach and access

1. Optional OS OpenData/Premium basemap behind a bounded relay proxy.
2. Device-local land-access notes, encrypted backup and deletion tools.
3. Optional INSPIRE polygon reference with source, update date and limitations.
4. Planner moved out of the primary live-flight hierarchy while remaining
   maintained and linkable.

### P2 — only after privacy evidence

- opt-in crew/club land-access sharing;
- contact-subject correction and removal portal;
- moderated provenance/conflict handling;
- Android Auto recovery surface after the CarPlay field loop is proven.

## Acceptance metrics

- All expected devices can remain visible in a pre-launch room for 45 minutes
  and reconnect without creating duplicate craft or people.
- A returning crew opens its room in under 30 seconds; a new member joins by QR
  in under 60 seconds.
- A chase device can start the live phase within 15 seconds of balloon release,
  and all connected devices converge on the start within 10 seconds.
- A LANDED declaration reaches connected chasers within 10 seconds and never
  ends sharing automatically.
- During a 60-minute replay, every shared track retains its full bounded history
  and no stale fix is labelled live.
- Phone and CarPlay camera mode survives reconnect and relaunch.
- CarPlay completes a physical launch-to-recovery field test without requiring
  unsafe phone interaction from the driver.
- No land-contact record can be relayed or exported without an explicit action;
  all exported records retain provenance, confirmation date and deletion data.

## Provider and governance evidence

- [Apple CarPlay entitlement documentation](https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements)
  requires category approval, the navigation entitlement and matching signing
  configuration.
- [OS Maps API](https://docs.os.uk/os-apis/accessing-os-apis/os-maps-api) provides
  road/outdoor/light/leisure raster styles. [OS Data Hub plans](https://osdatahub.os.uk/plans/)
  distinguish unlimited OpenData from premium data and its current credit and
  usage terms.
- [HM Land Registry INSPIRE guidance](https://www.gov.uk/guidance/inspire-index-polygons-spatial-data)
  describes indicative registered-property polygons, not owner contacts.
- [ICO lawful-basis guidance](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/lawful-basis/a-guide-to-lawful-basis/)
  and [right-to-erasure guidance](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/individual-rights/individual-rights/right-to-erasure/)
  define the governance gate before shared personal land-contact data.

## Ticket map

- [#70 — field-feedback recovery-coordination epic](https://github.com/osholt/balloon-crumbs/issues/70)
- [#71 — reusable named crew rooms](https://github.com/osholt/balloon-crumbs/issues/71)
- [#72 — chase-led start and shared LANDED state](https://github.com/osholt/balloon-crumbs/issues/72)
- [#73 — road-first shared recovery map](https://github.com/osholt/balloon-crumbs/issues/73)
- [#15 — recovery-specific CarPlay chase map](https://github.com/osholt/balloon-crumbs/issues/15)
- [#74 — long pre-launch and recovery acceptance matrix](https://github.com/osholt/balloon-crumbs/issues/74)
- [#75 — optional OS final-approach basemap](https://github.com/osholt/balloon-crumbs/issues/75)
- [#76 — device-local privacy-governed land access notes](https://github.com/osholt/balloon-crumbs/issues/76)

## Delivery evidence

- Shared release, LANDED, retraction and recovery-complete semantics are
  documented in [recovery lifecycle](recovery-lifecycle.md).
- [#77 — HMLR INSPIRE boundary reference](https://github.com/osholt/balloon-crumbs/issues/77)
- [#17 — optional planner-only aeronautical context](https://github.com/osholt/balloon-crumbs/issues/17)
