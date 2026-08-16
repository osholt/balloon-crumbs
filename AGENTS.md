# Hot Pursuit — Codex Instructions

## Project overview

Hot Pursuit is an account-free, offline-first hot-air-balloon chase coordination
app for iOS and Android. It is derived from Tail End Charlie's Flutter client,
native Swift/Kotlin transport bridges, FastAPI/PostgreSQL relay, and CI.

The repository is currently a product scaffold. Treat inherited motorcycle
behaviour as candidate infrastructure, not accepted balloon functionality.

## Entry points

- `PLAN.md` — product scope, safety boundaries, acceptance criteria, and phases.
- `docs/architecture.md` — target architecture and migration boundaries.
- `docs/source-baseline.md` — exact upstream provenance and inherited state.
- `docs/backlog.md` — issue map and suggested order.
- `apps/mobile/` — inherited Flutter application and native shells.
- `apps/server/` — inherited privacy-bounded relay service.

## Narrow verification

```bash
cd apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

```bash
cd apps/server
uv sync --frozen --extra dev
uv run ruff format --check .
uv run ruff check .
uv run pytest
```

## Project rules

- Preserve the offline-first event journal and transport-neutral domain boundary.
- Keep operation membership account-free and scoped to a short code/QR invite.
- Model one balloon, a pilot/balloon device, and multiple independent chasers.
- Show fix age and `live`, `relayed`, `stale`, or `unknown`; never imply certainty.
- Road guidance must route to a safe road-accessible rendezvous, not blindly to
  the balloon coordinate, and must not encourage unlawful or off-road driving.
- Keep driver interaction voice-first and validate projected-car experiences on
  physical hardware before claiming support.
- Never present weather, wind, airspace, landing prediction, or altitude as
  authoritative unless its source, timestamp, units, and limitations are visible.
- Do not enable real domains, provider keys, signing, or deployment until each is
  explicitly selected. Current `*.invalid` values are deliberate safety guards.
- Do not commit credentials, signing assets, private flight data, or provider data
  whose licence does not allow redistribution.
