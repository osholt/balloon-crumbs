# Road data generators

One static road-guidance layer built from an OpenStreetMap extract, generated
once, checked in, and shipped in the app bundle. Being bundled rather than
fetched lets rural chase guidance work without signal.

It emits a GeoJSON `FeatureCollection` carrying the ODbL attribution and the
extract date.

## Mini-roundabouts

`highway=mini_roundabout` nodes. OSRM and Valhalla both route through these
without necessarily emitting a manoeuvre, so the driver gets no instruction at a
junction they have to give way at. This layer restores it.

```bash
python3 tools/road-data/generate_mini_roundabouts.py \
  --input <overpass.json> \
  --output apps/mobile/assets/<layer>.geojson
```

## Tests

```bash
python3 -m unittest discover -s tools/road-data/tests -v
```

## Why this directory exists

This generator lived in `tools/discovery/` alongside the motorcycle catalogue
pipeline — good biking roads, twisty highlights, mountain passes, biker stops —
which was deleted with the discovery layer (#19, #21). It was never part of
it: it imports nothing from that pipeline and serves ordinary road-junction
guidance for chase vehicles.
