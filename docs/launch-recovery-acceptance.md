# Launch-to-recovery acceptance matrix

Status: automated matrix implemented; physical CarPlay evidence remains tracked
by [#15](https://github.com/osholt/balloon-crumbs/issues/15).

This matrix starts when the crew assembles, 45 minutes before release, and ends
only when recovery is complete. The checked-in fixture is generated,
deterministic and contains no real flight, precise field or contact data:
`apps/mobile/test/fixtures/launch_recovery_acceptance.json`.

## Automated matrix

| Stage or failure | Required result | Evidence |
| --- | --- | --- |
| 45-minute pre-launch lobby | Five devices remain present; a restart with the same installation identity replaces rather than duplicates the member | `apps/server/tests/test_pre_start_presence.py::test_five_devices_survive_a_45_minute_pre_launch_without_ghosts` |
| Craft assignment | Two balloon devices resolve to one balloon while three vehicles remain independent | `launch_recovery_acceptance_fixture_test.dart`, `ride_controller_craft_test.dart` |
| Release | Chase crew can start the live phase and the event records actor and flight role | `ride_controller_test.dart::chase crew can start live tracking at balloon release` |
| Live positions and tracks | Balloon and vehicle traces stay distinct; duplicate or out-of-order fixes do not rewind them | `craft_track_reducer_test.dart`, `rider_trail_recorder_test.dart`, `live_presence_two_device_test.dart` |
| Fix/wind/relay degradation | GPS loss, stale forecast wind, delayed relay and out-of-order replay degrade or freeze without inventing live state | `craft_roster_test.dart`, `live_flight_projection_test.dart`, `internet_relay_worker_test.dart` |
| Landing intent | A missing intent is valid; a revision remains separate from the calculated landing envelope | `landing_zone_test.dart`, `live_flight_projection_test.dart` |
| LANDED and retraction | Aboard, witnessed, radio-confirmed and manually marked evidence stay attributable; a later valid declaration wins | `flight_landing_test.dart`, `ride_controller_test.dart`, `widget_test.dart` |
| Recovery phase | LANDED does not end the operation; chase movement and location sharing continue until recovery complete | `fiesta_flight_simulation_test.dart`, `ride_controller_test.dart` |
| CarPlay | North-up/Direction-up and balloon/landing targets survive bridge updates and reconnect | `carplay_bridge_test.dart`, `map_orientation_preferences_test.dart`; physical checks remain below |

## Membership and authority closure

Issue #5's original “pilot starts” wording is superseded by the observed field
workflow: the pilot retains flight authority, while the pilot or either chase
role can mark balloon release and begin live tracking. Observers and balloon
crew cannot start it. The following evidence closes the remaining lifecycle
criteria without putting a pre-launch action back on the pilot:

| Criterion | Evidence |
| --- | --- |
| Five devices gather before launch without duplicate membership | `test_pre_start_presence.py::test_five_devices_survive_a_45_minute_pre_launch_without_ghosts` |
| Multiple independent chasers and role-specific viewpoints | `launch_recovery_acceptance_fixture_test.dart`, `ride_controller_craft_test.dart`, `flight_role_experience_test.dart` |
| Restart preserves operation, role, device and craft identity | `shared_preferences_session_store_test.dart`, `live_presence_two_device_test.dart::a rider who restarts the app rejoins without re-opting in`, `ride_controller_craft_test.dart::the roster survives a journal replay` |
| Only the current pilot can end the flight or transfer pilot authority | `ride_controller_test.dart::pilot handover is offered, accepted and applied on both devices`, `pilot_handover_test.dart` and the authority tests in `ride_controller_test.dart` |
| Release can be marked by the pilot or chase roles, never an observer or forged balloon role | `ride_controller_test.dart::chase crew can start live tracking at balloon release` and `balloon device cannot forge a chase role to start tracking` |
| End stops location publication and begins bounded retention | `situational_awareness_controller_test.dart::the durable journal rejects a location fix queued after flight end`, `_handleRideEnded` in `active_ride_shell.dart`, `test_sync.py::test_ride_end_shortens_retention_and_cleanup_deletes_ride` |
| Typed-code lookup is bounded and credentials are not stored in plaintext | `test_join_codes.py::test_ride_code_lookup_is_numeric_and_rate_limited`, `test_token_less_lookups_share_a_global_budget_across_callers`, and `test_register_and_resolve_six_digit_ride_code` |
| Offline/out-of-order authority changes converge | `pilot_handover_test.dart` and `ride_controller_test.dart::offline leader handover and duplicate starts converge deterministically` |

The bounded CI set is deliberately virtual-time driven. It does not sleep for
45 minutes and it never publishes synthetic positions to a live relay.

## Physical run record

Create one table per run in the field-test issue or release evidence. Do not put
join secrets, exact tracks or private land contacts in it.

| Field | Record |
| --- | --- |
| Date / tester build | |
| Phone models | |
| iOS / Android versions | |
| Vehicle / head unit | |
| Wired or wireless CarPlay | |
| Route duration and broad conditions | |
| Pre-launch lobby duration / reconnects | |
| Release actor and convergence time | |
| GPS, altitude, wind and relay degradations | |
| Landing evidence / retraction / recovery completion | |
| North-up / Direction-up and target changes | |
| Voice, Bluetooth and background behaviour | |
| Battery / thermal observations | |
| Driver-distraction or accessibility issues | |
| Failures and follow-up tickets | |

## Pass rule

- All five devices are present after the pre-launch window with no ghost craft.
- No stale or unknown fix uses the live visual state.
- LANDED keeps sharing active and recovery complete stops it deliberately.
- CarPlay never requires phone interaction from the driver during the moving
  portion and reroutes only to a lawful road rendezvous.
- Any failed physical row opens a blocking ticket; simulator success does not
  waive the physical CarPlay gate.
