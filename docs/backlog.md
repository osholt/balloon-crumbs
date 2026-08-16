# Initial Backlog

The GitHub issues mirror this ordered backlog. Priority is a product priority,
not a claim that every P0 item is small.

| Order | Priority | Issue | Depends on |
|---:|:---:|---|---|
| 1 | P0 | Isolate inherited TEC baseline and keep CI green | — |
| 2 | P0 | Define flight roles, pilot authority, and anonymous lifecycle | 1 |
| 3 | P0 | Implement balloon telemetry and altitude-coloured ground track | 2 |
| 4 | P0 | Support multiple chase vehicles and role-specific viewpoints | 2, 3 |
| 5 | P0 | Build safe moving rendezvous selection and road routing | 3, 4 |
| 6 | P0 | Adapt spoken guidance for moving chase targets | 5 |
| 7 | P0 | Build balloon/chase simulator and replay test matrix | 2–6 |
| 8 | P0 | Complete security, privacy, retention, and field-test gates | 2–7 |
| 9 | P1 | Evaluate and integrate weather and wind context | 3 |
| 10 | P1 | Decide airspace, NOTAM, landing-note, and access data sources | 3 |
| 11 | P1 | Add revocable observer sharing and balloon-specific exports | 2, 3 |
| 12 | P1 | Evaluate CarPlay and Android Auto chase companion | 5, 6 |
| 13 | P0 | Carry balloon altitude through GPX export and import (#16) | 3 |
| 14 | P1 | Evaluate aeronautical chart layers as flight context (#17) | 10 |

Each implementation issue must add automated acceptance tests and update the
product claim in `README.md` only after its evidence gate passes.
