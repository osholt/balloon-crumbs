# CarPlay navigation entitlement and acceptance

Status: implementation complete; Apple managed-capability grant and physical
vehicle acceptance pending (2026-08-23).

## Requested capability

- App: Balloon Crumbs
- Bundle ID: `dev.osholt.ballooncrumbs`
- Category: navigation
- Entitlement: `com.apple.developer.carplay-maps`
- Apple request: <https://developer.apple.com/contact/request/carplay/>

Request description:

> Balloon Crumbs is an account-free, offline-first hot-air-balloon recovery
> coordination app. It shares one balloon's and its private chase crew's live
> positions, recent tracks, fix freshness, intended or confirmed landing area,
> and a safe road-accessible rendezvous. CarPlay is the chase driver's primary
> low-interaction surface. Planning, weather detail, pilot controls and personal
> land-access notes remain on the phone.

CarPlay behaviour:

> The navigation scene presents a two-dimensional road map with the local chase
> vehicle, balloon, other chase vehicles, shared trails, fix age/state, intended
> landing area, confirmed landing point and forecast landing envelope. It gives
> lawful road guidance, manoeuvre distance, ETA, spoken instructions and dynamic
> rerouting to either the current safe rendezvous near the balloon or the crew's
> published landing target. Drivers have one-tap Follow and North-up/Direction-up
> controls and bounded CarPlay-template actions. It never routes directly
> off-road, presents aviation/weather controls, or asks the pilot to operate it.

Submitting the request also requires the account holder to accept Apple's
CarPlay Entitlement Addendum. Keep the final submission with the account holder;
do not automate acceptance of that agreement.

## Repository and signing gates

- Debug, profile and release targets declare the maps entitlement.
- `Info.plist` registers `CarPlaySceneDelegate` for the CarPlay template scene.
- The TestFlight workflow and local uploader inspect the signed IPA with
  `codesign` and refuse upload without the granted maps entitlement.
- After Apple grants the capability, regenerate both development and App Store
  provisioning profiles for the Balloon Crumbs App ID. Never reuse the inherited
  Tail End Charlie or Hot Pursuit profile.

## Implemented driver surface

- MapLibre road basemap using the phone's resolved light/dark style.
- One balloon plus independent chase vehicles with explicit craft icons,
  heading, ground speed, altitude where applicable, and `live`, `stale` or
  `unknown` detail.
- Balloon trace split into the same altitude-coloured segments as the phone and
  web planner; recent vehicle traces remain separately identifiable.
- Intended landing envelope and confirmed landing area.
- Persisted North-up/Direction-up camera toggle and Follow control.
- Road route, remaining/ridden geometry, manoeuvre, distance, ETA and rerouting.
- Recovery-specific status/actions with inherited TEC leader/rider branding
  removed.
- Speed-limit presentation remains gated to the chase-driver role.

## Acceptance matrix

| Evidence | Status | Requirement |
| --- | --- | --- |
| Flutter analysis and focused projection tests | Pass | No Dart/static failures; snapshot contract covered |
| Native iOS simulator build | Pass | Swift scene and MapLibre renderer compile |
| iOS 17.5 CarPlay Home | Pass | Balloon Crumbs appears with the navigation entitlement |
| Signed development archive | Pending grant | Embedded profile and app signature contain maps entitlement |
| Signed TestFlight IPA | Pending grant | CI's entitlement gate passes before upload |
| Minimum 748x456, standard 800x480, portrait 768x1024, high-res 1920x720 | Pending final visual run | No clipped controls or hidden attribution |
| Locked iPhone | Physical test required | Recovery map and guidance continue while phone is locked |
| Wired and wireless CarPlay | Physical test required | Connect/reconnect, voice/audio ducking and reroutes work |
| North-up/Direction-up, Follow, landing target and balloon target | Physical test required | Controls remain bounded and responsive in motion |
| Full launch-to-LANDED-to-recovery rehearsal | Physical test required | No phone interaction is required from the driver |

Apple explicitly says Simulator is not sufficient for locked-phone, Siri or
audio behaviour, so physical evidence is a release gate. On Xcode 26.5's iOS
26.5 runtime, Apple's `CarPlayTemplateUIHost` currently aborts while evaluating
destination sharing (`vehicleSupportsDestinationSharing`). That is an Apple
host-process regression, not a Runner crash; the iOS 17.5 runtime is retained
for projected-display visual testing until the runtime is fixed.
