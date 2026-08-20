# Weather and wind source

Open-Meteo is the selected advisory wind provider for tester builds. Balloon
Crumbs requests the UK Met Office UKV forecast through Open-Meteo's keyless
forecast API and displays a small grid of wind direction and speed values at
selectable heights from 20 m to 2,000 m above mean sea level.

No API credential is stored or shipped. Slider changes reuse the complete
vertical profile returned by the last request; they do not make another
request. Forecast data is kept in memory only. The simulator retains its dated,
bundled wind profile as an offline fallback.

The map attributes the live data to Open-Meteo and identifies UKMO as the model
source. Open-Meteo's UKMO documentation states that UK Met Office data is
licensed under CC BY-SA 4.0:

- <https://open-meteo.com/en/docs/ukmo-api>
- <https://open-meteo.com/en/license>

## Limitations

This is numerical forecast-model output, not a live measurement from the
balloon and not an aviation weather briefing. The displayed valid time, height
datum, units, source, and forecast-only warning must remain visible. Turning the
map layer off hides the arrows but does not change the simulator's wind physics.

The public keyless endpoint is appropriate for the current internal-test use.
Usage, attribution, caching, and commercial terms must be reviewed again before
a public or paid release.
