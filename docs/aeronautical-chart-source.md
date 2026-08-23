# Aeronautical chart source

OpenAIP is the selected advisory aeronautical layer for the optional web
planner. The live iOS and Android recovery maps are road-first and never load
OpenAIP tiles. The planner uses OpenAIP's combined raster aeronautical chart and
visibly attributes it as `© openAIP contributors · CC BY-NC 4.0`.

The service describes itself as TMS, but OpenAIP's current first-party
MapLibre style consumes the published `{z}/{x}/{y}` coordinates as XYZ. The app
matches that live contract and renders the combined chart opaquely instead of
blending it into the ordinary road basemap.

The deployed planner relay requires this host-side secret:

```text
BALLOON_CRUMBS_OPENAIP_API_KEY
```

The key is a third-party application key created from the OpenAIP user profile.
It is supplied only to the relay's bounded `/maps/openaip/` proxy and is never
committed, placed in planner JavaScript, or compiled into a mobile tester build.

The dormant mobile provider boundary remains so a future pilot-only product can
opt in without changing the chase map. Its default is off and no production
call site enables it. Planner availability is independent of live recovery.

## Limitations

OpenAIP is community-maintained advisory data. It can show controlled airspace,
ATZ/MATZ, danger/prohibited areas, aerodromes, and vertical limits, but it is not
an authoritative or complete source of current UK NOTAMs and temporary
restrictions. The UI therefore says that directly and does not describe the
layer as clearance, terrain clearance, or primary navigation.

For UK operations, pilots must still check the current NATS UK AIS AIP and
official NOTAM/pre-flight briefing. NATS AIRAC links are dynamic and must not be
treated as permanent tile endpoints.
