# Simulator and replay closure

Status: automated acceptance complete for issue #10. Physical-device evidence
belongs to the security/field gate in issue #11 and is not implied here.

## Safety boundary

Every simulator session is marked `isSimulation`. The production shell disables
device location, nearby transport and internet relay workers for that session;
the controller writes generated fixes only to the in-memory authenticated event
and read-model path. The screen continuously says **SYNTHETIC FLIGHT**, reports
the scenario seed, and states that no device GPS or live relay is in use.

The two connected choices below simulate delivery into that in-memory path. They
do not open a socket:

- **Internet + nearby** — all current synthetic crew fixes are delivered.
- **Nearby only** — the same bounded local delivery continues while the visible
  mode rehearses loss of internet.
- **No crew link** — local motion continues and remote fixes freeze. Selecting a
  connected mode publishes one current snapshot per participant and exercises
  normal journal convergence.

Balloon fix quality is independently controllable as precise GNSS plus altitude,
150 m inaccurate GNSS, position with altitude missing, or GPS unavailable. Loss
holds the last evidence rather than manufacturing a new location.

## Determinism contract

The default seed is `742023`. It drives stable per-vehicle traffic phases using
an integer mixer that is independent of Dart string hashes. Route samples,
motion, wind integration, altitude, telemetry quality and event order are pure
functions of the seed, scenario inputs and explicit virtual-time advances. Tests
inject a fixed clock where exact event timestamps matter.

Each chase vehicle can own a separate route sampler. Changing one route resets
only that vehicle's road progress and trace; it cannot move the balloon or a
different chase vehicle.

## Automated matrix

| Scenario | Evidence |
| --- | --- |
| Ascent, drift, level segment, descent, landing and post-landing recovery | `fiesta_flight_simulation_test.dart` |
| Forecast wind changes horizontal drift while altitude remains independently scripted | `fiesta_flight_simulation_test.dart`, `open_meteo_wind_test.dart` |
| Two or more chasers use distinct road geometry | `ride_simulation_controller_test.dart::two chase vehicles follow independent road paths` |
| Time scale and balloon/chase viewpoint are controllable | `ride_simulation_controller_test.dart`, `ride_simulation_screen_test.dart` |
| Internet, nearby-only, disconnected and reconnect states | `ride_simulation_controller_test.dart::crew links disconnect, freeze peers, and converge nearby-only` |
| Inaccurate fix, altitude loss, GPS loss and recovery | `ride_simulation_controller_test.dart::balloon fix quality covers inaccurate, altitude loss and GPS loss` |
| Duplicate, out-of-order and clock-skewed evidence does not rewind canonical state | `craft_track_reducer_test.dart`, `rider_trail_recorder_test.dart`, `live_presence_clock_skew_test.dart` |
| Stale wind, moving-target hysteresis, provider failure and unreachable candidates fail boundedly | `open_meteo_wind_test.dart`, `chase_guidance_target_test.dart`, `chase_rendezvous_planner_test.dart` |
| Same seed and inputs reproduce craft positions and speeds | `ride_simulation_controller_test.dart::the same seed and inputs reproduce every craft decision` |
| Altitude trail, target choice and freshness/read-model degradation | `craft_track_reducer_test.dart`, `chase_guidance_target_test.dart`, `craft_roster_test.dart`, `live_flight_projection_test.dart` |
| Complete long pre-launch-to-recovery fault declaration remains private and generated | `launch_recovery_acceptance_fixture_test.dart` |
| No synthetic coordinates reach external transport | simulation construction in `active_ride_shell.dart`; source contract in `ride_simulation_controller.dart` |

Mobile CI runs the complete bounded Flutter suite under a 15-minute job timeout,
then requires both Android and unsigned iOS builds. Therefore every matrix row
above is a pull-request and main-branch gate rather than an optional local test.
