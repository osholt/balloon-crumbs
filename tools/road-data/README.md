# Road data generators

Two static layers built from OpenStreetMap extracts, generated once, checked in,
and shipped in the app bundle. Being bundled rather than fetched is the point: a
chase driver in a rural lane with no signal gets the same warning as one on a
motorway.

Both emit a GeoJSON `FeatureCollection` carrying the ODbL attribution and the
extract date.

## Speed cameras

`highway=speed_camera` nodes from Overpass JSON. Accepts several input files so a
large region can be fetched in tiles.

```bash
python3 tools/road-data/generate_speed_cameras.py \
  --input <overpass.json> [--input <more.json>] \
  --bounded-region <region> \
  --output apps/mobile/assets/<layer>.geojson
```

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

These two lived in `tools/discovery/` alongside the motorcycle catalogue
pipeline — good biking roads, twisty highlights, mountain passes, biker stops —
which was deleted with the discovery layer (#19, #21). They were never part of
it: neither imports anything from it, and both serve the enforcement alerts and
turn guidance that the chase driver keeps. They were moved rather than deleted
because the road they run on is a road, whoever is driving it.
