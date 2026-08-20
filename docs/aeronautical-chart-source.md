# Aeronautical chart source

OpenAIP is the selected advisory aeronautical layer for tester builds. The app
uses OpenAIP's combined raster aeronautical chart and visibly attributes it as
`© openAIP contributors · CC BY-NC 4.0`.

The service describes itself as TMS, but OpenAIP's current first-party
MapLibre style consumes the published `{z}/{x}/{y}` coordinates as XYZ. The app
matches that live contract and renders the combined chart opaquely instead of
blending it into the ordinary road basemap.

Release workflows require this Actions secret:

```text
BALLOON_CRUMBS_OPENAIP_API_KEY
```

The key is a third-party application key created from the OpenAIP user profile.
It is passed as a `--dart-define`, never committed. OpenAIP's tile endpoint is
built into the app only because the provider has now been explicitly selected.

The build timestamp starts a 28-day configuration window. An unstamped local
build, missing key, future timestamp, or tester build beyond that window does
not draw the chart; the balloon map labels it unavailable or stale instead.

## Limitations

OpenAIP is community-maintained advisory data. It can show controlled airspace,
ATZ/MATZ, danger/prohibited areas, aerodromes, and vertical limits, but it is not
an authoritative or complete source of current UK NOTAMs and temporary
restrictions. The UI therefore says that directly and does not describe the
layer as clearance, terrain clearance, or primary navigation.

For UK operations, pilots must still check the current NATS UK AIS AIP and
official NOTAM/pre-flight briefing. NATS AIRAC links are dynamic and must not be
treated as permanent tile endpoints.
