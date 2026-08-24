# Optional OS final-approach map

Decision recorded: 24 August 2026. Recheck the linked terms before changing
provider, plan, cache duration, zoom range or attribution.

## Product boundary

The ordinary road map remains the default live and CarPlay map. A chase device
in Great Britain can optionally place OS Maps API `Outdoor_3857` raster detail
over that road map for the final approach to a field. Shared balloon and crew
tracks, landing state, forecast envelope and road guidance are app-owned layers
above both maps. The balloon view does not offer the control.

OS detail is online-only. The app probes one close-zoom tile before enabling it.
The road map remains mounted underneath, so an unavailable or failed OS tile
immediately reveals the road map without removing flight geometry. Flutter's
fallback renderer also turns the layer off on a tile error. CarPlay deliberately
continues to use the recovery road map: it avoids a raster/provider dependency
on the safety-relevant projected display and complies with its smaller-screen
interaction constraints.

The UI states that map detail does not identify an owner, grant access, prove a
safe vehicle entrance or replace local permission.

## Provider and plan decision

Use the official [OS Maps API](https://docs.os.uk/os-apis/accessing-os-apis/os-maps-api)
with the Web Mercator `Outdoor_3857` style. OS documents it for web and mobile
applications and gives Great Britain coverage. In that layer, [zooms 7–16 are
OS OpenData and 17–20 are Premium](https://docs.os.uk/os-apis/accessing-os-apis/os-maps-api/layers-and-styles).
Balloon Crumbs admits only zooms 13–20 because this is a field-approach aid, not
a general alternative basemap.

For production, create a separate **live Premium Plan project** for Balloon
Crumbs. OS currently provides up to £1,000 of premium API use each month and
unlimited OpenData use; OS Maps API accounts one map view per 15 raster tiles
and applies a 600-transactions-per-minute project throttle. These current
[plan and transaction rules](https://osdatahub.os.uk/support/faqs/plans) are
the server-side billing guard. Do not use a development-mode key in a tester or
production build. To make overage a hard failure rather than a surprise charge,
do not attach an automatic overage payment method; OS says premium access pauses
after the included allowance if valid payment details are absent while OpenData
continues.

## Credential, privacy and usage controls

- Store the project key only as `BALLOON_CRUMBS_OS_MAPS_API_KEY` in the Oracle
  host's mode-600 deployment environment. Never place it in GitHub, Dart
  defines, mobile assets, tile URLs, JavaScript, logs or screenshots.
- The Pages Worker accepts only `/maps/os/outdoor/…`; Caddy accepts numeric XYZ
  requests only at zoom 13–20 and rewrites them to the fixed OS
  `Outdoor_3857` endpoint. It is not a general proxy.
- The raster source declares Great Britain bounds, preventing MapLibre from
  requesting tiles elsewhere. The app offers the control only within
  conservative Great Britain bounds.
- Caddy access logging remains disabled. Observe aggregate map-view usage and
  cost in the dedicated OS Data Hub project dashboard, which does not require
  Balloon Crumbs to retain precise flight viewports.
- OS's [API terms](https://osdatahub.os.uk/support/legal/api-terms?lang=en)
  permit Premium end users to cache temporarily for up to 24 hours. Responses
  therefore use `Cache-Control: private, max-age=86400`; no shared tile cache or
  offline-region download is enabled for this layer.

Required attribution is available in the map selection sheet:

> Contains OS data © Crown copyright and database right 2026

OS's [mobile branding guidance](https://docs.os.uk/os-apis/core-concepts/os-api-branding)
allows required information to sit in the application's menu rather than
obscuring a limited map view.

## Activation

1. Create the live OS Data Hub project and place its key in the Oracle env file.
2. Recreate the isolated Caddy container.
3. Set repository variable `BALLOON_CRUMBS_OS_FINAL_APPROACH_ENABLED=true`.
4. Build tester releases. The client contains only the same-origin Pages tile
   template; it never contains the OS credential.
5. Verify Bristol and rural-field views at zooms 13, 16, 17 and 20, then remove
   the key during a live view and confirm the road map, tracks and guidance
   remain present.
