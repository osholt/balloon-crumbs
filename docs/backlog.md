# Initial Backlog

The GitHub issues mirror this ordered backlog. Priority is a product priority,
not a claim that every P0 item is small. Work packages are defined in
[delivery-plan.md](delivery-plan.md).

| Order | Priority | Work | WP | Depends on |
|---:|:---:|---|:---:|---|
| 1 | P0 | ~~Isolate inherited TEC baseline and keep CI green~~ **done** | WP1 | — |
| 2 | P0 | Balloon-capable telemetry: altitude, source, vertical speed | WP2 | 1 |
| 3 | P0 | Craft model, flight roles, and pilot authority | WP3 | 2 |
| 4 | P0 | Delete the motorcycle domain and rename the vocabulary | WP4 | 3 |
| 4a | P0 | Replace the 15 motorcycle map markers with craft icons (#18) | WP4 | 3 |
| 5 | P0 | Altitude-coloured ground track and telemetry card | WP5 | 2, 3 |
| 6 | P0 | Pilot view, drawn landing area, and inferred landing phase | WP6 | 3, 5 |
| 7 | P0 | Multiple chase vehicles, rendezvous, and vehicle assignment | WP7 | 3, 5 |
| 7a | P0 | Route to the intended landing area, with a balloon-divergence check | WP7 | 6, 7 |
| 7b | P0 | Mini-map as the chase decision surface (balloon, track, area, vehicles) | WP7 | 7a |
| 8 | P0 | Voice-first chase guidance for a moving target | WP8 | 7 |
| 9 | P0 | Ground notes and the retrieve | WP9 | 3 |
| 10 | P0 | Landing-phase basemap (OS topographic / aerial) | WP6b | 6 |
| 11 | P0 | Balloon/chase simulator and replay matrix | WP10 | 3–9 |
| 12 | P0 | Security, privacy, retention, and field-test gates | WP12 | 3–11 |
| 13 | P1 | Carry balloon altitude through GPX export and import (#16) | WP5 | 2 |
| 14 | P1 | Retarget speed limits, camera and enforcement alerts at the chase driver | WP7 | 3 |
| 15 | P1 | Pilot aeronautical context: airspace, notices, restrictions | WP10b | 5 |
| 16 | P1 | Flight plan / notification: research the UK position, then attach or generate | WP10b | 15 |
| 17 | P1 | Evaluate and integrate weather and wind context | WP11 | 5 |
| 18 | P1 | Decide airspace, NOTAM, landing-note, and access data sources (#13) | WP11 | 5 |
| 19 | P1 | Evaluate aeronautical chart layers as flight context (#17) | WP11 | 18 |
| 20 | P1 | Restore CarPlay / Android Auto for the chase driver | — | 8 |
| 21 | P1 | Revocable observer sharing and balloon-specific exports | — | 3, 5 |
| 22 | P2 | Multiple balloons in one event, with a shared vehicle pool | — | 3, 7 |
| 23 | P2 | Dynamic chase reassignment across balloons by distance and wind | — | 22, 17 |

## Notes on ordering

**WP3 before WP4**, so the 3,889 `rider` references are renamed once into the
craft model rather than twice. **WP4 early**, because the motorcycle domain is
currently the larger half of the app and anything built on top of it costs more
to unpick later.

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
