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
| 5 | P0 | Altitude-coloured ground track and telemetry card | WP5 | 2, 3 |
| 6 | P0 | The pilot view | WP6 | 3, 5 |
| 7 | P0 | Multiple chase vehicles, rendezvous, and vehicle assignment | WP7 | 3, 5 |
| 8 | P0 | Voice-first chase guidance for a moving target | WP8 | 7 |
| 9 | P0 | Ground notes and the retrieve | WP9 | 3 |
| 10 | P0 | Balloon/chase simulator and replay matrix | WP10 | 3–9 |
| 11 | P0 | Security, privacy, retention, and field-test gates | WP12 | 3–10 |
| 12 | P1 | Carry balloon altitude through GPX export and import (#16) | WP5 | 2 |
| 13 | P1 | Evaluate and integrate weather and wind context | WP11 | 5 |
| 14 | P1 | Decide airspace, NOTAM, landing-note, and access data sources (#13) | WP11 | 5 |
| 15 | P1 | Evaluate aeronautical chart layers as flight context (#17) | WP11 | 14 |
| 16 | P1 | Revocable observer sharing and balloon-specific exports | — | 3, 5 |
| 17 | P1 | Re-evaluate CarPlay and Android Auto for the chase driver | — | 8 |

The two ordering choices worth stating: **WP3 before WP4**, so the vocabulary is
renamed once into the craft model rather than twice; and **WP4 early**, because
the motorcycle domain is currently the larger half of the app and every package
built on top of it costs more to unpick later.

Each implementation issue must add automated acceptance tests and update the
product claim in `README.md` only after its evidence gate passes.
