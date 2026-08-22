export const MAP_PALETTES = Object.freeze({
  dark: {
    background: "#14111b",
    landcover: "#17201c",
    park: "#17201c",
    residential: "#181420",
    water: "#1b2436",
    building: "#201b29",
    boundary: "#3a3247",
    path: "#241f2e",
    minor: "#2a2434",
    tertiary: "#352e42",
    primary: "#40374f",
    motorway: "#4d4260",
    label: "#8d84a0",
    place: "#c4b9c0",
    halo: "#14111b",
  },
  light: {
    background: "#f1eee7",
    landcover: "#dce8d5",
    park: "#d4e6cd",
    residential: "#e9e3dc",
    water: "#b9dced",
    building: "#ddd4ca",
    boundary: "#a89bab",
    path: "#d2c9bf",
    minor: "#c7bdb2",
    tertiary: "#b6a99e",
    primary: "#9d8d83",
    motorway: "#8d7b87",
    label: "#514958",
    place: "#302b34",
    halo: "#f1eee7",
  },
});

export function themePaintUpdates(themeName) {
  const palette = MAP_PALETTES[themeName];
  return [
    ["background", "background-color", palette.background],
    ["landcover-green", "fill-color", palette.landcover],
    ["park", "fill-color", palette.park],
    ["landuse-residential", "fill-color", palette.residential],
    ["water", "fill-color", palette.water],
    ["waterway", "line-color", palette.water],
    ["building", "fill-color", palette.building],
    ["boundary-admin", "line-color", palette.boundary],
    ["road-path", "line-color", palette.path],
    ["road-minor", "line-color", palette.minor],
    ["road-tertiary", "line-color", palette.tertiary],
    ["road-primary", "line-color", palette.primary],
    ["road-motorway", "line-color", palette.motorway],
    ["road-label", "text-color", palette.label],
    ["road-label", "text-halo-color", palette.halo],
    ["place-label", "text-color", palette.place],
    ["place-label", "text-halo-color", palette.halo],
  ];
}

export function themeStyle(style, themeName) {
  const layers = new Map((style.layers ?? []).map((layer) => [layer.id, layer]));
  for (const [layerId, property, value] of themePaintUpdates(themeName)) {
    const layer = layers.get(layerId);
    if (layer) layer.paint = { ...(layer.paint ?? {}), [property]: value };
  }
  return style;
}

export function applyThemePaint(map, themeName) {
  if (!map) return;

  // MapLibre's isStyleLoaded() also becomes false while source tiles are
  // loading. Theme changes are still safe at that point, so checking it makes
  // a toggle silently affect the page chrome but not the map during a pan or
  // raster refresh. Layer existence is the actual precondition we need.
  for (const [layerId, property, value] of themePaintUpdates(themeName)) {
    if (map.getLayer(layerId)) map.setPaintProperty(layerId, property, value);
  }
  if (map.getLayer("openaip-chart")) {
    map.setPaintProperty(
      "openaip-chart",
      "raster-opacity",
      themeName === "dark" ? 0.76 : 0.62,
    );
  }
  if (map.getLayer("forecast-track-casing")) {
    map.setPaintProperty(
      "forecast-track-casing",
      "line-color",
      themeName === "dark" ? "#ffffff" : "#11151c",
    );
  }
}
