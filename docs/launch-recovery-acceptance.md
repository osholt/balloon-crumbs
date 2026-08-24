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
| Multiple independent chasers and role-specific viewpoints | `launch_recovery_acceptance_fixture_test.dart`, `ride_controller_craft_test.dart`, `craft_roster_test.dart`, `role_specific_map_responsive_test.dart` |
| Restart preserves operation, role, device and craft identity | `shared_preferences_session_store_test.dart`, `live_presence_two_device_test.dart::a rider who restarts the app rejoins without re-opting in`, `ride_controller_craft_test.dart::the roster survives a journal replay` |
| Only the current pilot can end the flight or transfer pilot authority | `ride_controller_test.dart::pilot handover is offered, accepted and applied on both devices`, `pilot_handover_test.dart` and the authority tests in `ride_controller_test.dart` |
| Release can be marked by the pilot or chase roles, never an observer or forged balloon role | `ride_controller_test.dart::chase crew can start live tracking at balloon release` and `balloon device cannot forge a chase role to start tracking` |
| End stops location publication and begins bounded retention | `situational_awareness_controller_test.dart::the durable journal rejects a location fix queued after flight end`, `_handleRideEnded` in `active_ride_shell.dart`, `test_sync.py::test_ride_end_shortens_retention_and_cleanup_deletes_ride` |
| Typed-code lookup is bounded and credentials are not stored in plaintext | `test_join_codes.py::test_ride_code_lookup_is_numeric_and_rate_limited`, `test_token_less_lookups_share_a_global_budget_across_callers`, and `test_register_and_resolve_six_digit_ride_code` |
| Offline/out-of-order authority changes converge | `pilot_handover_test.dart` and `ride_controller_test.dart::offline leader handover and duplicate starts converge deterministically` |

The bounded CI set is deliberately virtual-time driven. It does not sleep for
45 minutes and it never publishes synthetic positions to a live relay.

## Role-specific viewpoint closure

Issue #7 keeps the shared operation model independent from the camera a crew
member chooses. The View control changes only local map framing between this
craft, the balloon and the whole crew; it cannot publish a role, authority or
guidance-target event. Balloon focus follows fresh craft updates, while the
whole-crew view reuses the bounded Mercator framing used by the live mini-map.

| Criterion | Evidence |
| --- | --- |
| At least three independently moving chase vehicles stay identifiable | `craft_roster_test.dart::four vehicles stay individually identifiable and addressable`; `ride_map_feature_test.dart::recovery viewpoints frame craft without treating hazards as crew` also keeps equal display labels separate by craft ID |
| Balloon, current-craft and whole-crew views switch locally | `role_specific_map_responsive_test.dart` opens the View control and selects Balloon; `recoveryMapViewpointPoints` accepts no ride controller or shared-state writer |
| Mini-map includes relevant craft with bounded framing | `group_mini_map_framing_test.dart` covers local groups, missing fixes and the 300 km outlier; `role_specific_map_responsive_test.dart` verifies every ground role retains the live overview |
| Pilot/airborne crew suppress road UI while driver prioritises it | `RecoveryMapRoleExperience` is exercised for all five roles in `role_specific_map_responsive_test.dart`; `balloon_map_presentation_test.dart` and `active_ride_navigation_escape_test.dart` cover map controls and moving pilot chrome |
| Live, relayed, stale and unknown never collapse into live | `live_presence_test.dart`, `craft_roster_test.dart`, `ride_membership_live_presence_test.dart`; freshness and source remain in each inspectable marker label |
| Small phone, landscape and large text | `role_specific_map_responsive_test.dart` renders pilot, airborne crew, chase driver, chase crew and observer at 320×568, 667×375 and 390×844 with 200% text; it also caught and closes the basemap badge overflow |

## Safe moving-rendezvous closure

The chase route ends at a provider-routed road candidate around flight
evidence, never at the raw airborne coordinate. A fresh moving fix produces a
bounded 60-second constant-motion estimate; a stationary fix produces a
surrounding search without inventing direction; a fix over 45 seconds old
cannot create a target. Four deterministic surrounding candidates are scored by
fresh provider travel time and endpoint separation. The previous endpoint is
also rescored and retained unless another saves at least 90 seconds.

| Criterion | Evidence |
| --- | --- |
| Raw balloon coordinate is never a driving endpoint | `chase_rendezvous_planner_test.dart::raw flight evidence is never submitted as a driving endpoint` |
| Mapped restrictions and unverified access stay distinct | Provider-rejected candidates are skipped in `chase_rendezvous_planner_test.dart`; route descriptions and the role dashboard say “mapped access only”; `docs/routing-provider-policy.md` records source terms and limitations |
| Missing/stale evidence freezes rather than invents | `chase_guidance_target_test.dart::stale balloon fixes cannot become a live navigation target`; the live shell retains the prior route and labels why |
| Movement, time, age and score hysteresis are explicit | `ChaseGuidanceReroutePolicy` uses 2 minutes, 300 m and a 10-minute maximum age; `ChaseRendezvousPlanner` uses a 90-second minimum score improvement |
| Replay is deterministic and failures are bounded | `chase_rendezvous_planner_test.dart` covers crossings, reversals, stationary fixes, rejected candidates, all-unreachable candidates and identical replay results |
| Provider use is within current terms | `docs/routing-provider-policy.md`; candidate calls are sequential at 1.1 seconds and identify Balloon Crumbs through `User-Agent` and `X-Client-Id` |

## Voice-first chase closure

The automated speech contract is in `docs/spoken-recovery-guidance.md`.
`chase_spoken_guidance_test.dart` proves rendezvous disclosure, priority and
deduplication under churn; the phone and CarPlay source tests prove one-action
mute-and-stop wiring. Physical Bluetooth, interruption, background and head-unit
rows remain mandatory before reliability is claimed.

## Balloon telemetry closure

Balloon Crumbs stores telemetry internally in metres and converts only at the
presentation boundary. Altitude defaults to metres independently of the road
distance locale; a separate persisted setting can select feet. The telemetry
card, wind levels, flight-plan stages, replay, map/CarPlay labels, altitude
thresholds and legend all consume that same setting.

The measured-track integrity limits are deliberately generous corruption
guards, not operating limits: 60 m/s ground speed and 12 m/s vertical speed,
with both fixes' reported accuracy added to the permitted displacement. A gap
longer than two minutes starts a new segment. Missing altitude remains a valid
position with an unknown-height segment. A rejected fix remains in the signed
offline event journal and in the reducer's rejected-evidence list, while never
becoming part of the canonical drawn trail.

| Criterion | Policy and evidence |
| --- | --- |
| Fix age, source and accuracy | Local balloon telemetry states measurement age, GNSS/barometric/unknown source, datum and available vertical accuracy; shared craft details retain position accuracy, transport source and freshness. `location_sample_altitude_test.dart`, `device_location_source_test.dart`, `balloon_map_presentation_test.dart` |
| Documented accessible scale | Fixed metric boundaries are 150/300/600/900 m; colour and progressively thicker strokes encode the same band, while unknown altitude is the thinnest grey stroke. The textual and semantic legend converts every boundary. `balloon_altitude_style_test.dart`, `route_trail_style_test.dart`, `balloon_map_presentation_test.dart` |
| Missing or invalid altitude | A missing reading carries unknown source/datum and draws a grey segment without deleting the position or inventing a height. `location_sample_altitude_test.dart`, `balloon_altitude_style_test.dart`, `craft_track_reducer_test.dart` |
| Impossible jumps | Horizontal and vertical teleports are excluded from the canonical balloon trail, retained as rejected evidence and surfaced in flight warnings. `balloon_telemetry_plausibility.dart`, `craft_track_reducer_test.dart` |
| Unit consistency | Metric is the all-locale default; feet changes altitude, accuracy, vertical rate, wind levels, plan/replay values, scale thresholds and legend together. `altitude_unit_test.dart`, `distance_unit_controller_test.dart`, `balloon_map_presentation_test.dart`, `widget_test.dart` |
| Replay/degradation matrix | The seeded simulator explicitly climbs, holds level and descends; two chasers can follow independent road geometry; link and fix-quality controls exercise internet/nearby/disconnected, inaccurate, altitude-lost and GPS-lost states. The long fixture adds duplicate/out-of-order, clock skew, stale wind, route-provider failure and unreachable candidates. `docs/simulator-replay-matrix.md`, `ride_simulation_controller_test.dart`, `fiesta_flight_simulation_test.dart`, `launch_recovery_acceptance_fixture_test.dart`, `live_presence_clock_skew_test.dart`, `chase_rendezvous_planner_test.dart` |

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
