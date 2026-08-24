# Road routing provider policy

Reviewed 24 August 2026 for the safe moving-rendezvous closure.

## Configured providers

The mobile client keeps every endpoint replaceable at build time:

| Purpose | Default | Build-time setting |
| --- | --- | --- |
| ordinary car routing | OSRM public demo | `BALLOON_CRUMBS_ROUTING_URL` |
| dimension/restriction-aware routing | Valhalla public demo | `BALLOON_CRUMBS_VALHALLA_ROUTING_URL` |
| user-triggered place search | public Nominatim | `BALLOON_CRUMBS_GEOCODING_URL` |

These defaults are suitable for the current small internal test group, not a
capacity or uptime commitment for a public launch.

## Terms and request bounds

- The [OSRM demo service policy](https://map.project-osrm.org/about.html)
  permits fair use with attribution, an identifying user agent, no scraping or
  heavy use, and at most one request per second.
- The [Valhalla public-demo documentation](https://valhalla.github.io/valhalla/start/introduction/)
  applies the same fair-use policy and asks published clients to send an
  identifying `X-Client-Id`. Balloon Crumbs sends both `User-Agent` and
  `X-Client-Id` on road requests.
- The [Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/)
  permits moderate, user-triggered app search at no more than one request per
  second, with identification, attribution, caching and a switchable endpoint.
  Balloon Crumbs does not use it for autocomplete, reverse-query grids or
  moving-target routing.
- The routing graph is principally OpenStreetMap data. Attribution and the ODbL
  data terms remain visible through the app's map information surface; see the
  [Valhalla data-source statement](https://valhalla.github.io/valhalla/mjolnir/data_sources/).

One rendezvous decision tries at most four surrounding candidates, plus the
previous endpoint when it is still relevant. Requests are sequential with
1.1 seconds between them. Ordinary recalculation then requires two minutes and
300 m of target movement; a stationary route is refreshed after ten minutes.
This keeps the default clients below the provider request-rate limit.

## What provider routing proves

OSRM's car profile and Valhalla's auto/truck costing use mapped road and access
restrictions. Vehicle dimensions entered by a crew select Valhalla truck
costing. A returned path therefore means the provider found a traversable route
under its profile and current OpenStreetMap graph.

It does **not** prove that:

- every private, destination-only, seasonal or temporary restriction is mapped;
- a gate is open or a landowner has given permission;
- a road shoulder, gateway or lane is safe or lawful to stop on;
- the vehicle dimensions or source map are complete and current.

The app consequently says “mapped access only”, keeps field permission and safe
stopping unverified, and freezes the prior route if no bounded candidate is
accepted. A raw airborne coordinate is never submitted as the driving endpoint.

