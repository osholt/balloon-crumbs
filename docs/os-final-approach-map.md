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
Balloon Crumbs uses the **free OS OpenData Plan** and admits only native zooms
13–16. At closer display zooms the renderer may enlarge the zoom-16 image, but
neither the client nor relay can request a Premium tile.

The [OS API Service Terms](https://osdatahub.os.uk/support/legal/api-terms)
expressly permit Open API Services for any purpose under the
[Open Government Licence v3](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/),
including making Open API Data available to application end users. The OGL
permits copying, publishing, adapting and commercial or non-commercial use,
subject to attribution, no implied endorsement and its other conditions. OS
documents OS Maps API as suitable for web and mobile basemaps. This is the
licensing basis for the feature; it does not rely on the Premium allowance.

The free plan remains subject to OS service limits and fair use. Observe its
aggregate use in the dedicated OS Data Hub project dashboard. Do not switch the
project to Premium, broaden the admitted zoom range or change the cache policy
without a fresh licence review.

## Credential, privacy and usage controls

- Store the project key only as `BALLOON_CRUMBS_OS_MAPS_API_KEY` in the Oracle
  host's mode-600 deployment environment. Never place it in GitHub, Dart
  defines, mobile assets, tile URLs, JavaScript, logs or screenshots.
- The Pages Worker accepts only `/maps/os/outdoor/…`; Caddy accepts numeric XYZ
  requests only at zoom 13–16 and rewrites them to the fixed OS
  `Outdoor_3857` endpoint. It is not a general proxy.
- The raster source declares Great Britain bounds, preventing MapLibre from
  requesting tiles elsewhere. The app offers the control only within
  conservative Great Britain bounds.
- Caddy access logging remains disabled. Observe aggregate map-view usage and
  service status in the dedicated OS Data Hub project dashboard, which does not
  require Balloon Crumbs to retain precise flight viewports.
- Responses conservatively use `Cache-Control: private, max-age=86400`; no
  shared tile cache or offline-region download is enabled for this layer.

The official colour OS API logo is fixed inside the map whenever the layer is
visible. Required attribution and links to the OGL, OS API terms and OS map
error/contact route are available in the map selection sheet:

> Contains OS data © Crown copyright and database right 2026

This follows OS's [mobile branding guidance](https://docs.os.uk/os-apis/core-concepts/os-api-branding):
the logo remains on the map, while copyright, terms and error-reporting links
sit in the menu rather than obscuring the limited mobile viewport. The logo is
the unmodified official `os-logo-maps.png` from OS's OGL-licensed
[`os-api-branding`](https://github.com/OrdnanceSurvey/os-api-branding)
repository (SHA-256
`2de353907ce3695b12ee2553e7f87064c8bbcf94720f404edcd5391a0dc4f15c`).

## Activation

1. Create the live OS Data Hub project and place its key in the Oracle env file.
2. Recreate the isolated Caddy container.
3. Set repository variable `BALLOON_CRUMBS_OS_FINAL_APPROACH_ENABLED=true`.
4. Build tester releases. The client contains only the same-origin Pages tile
   template; it never contains the OS credential.
5. Verify Bristol and rural-field views at zooms 13 and 16, verify closer
   display zooms do not request 17–20, then remove
   the key during a live view and confirm the road map, tracks and guidance
   remain present.
