# Tester release notes

Android workflow runs attach a generated release summary containing the app
version, Play version code, commit, destination track, and recent changes. Copy
the tester-facing entry here after each release so an installed build can be
matched to its changes.

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
