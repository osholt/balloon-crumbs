# Tail End Charlie post-fork audit

Audit point: Balloon Crumbs baseline `5a90c59d` through Tail End Charlie `725dbee8`
(22 August 2026). Every merged TEC pull request reachable after the baseline is
listed below. “Port” means domain-neutral code worth adapting; it does not mean
copying motorcycle behaviour or claims. Projected-car changes remain gated on
physical hardware validation.

| TEC PR | Associated issue(s) | Assessment | Balloon Crumbs action |
|---:|---:|---|---|
| [#651](https://github.com/osholt/tailendcharlie/pull/651) | #650 | Complete archive tracks do not fit tiny library previews | **Ported** with responsive camera padding and tests |
| [#649](https://github.com/osholt/tailendcharlie/pull/649) | — | Android Auto navigation-surface permission | Port with #603/#646 only at the physical-hardware gate |
| [#648](https://github.com/osholt/tailendcharlie/pull/648) | — | Tester notes only | Reference; no code |
| [#647](https://github.com/osholt/tailendcharlie/pull/647) | — | Motorcycle heatmap contribution | Do not port; not a balloon chase primitive |
| [#646](https://github.com/osholt/tailendcharlie/pull/646) | — | Android Auto discovery descriptor | Port with #603/#649 only at the physical-hardware gate |
| [#645](https://github.com/osholt/tailendcharlie/pull/645) | — | Circular motorcycle-route direction | Do not port |
| [#643](https://github.com/osholt/tailendcharlie/pull/643) | #642 | Circular-route constrained crossings | Do not port |
| [#641](https://github.com/osholt/tailendcharlie/pull/641) | #640 | Circular-route timeout recovery | Do not port |
| [#639](https://github.com/osholt/tailendcharlie/pull/639) | — | Circular-route costing/review | Do not port |
| [#638](https://github.com/osholt/tailendcharlie/pull/638) | — | TEC deployment proxy to Balloon Crumbs relay | TEC infrastructure only; no reverse port |
| [#637](https://github.com/osholt/tailendcharlie/pull/637) | — | Circular-route motorway fallback | Do not port |
| [#635](https://github.com/osholt/tailendcharlie/pull/635) | — | Circular-route no-path copy | Do not port |
| [#634](https://github.com/osholt/tailendcharlie/pull/634) | — | Navigation controls in both orientations | Port after balloon map overlays stabilise |
| [#633](https://github.com/osholt/tailendcharlie/pull/633) | — | Map and road-guidance refinement | Split: port generic camera/guidance fixes; reject motorcycle-only UI |
| [#632](https://github.com/osholt/tailendcharlie/pull/632) | #631 | Tester email presentation | No configured Balloon Crumbs mail workflow |
| [#629](https://github.com/osholt/tailendcharlie/pull/629) | — | Tester notes only | Reference; no code |
| [#628](https://github.com/osholt/tailendcharlie/pull/628) | — | Stop free-roam road navigation | Port when personal chase-target guidance lands |
| [#627](https://github.com/osholt/tailendcharlie/pull/627) | #619 | Landscape safety-cluster anchoring | Port after balloon map overlays stabilise |
| [#618](https://github.com/osholt/tailendcharlie/pull/618) | #614 | Read roundabouts from road geometry | Port as a self-contained road-guidance change |
| [#617](https://github.com/osholt/tailendcharlie/pull/617) | — | British-side route framing | Port as a self-contained camera test |
| [#612](https://github.com/osholt/tailendcharlie/pull/612) | #605 | Home must reopen an active operation, not offer a second | **Adapted**: running flights can be set aside/reopened and block a second flight |
| [#611](https://github.com/osholt/tailendcharlie/pull/611) | #607 | Screen-awake scope | Port only with battery and driver-interaction acceptance testing |
| [#610](https://github.com/osholt/tailendcharlie/pull/610) | #608 | Follow camera accounts for bottom band | Port after balloon setup panel layout settles |
| [#609](https://github.com/osholt/tailendcharlie/pull/609) | — | Overflow button order | Inspect after terminology and action-surface rewrite |
| [#604](https://github.com/osholt/tailendcharlie/pull/604) | — | Tester email naming | No configured Balloon Crumbs mail workflow |
| [#603](https://github.com/osholt/tailendcharlie/pull/603) | #602 | Android Auto map, turn card and engine | Port only at physical-hardware gate; do not claim support before it passes |
| [#601](https://github.com/osholt/tailendcharlie/pull/601) | #600 | Motorcycle free roam | Do not port; chase guidance has explicit balloon/landing targets |
| [#599](https://github.com/osholt/tailendcharlie/pull/599) | — | Tester notes only | Reference; no code |
| [#597](https://github.com/osholt/tailendcharlie/pull/597) | #592–#596, #598 | Restore/set-aside/start-screen fixes | **Adapted** recovered-flight choice and running-flight set-aside; remaining visual fixes stay in the map queue |
| [#591](https://github.com/osholt/tailendcharlie/pull/591) | — | Tester notes only | Reference; no code |
| [#590](https://github.com/osholt/tailendcharlie/pull/590) | #579 | Leave pre-start; one destination entry | Port the state fix; destination UX is superseded by map-first landing setup |
| [#589](https://github.com/osholt/tailendcharlie/pull/589) | #578 | Motorcycle discovery layers | Do not port |
| [#588](https://github.com/osholt/tailendcharlie/pull/588) | #575 | Valhalla-match imported tracks | Port after route-import regression suite |
| [#587](https://github.com/osholt/tailendcharlie/pull/587) | — | Tester notes only | Reference; no code |
| [#586](https://github.com/osholt/tailendcharlie/pull/586) | #580 | Claim generic GPX types on iOS | **Ported** with generic-data and XML MIME declarations |
| [#585](https://github.com/osholt/tailendcharlie/pull/585) | #577 | Free-roam position reacquisition | Re-test against chase foreground location before porting |
| [#584](https://github.com/osholt/tailendcharlie/pull/584) | #574 | Garmin leg geometry is not thousands of waypoints | **Ported** parser fix and regression expectation |
| [#583](https://github.com/osholt/tailendcharlie/pull/583) | #572, #573 | Free-roam top-band ownership | Superseded by balloon setup and chase telemetry surfaces |
| [#582](https://github.com/osholt/tailendcharlie/pull/582) | #576 | Build a motorcycle free-roam route | Do not port |
| [#571](https://github.com/osholt/tailendcharlie/pull/571) | #547 | Editable circular rides on web | Do not port |
| [#570](https://github.com/osholt/tailendcharlie/pull/570) | #550 | Heatmap route bias | Do not port |
| [#569](https://github.com/osholt/tailendcharlie/pull/569) | #495 | Global heatmap in web planner | Do not port |
| [#568](https://github.com/osholt/tailendcharlie/pull/568) | #494 | Global motorcycle heatmap on mobile | Do not port |
| [#567](https://github.com/osholt/tailendcharlie/pull/567) | #542 | Auto-save/recover interrupted operations | Retain recovery model; completed-flight v2 must include balloon/wind data |
| [#566](https://github.com/osholt/tailendcharlie/pull/566) | #553 | Save imported web plans before starting | Port into the Flight Library flow |
| [#565](https://github.com/osholt/tailendcharlie/pull/565) | #546 | Preserve selected destination route at creation | Port with intended-area/road-rendezvous handoff tests |
| [#564](https://github.com/osholt/tailendcharlie/pull/564) | #544 | Alerts inside rounded screens | Port when chase-driver alert layout is final |
| [#563](https://github.com/osholt/tailendcharlie/pull/563) | #549 | Mobile circular ride planning | Do not port |
| [#562](https://github.com/osholt/tailendcharlie/pull/562) | #551 | Free-roam POI layers | Do not port |
| [#561](https://github.com/osholt/tailendcharlie/pull/561) | #548 | Motorcycle fuel/comfort/meal stops | Do not port |
| [#560](https://github.com/osholt/tailendcharlie/pull/560) | #552 | Circular route generator | Do not port |
| [#559](https://github.com/osholt/tailendcharlie/pull/559) | #492 | Private motorcycle heatmap | Do not port |
| [#558](https://github.com/osholt/tailendcharlie/pull/558) | #545 | Keep alerts on selected natural voice | **Ported** warmed-voice deadline and regression test |
| [#557](https://github.com/osholt/tailendcharlie/pull/557) | #543 | Fit complete route in review | Port beside #651 |
| [#556](https://github.com/osholt/tailendcharlie/pull/556) | #490 | Unified Ride Library | Adapt naming and archive schema into Flight Library |
| [#555](https://github.com/osholt/tailendcharlie/pull/555) | #541 | Transferable library backups | Reassess privacy after flight archive v2 defines chaser/craft retention |
| [#554](https://github.com/osholt/tailendcharlie/pull/554) | #493 | Relay motorcycle heatmaps | Do not port |

## Port rule

Each remaining “Port” item is a separate, reviewable change with its upstream
commit recorded in the commit message. A bulk merge is unsafe: the post-fork
range also deletes and rewrites balloon-specific code, touches 100+ files and
introduces motorcycle heatmaps, circular-route planning and release claims that
are outside Balloon Crumbs. The applicable fixes are therefore adapted through
balloon-domain acceptance tests rather than merged wholesale.
