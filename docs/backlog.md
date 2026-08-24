# Initial Backlog

Field evidence from 23 August 2026 is planned in
[field operations and recovery coordination](field-operations-recovery-plan.md).
Its recovery-first P0 order supersedes the earlier pilot/planner ordering below;
the existing work packages remain useful implementation dependencies.

The next coordinated implementation is specified in
[role-specific live flight experience](role-specific-live-flight-experience.md).
Its slices supersede implementing WP3/WP5/WP6/WP7/WP10b/WP11 independently:
role and craft assignment, route-state separation and role-specific shells are
prerequisites for bringing planner evidence into the live app safely.

The GitHub issues mirror this ordered backlog. Priority is a product priority,
not a claim that every P0 item is small. Work packages are defined in
[delivery-plan.md](delivery-plan.md).

| Order | Priority | Work | WP | Depends on |
|---:|:---:|---|:---:|---|
| 1 | P0 | ~~Isolate inherited TEC baseline and keep CI green~~ **done** | WP1 | — |
| 2 | P0 | ~~Balloon-capable telemetry: altitude, source, datum, accuracy, vertical speed~~ **done** | WP2 | 1 |
| 3 | P0 | ~~Craft model, flight roles, and pilot authority~~ **done** | WP3 | 2 |
| 4 | P0 | ~~Delete the motorcycle domain and replace user-facing ride/rider copy~~ **done**; compatibility identifiers remain until after 6, 7 | WP4 | 3 |
| 4a | P0 | ~~Replace the 15 motorcycle map markers with craft icons (#18)~~ **done** | WP4 | 6, 7 |
| 5 | P0 | ~~Altitude-coloured ground track and telemetry card~~ **done** | WP5 | 2, 3 |
| 6 | P0 | Pilot view, drawn landing area, and inferred landing phase | WP6 | 3, 5 |
| 7 | P0 | ~~Multiple chase vehicles and vehicle assignment~~ **done**; rendezvous remains in 7a | WP7 | 3, 5 |
| 7a | P0 | ~~Chaser-selectable road guidance to the balloon or intended landing area, with bounded road-candidate selection, access uncertainty and reroute hysteresis~~ **done** | WP7 | 6, 7 |
| 7b | P0 | ~~Mini-map and local viewpoint switching as the chase decision surface (balloon, track, area, vehicles)~~ **done** | WP7 | 7a |
| 8 | P0 | Voice-first chase guidance for a moving target | WP8 | 7 |
| 9 | P0 | Ground notes and the retrieve | WP9 | 3 |
| 10 | P0 | Landing-phase basemap (OS topographic / aerial) | WP6b | 6 |
| 11 | P0 | Balloon/chase simulator and replay matrix | WP10 | 3–9 |
| 11a | P0 | Full-flight archive v2: time-align balloon telemetry, available chaser/craft locations, wind observations and guidance target changes; replay any previous flight, not only the bundled Fiesta scenario | WP10 | 5–9 |
| 12 | P0 | Security, privacy, retention, and field-test gates | WP12 | 3–11 |
| 12a | P0 | Multiple operational boundaries and altitude bands: draw, name, share and update more than one line/area in the web planner or app; alert on crossing with source, age and hysteresis; support configurable high/low altitude alerts | WP10b | 5, 6, 12 |
| 13 | P1 | ~~Carry balloon altitude through GPX export and import (#16)~~ **done** | WP5 | 2 |
| 14 | P1 | Retarget posted speed limits at the chase driver; remove inherited camera/enforcement alerts | WP7 | 3 |
| 15 | P1 | Pilot aeronautical context: airspace, notices, restrictions | WP10b | 5 |
| 16 | P1 | Flight plan / notification: research the UK position, then attach or generate | WP10b | 15 |
| 17 | P1 | Evaluate and integrate weather and wind context | WP11 | 5 |
| 18 | P1 | Decide airspace, NOTAM, landing-note, and access data sources (#13) | WP11 | 5 |
| 19 | P1 | Evaluate aeronautical chart layers as flight context (#17) | WP11 | 18 |
| 20 | P1 | Restore CarPlay / Android Auto for the chase driver | — | 8 |
| 21 | P1 | Revocable observer sharing and balloon-specific exports | — | 3, 5 |
| 22 | P2 | Multiple balloons in one event, with a shared vehicle pool | — | 3, 7 |
| 23 | P2 | Dynamic chase reassignment across balloons by distance and wind | — | 22, 17 |
| 24 | P1 | Saved launch/landing-area catalogue and time-by-altitude weather scan informed by the Ballooning Maps review | WP11 | 17, 18 |

## Notes on ordering

**WP3 before WP4**, so the 3,889 `rider` references are renamed once into the
craft model rather than twice. **WP4 early**, because the motorcycle domain is
currently the larger half of the app and anything built on top of it costs more
to unpick later.

**The craft and vocabulary dependency is now landed.** WP6/WP7 create and attach
crafts in production; live surfaces project one marker per craft; and #18 stores
the selected silhouette on `Craft`, keyed to `CraftKind`. Canonical
`craftStyle` payloads retain an additive legacy-key bridge for installed tester
builds. The completed reasoning and compatibility boundary are recorded in
`delivery-plan.md`.

**Items 22 and 23 are deliberately last but constrain item 3 now.** Multiple
balloons with a shared vehicle pool, where a vehicle switches target mid-flight
based on distance and wind, is a different product. It is not being built. But
the craft model in WP3 is being written so it does not have to be re-cut later:
crafts are a set rather than a balloon slot, a vehicle's chase assignment is its
own journalled fact, and guidance takes a target craft as a parameter. See
"Designed-for, not built-yet" in the delivery plan.

**Items 15 and 16 begin as research, not code.** The regulatory position for UK
balloon flight plans and notifications needs confirming with the CAA and the BBAC
before anything is built, and generating a flight plan a pilot then relies on is
a safety claim rather than a feature.

Each implementation issue must add automated acceptance tests and update the
product claim in `README.md` only after its evidence gate passes.
