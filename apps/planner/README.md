# Balloon pilot planner

Static application code for a balloon pilot's forecast flight plan. It keeps
the short plan-code flow inherited from Tail End Charlie, but it does not
pretend a balloon follows a road route:

- the pilot selects a launch point, departure time, duration and altitude;
- UKMO UKV wind from Open-Meteo is sampled on the same 3×3 grid and MSL height
  levels used by the mobile app;
- the forecast track integrates the balloon through its own climb, cruise and
  descent profile;
- the basemap and planner controls can switch between light and dark themes,
  with an explicit tile-load indicator and retry action;
- OpenAIP's combined aeronautical chart is visible with a plain-language key;
- the purple landing envelope is the convex boundary of endpoints produced by
  the tested two-stage altitude strategies;
- an optional destination search ranks those strategies by forecast miss
  distance and clearly reports when none gets within the planning tolerance;
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
