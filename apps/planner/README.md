# Balloon pilot planner

Static application code for a balloon pilot's forecast flight plan. It keeps
the short plan-code flow inherited from Tail End Charlie, but it does not
pretend a balloon follows a road route:

- the pilot can find a UK place with a submit-only OpenStreetMap search, choose
  a result explicitly as the launch point, and then select a flight date, launch
  elevation and optional destination;
- UKMO UKV wind from Open-Meteo is sampled across a 5×5 grid spanning roughly
  120 km around the launch, at 14 MSL height levels, with hourly interpolation
  during the flight and spatially interpolated display arrows across the visible
  sampling area;
- the destination optimiser searches start times across the selected day,
  10–180 minute durations and four changing altitude controls up to the highest
  pilot-selected maximum altitude, bounded by the highest 2,000 m MSL forecast
  layer; the same ceiling constrains the representative track and landing
  envelope;
- start time, an approximate matching window for the selected profile, duration,
  altitude profile and resulting peak altitude are optimiser outputs rather than
  pilot-supplied route inputs;
- before a destination is chosen, a clearly labelled representative 60-minute
  forecast keeps a visible altitude-coloured track, start time, duration, peak
  altitude and forecast landing on the map;
- placed launch and destination pins can be dragged directly; moving the launch
  reloads its wind field while retaining the destination, and moving the
  destination reruns the optimiser without a separate placement action;
- after launch, the next map click sets the destination directly, while dragging
  the initial yellow forecast endpoint converts it into the intended destination;
- a flight-profile pane lists launch and landing times, duration, the altitude at
  each 20% stage and each climb, level or descent change;
- the compact control panel keeps route inputs and results together, with wind,
  chart and sharing controls grouped below and longer guidance in disclosures;
- the basemap and planner controls can switch between light and dark themes,
  with an explicit tile-load indicator and retry action;
- OpenAIP's combined aeronautical chart is visible with a plain-language key;
- the purple landing envelope is the convex boundary of endpoints produced by
  the coarse start-time, duration and altitude search;
- the destination search refines its best candidates to a 100 m acceptance
  distance and clearly reports when none can get that close;
- the forecast landing area and separately editable destination are shown; and
- the resulting forecast track can be stored through `/api/v1/plans` and loaded
  in the app with the returned short code.

The public page is served at `https://balloon-crumbs.pages.dev/`. Its Pages
Worker keeps browser calls same-origin and proxies only the relay, health,
Open-Meteo, OpenFreeMap and OpenAIP paths needed by the planner to the isolated
Oracle deployment. The origin also serves `/plan/` as a recovery path. The
OpenAIP key stays in the host environment and is attached as a request header
by Caddy; it is never shipped to Pages or browser code.

The vendored MapLibre GL JS distribution and licence are copied from the pinned
5.24.0 assets already used by the Tail End Charlie website.

UK Met Office data obtained through Open-Meteo is attributed under CC BY-SA
4.0. See `docs/weather-wind-source.md` for source, licence and safety limits.
Place search uses the public OpenStreetMap Nominatim service through a bounded,
cached Pages endpoint. It never runs autocomplete: only an explicit submitted
query is sent, with a maximum of five UK results.

## Checks

```bash
node --test apps/planner/planner-core.test.mjs
node --test apps/planner/pages-worker.test.mjs
node --check apps/planner/app.js
```

These are forecasts, not aviation briefings or primary navigation. The planner
does not present a track as controllable, and it does not hide missing forecast
data behind a synthetic fallback. The landing envelope is not a safe-landing
assessment and does not mean that every point inside it is reachable. The
destination search does not account for airspace, terrain, legal limits, burner
fuel, or the balloon's actual climb and descent performance.
