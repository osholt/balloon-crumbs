# Shared landing and recovery lifecycle

Status: implemented for the private tester relay and mobile clients.

The live operation is an append-only sequence:

```text
crew room -> setting up -> released/live -> LANDED/recovery -> complete
```

`flightStartedByCrew` begins live tracking. `flightLanded` records a landing
declaration, and `flightLandingRetracted` retracts one named declaration. The
existing `rideEnded` event is the final recovery-complete transition. A LANDED
event does **not** stop location capture, relay publication or shared tracks.

## Landing evidence

Every declaration records the author device, display name, flight role, event
time and one of:

- `aboard` — reported by a device in the balloon;
- `witnessed` — seen by ground crew;
- `radioConfirmed` — confirmed over radio or another channel;
- `manuallyMarked` — a crew member selected the confirmed point on the map.

A fresh, accurate fix from an aboard role is labelled **Confirmed balloon
fix**. A manually selected coordinate is labelled **Crew-marked landing
point**. A location attached by ground crew is always **Best-known balloon
position**, even if the shared fix looked fresh locally. Missing, stale or
relayed evidence is never promoted to an exact balloon position.

Retraction names the exact `flightLanded` event it reverses. If an old offline
retraction arrives after a newer declaration, it cannot erase the newer state.
Observers cannot declare, retract or complete recovery.

## Live behaviour

- The Flight screen exposes one prominent `MARK BALLOON LANDED` action.
- The author chooses how landing was confirmed and confirms the shared action.
- Manual confirmation moves to the map for one explicit point selection.
- All clients show the LANDED evidence and location-confidence label.
- The landing evidence is shown on phone and projected maps.
- Forecast-envelope growth stops once LANDED is current.
- A chaser's balloon target resolves to the preserved landing evidence and a
  fresh lawful road route is requested; a missing landing coordinate leaves the
  previous route in place rather than inventing a destination.
- `Retract` returns clients to the live-flight state.
- `Recovery complete` is separately confirmed and is the only new recovery
  action that ends the operation and stops location publication.

## Compatibility and retention

The additive landing event types use the existing
`crew-flight-lifecycle-v1` relay capability. A client that has negotiated an
older relay refuses to publish the shared action instead of recording a
local-only success. Current relays cap both event types at 72 hours, matching
the rest of the flight-scoped journal. Older clients skip unknown event names
and continue processing the remaining batch.

## Automated evidence

- `test/domain/flight_landing_test.dart` — signed role validation, deterministic
  ordering, targeted offline retraction and observer/forgery rejection.
- `test/controllers/ride_controller_test.dart` — aboard confirmation,
  best-known radio evidence, retraction, continued sharing phase and explicit
  recovery completion.
- `test/services/chase_guidance_target_test.dart` — post-landing retargeting.
- `test/services/live_flight_projection_test.dart` — forecast envelope stops.
- `test/internet/internet_relay_worker_test.dart` and server additive-event
  tests — capability gating, relay carriage and bounded retention.
- `test/widget_test.dart` — the end-to-end LANDED/retract recovery flow.
