# Weather and wind source

Decision reviewed: 24 August 2026. Recheck the linked provider and licence
pages before a public, paid or high-volume release.

Open-Meteo is the selected advisory wind provider for tester builds. Balloon
Crumbs requests the UK Met Office UKV forecast through Open-Meteo's keyless
forecast API and displays a 5 × 5 grid of wind direction and speed values at
selectable heights from 20 m to 2,000 m above mean sea level. It also requests
the UKMO surface gust: this is labelled `G`, in km/h, and is explicitly the
forecast gust at 10 m above ground level (AGL), not a gust at the selected MSL
wind layer.

No API credential is stored or shipped. Slider changes reuse the complete
vertical profile returned by the last request; they do not make another
request. Forecast data is kept in memory only and is not an offline cache. A
prior in-memory response may remain visible after a network failure, but it is
labelled `STALE` after either its fetch age exceeds two hours or its valid time
is more than 90 minutes from the current time. The simulator retains its dated,
bundled wind profile as a visibly separate `BUNDLED REFERENCE`, never as a live
or current forecast.

The map attributes the live data to Open-Meteo and identifies UKMO as the model
source. Open-Meteo's UKMO documentation states that UK Met Office data is
licensed under CC BY-SA 4.0:

- <https://open-meteo.com/en/docs/ukmo-api>
- <https://open-meteo.com/en/license>

## Operational fit and provenance

Open-Meteo's UKMO documentation says the seamless UK feed combines the UKMO
Global model with the high-resolution UKV 2 km model over the UK and Ireland.
UKV is hourly, updates every hour and supplies approximately two forecast days.
Open-Meteo also notes an additional delay for UKMO open data. The bounded app
request asks for the nearest three model hours; the web planner asks for three
days so it can vary departure time.

The response used here exposes forecast valid times but not a trustworthy model
run identifier. Balloon Crumbs therefore shows the provider/model, exact valid
time and local fetch age, and does not invent or imply a run time. The web
planner additionally shows the selected model hour. The app does not request
Open-Meteo's “current” variables and has no observation provider: every wind or
gust value in this product is styled and described as forecast model output.

Only the selected, bounded wind context needed for a flight replay is shared
with that operation; it carries source, valid time, units and forecast status.
The 25-column provider response is not stored on the relay or redistributed as
a reusable weather dataset.

Open-Meteo's public keyless endpoint is suitable for current internal testing.
Its fair-use, rate, commercial-plan and attribution terms must be reviewed
before launch or increased load. No response is committed to Git or placed in a
shared offline pack.

## Limitations

This is numerical forecast-model output, not a live measurement from the
balloon and not an aviation weather briefing. The displayed valid time, height
datum, units, source, fetch age/freshness, surface-gust datum and forecast-only
warning must remain visible. Turning the map layer off hides the arrows but does
not change the simulator's wind physics.

Wind layers and telemetry use km/h for horizontal speed and metres MSL for
height. Vertical telemetry/rates remain m/s. Surface gust is the sole AGL value
and is labelled `10 m AGL` everywhere it is explained.

Failure or expiry never blocks balloon/crew positions, tracks, landing status or
chase guidance. Automated fixtures cover updated forecast selection, altitude
and bearing interpolation, current-to-stale transition, failed/offline refresh,
the dated bundled simulator reference, and 10 m gust parsing.

Pilots and crews must use an appropriate official aviation forecast and briefing
for operational decisions.
