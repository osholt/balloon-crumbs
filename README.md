# Balloon Crumbs

**Working title:** Balloon Crumbs
**Status:** product scaffold; inherited functionality is not yet field-ready for balloon operations

Balloon Crumbs is an account-free coordination app for hot-air-balloon pilots,
crew, and multiple chase vehicles. A pilot starts a flight, shares a six-digit
code, and the participating phones exchange live position and flight state. The
chase view is designed to show the balloon's coloured altitude trail, current
heading and speed, weather context, chase-vehicle positions, and safe voice
guidance over the road network.

The repository is derived from Tail End Charlie's offline-first Flutter and
FastAPI architecture. Its event journal, six-digit sessions, nearby/internet
relay, location capture, mapping, GPX, voice guidance, observer sharing,
simulation, diagnostics, and CI are retained as an implementation baseline.
Motorcycle concepts still present below the new product surface are migration
work, not balloon features.

> [!WARNING]
> This is not an aviation, navigation, landing-site, or driver-safety product.
> Do not use it for operational balloon chasing until the balloon-domain work,
> privacy/security review, provider licensing, and physical field-test gates in
> [PLAN.md](PLAN.md) are complete.

## Product direction

- No account: create or join a temporary operation using a six-digit code or QR.
- One balloon, one pilot view, and one or more chase vehicles/crew views.
- Live balloon and vehicle positions with honest live/relayed/stale/unknown state.
- Balloon ground track coloured by altitude, with speed, heading, climb/descent,
  fix age, and data source.
- Dynamic chase guidance that uses legal roads and safe rendezvous/intercept
  points, with voice-first instructions and explicit recalculation state.
- Role-specific map framing, including a balloon/chase mini-map and quick
  switching between participant viewpoints.
- Offline-first state, bounded retention, diagnostics, and a flight simulator.
- Weather and wind context, with aviation/airspace and landing information only
  from licensed and attributable providers.

See [PLAN.md](PLAN.md), [docs/architecture.md](docs/architecture.md), and
[docs/backlog.md](docs/backlog.md).

## Repository layout

```text
apps/mobile/                 Flutter client plus Swift/Kotlin platform bridges
apps/server/                 FastAPI/PostgreSQL relay inherited from TEC
apps/website/                Safe placeholder for the future public site
deploy/                      Deployment templates; no production credentials
docs/                        Product, architecture, source, and backlog notes
.github/workflows/           Mobile and server CI only
```

## Local verification

The inherited internal Dart/Python names remain `ride_relay` for now.

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

All copied network and associated-domain defaults use `*.invalid`. A real
domain, map provider, weather provider, and app-store identifiers are separate
release decisions.

## Licence and attribution

This derivative retains the PolyForm Noncommercial License 1.0.0. See
[LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
