# Tester release notes

Android workflow runs attach a generated release summary containing the app
version, Play version code, commit, destination track, and recent changes. Copy
the tester-facing entry here after each release so an installed build can be
matched to its changes.

## Next tester build

- Lets the person creating a flight choose Pilot, balloon crew, chase driver,
  or chase crew instead of assuming that the creator is the Pilot.
- Lets a joining balloonist request Pilot, with a deliberate assignment and
  acceptance step so an invitation cannot silently seize flight authority.
- Makes reusable crew rooms such as `TUCKER` selectable during flight creation
  and clearly distinguishes the persistent room name from the fresh private
  six-digit invitation for each launch.
- Preserves the creator's selected role and chase-vehicle name when starting a
  fresh flight in the same crew room.
- Shows the chase split view immediately in phone landscape: a complete
  north-up crew/balloon overview on the left and direction-up road guidance on
  the right, including the waiting state before the first balloon fix.
- Keeps that landscape presentation aligned with CarPlay, including shared
  tracks, balloon context, road distance, and travel time.

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
