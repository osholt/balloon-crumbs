import assert from "node:assert/strict";
import test from "node:test";

import { applyThemePaint, themeStyle } from "./planner-theme.mjs";

test("applies a theme while map sources are still loading", () => {
  const layers = new Set([
    "background",
    "water",
    "road-label",
    "openaip-chart",
    "forecast-track-casing",
  ]);
  const updates = [];
  const map = {
    isStyleLoaded: () => false,
    getLayer: (id) => layers.has(id),
    setPaintProperty: (id, property, value) => updates.push([id, property, value]),
  };

  applyThemePaint(map, "dark");

  assert.deepEqual(updates, [
    ["background", "background-color", "#14111b"],
    ["water", "fill-color", "#1b2436"],
    ["road-label", "text-color", "#8d84a0"],
    ["road-label", "text-halo-color", "#14111b"],
    ["openaip-chart", "raster-opacity", 0.76],
    ["forecast-track-casing", "line-color", "#ffffff"],
  ]);
});

test("prepares the initial style with the selected light palette", () => {
  const style = {
    layers: [
      { id: "background", paint: { "background-color": "old" } },
      { id: "water", paint: { "fill-color": "old", "fill-opacity": 0.8 } },
    ],
  };

  assert.equal(
    themeStyle(style, "light").layers[0].paint["background-color"],
    "#f1eee7",
  );
  assert.deepEqual(style.layers[1].paint, {
    "fill-color": "#b9dced",
    "fill-opacity": 0.8,
  });
});
