# Road-first live recovery map

The active-flight map is a shared recovery picture and does not require an
imported planner forecast. Its default basemap is the configured road map;
aeronautical tiles remain planner-only context.

## Shared live state

- Every operational role receives balloon and chase positions, craft identity,
  fix freshness, measured ground speed and direction.
- Each device keeps its own lawful road route. Route geometry is never written
  into the shared flight state and cannot overwrite another chaser's target.
- Durable journal positions rebuild the complete bounded balloon and chase
  tracks after a reconnect. Rendering simplification bounds map cost without
  truncating the recorded history.
- The balloon ground track is altitude-coloured. Forecast tracks and possible
  landing envelopes use separate advisory styling and labels.
- North-up and Direction-up are independently persisted for the balloon phone,
  chase phone and CarPlay surface.

## Live possible-landing estimate

When there is no imported forecast, the app combines the latest usable balloon
fix with the timestamped Open-Meteo UKMO wind field. It explores the published
height levels and bounded 20–120 minute flight durations, using a 2,000 m MSL
fallback ceiling when no planner constraints exist. This is deliberately a
recovery estimate, not a flight plan or landing-suitability claim.

On iOS, GNSS geoid altitude is used directly. Android GNSS ellipsoid movement
is terrain-referenced against the balloon's first durable fix. If neither a
usable altitude nor a terrain reference is available, the app explains that it
cannot calculate the estimate.

The forecast is removed rather than extrapolated when the balloon fix or wind
field is stale, incompatible, or the flight has been marked LANDED. Its source,
valid time and limitations are carried into the map label and recovery panel.

## Driver boundary

Chase drivers see the shared craft, tracks and live recovery estimate alongside
their own road guidance. They do not receive wind-grid controls, aeronautical
tiles, pilot controls or forecast data presented as authoritative guidance.
Road routing continues to target a safe road-accessible rendezvous rather than
an airborne or off-road coordinate.
