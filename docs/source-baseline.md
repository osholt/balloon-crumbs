# Source baseline and migration inventory

Balloon Crumbs was scaffolded from `osholt/tailendcharlie` commit
`5a90c59da54416a5fb8da67cf45960691543d5b7` on 15 August 2026. Git history,
build caches, local credentials, signing assets, marketing material, production
deployment workflows and Tail End Charlie production configuration were not
copied.

This inventory is the checked-in boundary between reusable infrastructure and
the Balloon Crumbs product. `Keep` means the behaviour is domain-neutral;
`adapt` means the implementation remains but its product contract is for balloon
recovery; `replace` means the inherited surface or model has been superseded;
and `remove` means it must not be reachable or shipped.

| Inherited area | Decision | Balloon Crumbs boundary |
| --- | --- | --- |
| Append-only event journal, replay and SQLite queue | Keep | Transport-neutral offline-first state; flight events and compatibility decoding are tested. |
| Anonymous short-code/QR membership | Adapt | Reusable crew-chosen flight codes, explicit craft and flight roles, pre-start presence and bounded membership. |
| Nearby and HTTPS relay transports | Adapt | Balloon Crumbs protocol, retention, rate limits and selected relay host; no inherited production endpoint or credential. |
| Location sampling, freshness and participant trails | Adapt | One balloon plus independent chase craft; `live`, `relayed`, `stale` and `unknown` remain explicit. |
| Map, offline regions and route geometry | Adapt | Road recovery maps, optional licensed final-approach detail, balloon/chaser shared tracks and role-specific framing. |
| GPX import, route recording and library | Adapt | Forecast flight plans and chase road routes; imported balloon forecasts never generate turn directions. |
| Road routing, speed limits and spoken guidance | Adapt | Lawful car routing and posted-limit display are chase-driver only; routing never directs a vehicle off-road to a balloon coordinate. |
| Car projection bridge | Replace | Balloon Crumbs CarPlay live-recovery map and chase actions; entitlement and physical-head-unit validation remain release gates. |
| Simulator | Replace | One balloon, wind-driven altitude-aware motion, one routed chase vehicle, live landing envelope and recovery lifecycle. |
| Diagnostics and export | Adapt | Flight terminology, Balloon Crumbs filenames and privacy-bounded local export. |
| Motorcycle roles, leader/tail hierarchy and bike identity | Replace | `FlightRole`, `Craft`, balloon/chase authority and craft-owned markers. Legacy storage/wire fields are decode-only compatibility boundaries. |
| Junction drop-offs, rejoin flow and back-marker behaviour | Remove | Motorcycle group-riding workflow; no Balloon Crumbs navigation or setup surface exposes it. |
| Motorcycle discovery, circular routes, ride heatmaps, fuel/comfort stops and motorcycle POIs | Remove | Not balloon-recovery primitives and not shipped. |
| Fixed speed-camera catalogue, camera/police reporting and enforcement warnings | Remove | Bundled dataset, domain categories, map controls, overlays, speech, diagnostics and tests removed. Posted speed limits remain. |
| Aeronautical chart as the primary live basemap | Replace | Road map is primary; OpenAIP is planner context only and is never represented as an operational briefing. |
| Upstream domains, update URLs, user-agent strings and diagnostic filenames | Replace | Balloon Crumbs-specific values only. Configuration examples contain no Tail End Charlie production host. |
| Upstream signing profiles, credentials and release workflows | Remove | Never copied. Balloon Crumbs signing and store workflows were created independently and use repository secrets. |

## Deliberate compatibility identifiers

The following inherited names can remain below the product boundary because
changing them would strand installed test builds or mixed-version relay state:

- persisted and relayed `riderId`, `riderName`, `riderSymbol` and historical
  event payload keys;
- native channel/header identifiers such as `x-tailendcharlie-*` where both old
  and current builds must interoperate;
- the stable identity-hash namespace used to recover the same anonymous device;
  and
- legacy `motorcycleStyle` input at storage/relay boundaries, normalised to
  canonical craft identity before it reaches product state.

These identifiers are not user-facing roles, copy, icons, controls, hosts,
credentials or deployment configuration. New domain events and UI use canonical
flight/craft terms.

## Scaffold safety and current release boundary

The scaffold initially used `balloon-crumbs.invalid` and development identifiers.
Real Balloon Crumbs domains, provider choices, bundle/application identifiers
and store workflows were added only after explicit selection. Secrets remain in
deployment environments or GitHub secrets and are never checked in.

The app is still an internal-test build, not an authoritative aviation,
meteorological, land-ownership or driver-safety product. Apple CarPlay
entitlement approval, physical projected-car validation and optional licensed
map/data activation remain external release gates.
