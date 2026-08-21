# Tester release notes

Android workflow runs attach a generated release summary containing the app
version, Play version code, commit, destination track, and recent changes. Copy
the tester-facing entry here after each release so an installed build can be
matched to its changes.

## Next tester build

- Adds **Plan a balloon flight** to the home map's More menu and opens the live
  planner in the iOS/Android in-app browser.
- Includes the planner's maximum-altitude landing envelope, draggable launch
  and destination points, wind-route search, and timed altitude profile without
  maintaining a second forecast implementation in the app.
- Keeps the planner's Open-Meteo/OpenAIP source labels and advisory safety
  warning visible.

## 1.0.1 (Play build 26 / TestFlight build 27) — 21 August 2026

- Adds UKMO forecast wind from Open-Meteo to the balloon map, with downwind
  arrows, speed, source and valid time.
- Adds an altitude slider from 20 m to 2,000 m MSL and a switch that hides the
  wind overlay without changing the simulated flight.
- Replaces the old demo fleet with one balloon and one Land Rover.
- Keeps the balloon's scripted climb and descent while forecast wind controls
  its ground direction.
- Updates the forecast landing area as the balloon moves and reroutes the Land
  Rover from its current position when that area changes.
- Moves the map clock above altitude telemetry and moves OpenAIP status into the
  information sheet, alongside a plain-language aeronautical chart key.

Open-Meteo wind and OpenAIP airspace are advisory forecast/context layers, not
an aviation weather briefing, clearance, or primary navigation source.

## 1.0.1 (Play build 25) — 20 August 2026

- Colours each balloon ground-track leg by measured altitude and shows a metric
  altitude legend; unavailable altitude remains grey.
- Shows the simulated landing zone and keeps it inside the balloon/chase map
  framing.
- Corrects OpenAIP chart addressing and renders the selected aeronautical chart
  without blending it into the road basemap.
- Makes the simulator climb, cruise, descend, and land rather than remaining at
  one altitude.
- Keeps the complete recorded chase-crew trail instead of discarding its oldest
  samples after a short distance.
- Displays balloon altitude in metres independently of the road-distance unit.

OpenAIP remains advisory context rather than an authoritative navigation source.
