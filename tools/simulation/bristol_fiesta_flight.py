#!/usr/bin/env python3
"""Build the Bristol Balloon Fiesta simulation from real measured winds.

The inherited simulator flew every craft along one road polyline at 13.4 m/s -
a motorcycle group ride. A balloon does not follow roads and cannot choose a
heading: it goes where the air goes, and the only control the pilot has is
altitude. That is the whole shape of a chase, so simulating it with a shared
road route teaches the app nothing.

## The winds are real

Measured winds over Ashton Court for the dawn mass ascent of Saturday
8 August 2026, from Open-Meteo (ERA5 archive and best-match model):

    10 m     from 094 degrees at  4.7 km/h
    173 m    from 055 degrees at 13.2 km/h
    832 m    from 159 degrees at 15.9 km/h

The interesting part, and the reason this scenario is worth simulating, is the
directional split. Drift is the reciprocal of the wind, so at 173 m the balloon
tracks 235 (southwest, over Long Ashton and out toward Backwell) while at 832 m
it tracks 339 (north-northwest, over the Avon Gorge toward Avonmouth and the
Severn estuary). Roughly a hundred degrees apart, in the same column of air.

A pilot that morning is therefore choosing a landing area by choosing a height,
and the wrong choice puts them over tidal water. This flight stays low and goes
southwest, which is what the estuary makes the sensible call - and it means the
chase crew must leave Ashton Court southbound before they know exactly where.

## What this produces

    assets/simulation/fiesta_balloon_flight.json  the flight the simulator flies
    assets/simulation/fiesta_balloon_flight.gpx   the same air track, viewable
    assets/simulation/fiesta_chase_route.gpx      a road route to the landing

The JSON is what the simulator reads, because it carries the height and the
clock alongside each position. GPX cannot: this app does not yet read `<ele>`
on import (#16), and a track with no timing would leave the simulator guessing
at a climb rate it already knows. The GPX is written anyway so the flight can be
opened in anything that shows a track.

Wind is interpolated as a vector between layers, never as a bearing: averaging
094 and 339 as numbers gives 216, which is the opposite of the truth. Crossing
layers during a climb or descent is what curves the ground track, so this is the
detail that makes the shape of the flight real rather than a straight line.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import sys
import urllib.request

# Ashton Court launch field, the Fiesta's main ascent site.
LAUNCH = (51.4459, -2.6413)
LAUNCH_ELEVATION_M = 60.0

# (height in metres above ground, wind FROM bearing, speed km/h)
WIND_LAYERS = [
    (10.0, 94.0, 4.7),
    (173.0, 55.0, 13.2),
    (832.0, 159.0, 15.9),
]

# The pilot's plan as (minutes from launch, target height above ground). A dawn
# Fiesta flight is typically 45-60 minutes; the climb to 380 m is the pilot
# looking for a slower or more northerly layer, and finding one that curves the
# track right before they come back down and commit to the field.
ALTITUDE_PLAN = [
    (0.0, 0.0),
    (2.5, 180.0),
    (18.0, 180.0),
    (24.0, 380.0),
    (32.0, 380.0),
    (40.0, 150.0),
    (48.0, 60.0),
    (52.0, 0.0),
]

STEP_SECONDS = 10.0
EARTH_RADIUS_M = 6371000.0


def wind_vector_at(height_m: float) -> tuple[float, float]:
    """East and north components of drift, in metres per second.

    Interpolates the wind as a vector between the measured layers. The returned
    vector is where the balloon *goes*, which is the reciprocal of where the
    wind comes from.
    """
    layers = WIND_LAYERS
    if height_m <= layers[0][0]:
        below = above = layers[0]
        fraction = 0.0
    elif height_m >= layers[-1][0]:
        below = above = layers[-1]
        fraction = 0.0
    else:
        for index in range(len(layers) - 1):
            if layers[index][0] <= height_m <= layers[index + 1][0]:
                below, above = layers[index], layers[index + 1]
                span = above[0] - below[0]
                fraction = (height_m - below[0]) / span
                break

    def components(layer: tuple[float, float, float]) -> tuple[float, float]:
        _, from_bearing, speed_kmh = layer
        speed = speed_kmh / 3.6
        toward = math.radians((from_bearing + 180.0) % 360.0)
        return speed * math.sin(toward), speed * math.cos(toward)

    east_below, north_below = components(below)
    east_above, north_above = components(above)
    return (
        east_below + (east_above - east_below) * fraction,
        north_below + (north_above - north_below) * fraction,
    )


def height_at(minutes: float) -> float:
    plan = ALTITUDE_PLAN
    if minutes <= plan[0][0]:
        return plan[0][1]
    if minutes >= plan[-1][0]:
        return plan[-1][1]
    for index in range(len(plan) - 1):
        start, end = plan[index], plan[index + 1]
        if start[0] <= minutes <= end[0]:
            fraction = (minutes - start[0]) / (end[0] - start[0])
            # Cosine easing: a balloon's vertical rate builds and eases rather
            # than switching instantly, and the curvature of the ground track
            # through a layer change depends on it.
            eased = (1 - math.cos(math.pi * fraction)) / 2
            return start[1] + (end[1] - start[1]) * eased
    return plan[-1][1]


def fly() -> list[dict[str, float]]:
    latitude, longitude = LAUNCH
    track: list[dict[str, float]] = []
    total_minutes = ALTITUDE_PLAN[-1][0]
    steps = int(total_minutes * 60 / STEP_SECONDS)
    for step in range(steps + 1):
        seconds = step * STEP_SECONDS
        height = height_at(seconds / 60.0)
        track.append(
            {
                "seconds": seconds,
                "latitude": latitude,
                "longitude": longitude,
                "height": height,
                "elevation": LAUNCH_ELEVATION_M + height,
            }
        )
        east, north = wind_vector_at(height)
        latitude += (north * STEP_SECONDS / EARTH_RADIUS_M) * 180.0 / math.pi
        longitude += (
            (east * STEP_SECONDS / (EARTH_RADIUS_M * math.cos(math.radians(latitude))))
            * 180.0
            / math.pi
        )
    return track


def distance_m(first: tuple[float, float], second: tuple[float, float]) -> float:
    lat1, lon1 = math.radians(first[0]), math.radians(first[1])
    lat2, lon2 = math.radians(second[0]), math.radians(second[1])
    haversine = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(haversine))


def bearing_deg(first: tuple[float, float], second: tuple[float, float]) -> float:
    lat1, lon1 = math.radians(first[0]), math.radians(first[1])
    lat2, lon2 = math.radians(second[0]), math.radians(second[1])
    delta = lon2 - lon1
    y = math.sin(delta) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(delta)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def road_route(
    start: tuple[float, float], end: tuple[float, float]
) -> tuple[list[tuple[float, float]], list[dict[str, object]]]:
    """A driving route from the launch field to the landing field.

    Fetched once at authoring time rather than at runtime: the simulator has to
    work with no network, which is the situation it exists to rehearse.
    """
    url = (
        "https://router.project-osrm.org/route/v1/driving/"
        f"{start[1]:.6f},{start[0]:.6f};{end[1]:.6f},{end[0]:.6f}"
        "?overview=full&geometries=geojson&steps=true"
    )
    with urllib.request.urlopen(url, timeout=30) as response:
        payload = json.load(response)
    if payload.get("code") != "Ok" or not payload.get("routes"):
        raise SystemExit(f"routing failed: {payload.get('code')}")
    route = payload["routes"][0]
    print(
        f"  road route: {route['distance'] / 1000:.1f} km, "
        f"{route['duration'] / 60:.0f} min driving"
    )
    maneuvers = []
    for leg in route.get("legs", []):
        for step in leg.get("steps", []):
            maneuver = step.get("maneuver", {})
            location = maneuver.get("location")
            kind = maneuver.get("type")
            # Depart and arrive are not decisions a driver makes at a junction,
            # and the inherited demo's manoeuvre list does not carry them.
            if not location or kind in (None, "depart", "arrive"):
                continue
            entry = {
                "type": kind,
                "latitude": round(location[1], 6),
                "longitude": round(location[0], 6),
            }
            if maneuver.get("modifier"):
                entry["modifier"] = maneuver["modifier"]
            if step.get("name"):
                entry["name"] = step["name"]
            if step.get("ref"):
                entry["ref"] = step["ref"]
            if kind == "roundabout" and step.get("maneuver", {}).get("exit"):
                entry["exit"] = step["maneuver"]["exit"]
            maneuvers.append(entry)
    print(f"  {len(maneuvers)} turn manoeuvres")
    return [(point[1], point[0]) for point in route["geometry"]["coordinates"]], maneuvers


def gpx_track(name: str, description: str, points: list[dict[str, float]]) -> str:
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="Balloon Crumbs" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
        "  <metadata>",
        f"    <name>{name}</name>",
        f"    <desc>{description}</desc>",
        "  </metadata>",
        "  <trk>",
        f"    <name>{name}</name>",
        "    <trkseg>",
    ]
    for point in points:
        lines.append(
            f'      <trkpt lat="{point["latitude"]:.6f}" lon="{point["longitude"]:.6f}">'
        )
        if "elevation" in point:
            lines.append(f'        <ele>{point["elevation"]:.1f}</ele>')
        lines.append("      </trkpt>")
    lines += ["    </trkseg>", "  </trk>", "</gpx>", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--no-network",
        action="store_true",
        help="Describe the flight without fetching the chase road route.",
    )
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parents[2]
    assets = root / "apps/mobile/assets/simulation"
    assets.mkdir(parents=True, exist_ok=True)

    track = fly()
    landing = (track[-1]["latitude"], track[-1]["longitude"])
    straight = distance_m(LAUNCH, landing)
    flown = sum(
        distance_m(
            (track[i - 1]["latitude"], track[i - 1]["longitude"]),
            (track[i]["latitude"], track[i]["longitude"]),
        )
        for i in range(1, len(track))
    )
    print(f"launch   {LAUNCH[0]:.5f}, {LAUNCH[1]:.5f}  (Ashton Court)")
    print(f"landing  {landing[0]:.5f}, {landing[1]:.5f}")
    print(
        f"  {straight / 1000:.2f} km from launch on a bearing of "
        f"{bearing_deg(LAUNCH, landing):.0f} degrees"
    )
    print(f"  {flown / 1000:.2f} km flown through the air over "
          f"{track[-1]['seconds'] / 60:.0f} minutes")
    print(f"  peak height {max(p['height'] for p in track):.0f} m above the launch field")

    (assets / "fiesta_balloon_flight.json").write_text(
        json.dumps(
            {
                "name": "Fiesta dawn ascent, 8 August 2026",
                "launch": {
                    "latitude": LAUNCH[0],
                    "longitude": LAUNCH[1],
                    "name": "Ashton Court",
                    "elevationMetres": LAUNCH_ELEVATION_M,
                },
                "windLayers": [
                    {"heightMetres": h, "fromDegrees": d, "speedKmh": s}
                    for h, d, s in WIND_LAYERS
                ],
                "source": (
                    "Open-Meteo, measured winds over Ashton Court for the dawn "
                    "mass ascent of Saturday 8 August 2026"
                ),
                "samples": [
                    {
                        "seconds": round(point["seconds"]),
                        "latitude": round(point["latitude"], 6),
                        "longitude": round(point["longitude"], 6),
                        "heightMetres": round(point["height"], 1),
                    }
                    for point in track
                ],
            },
            indent=2,
        )
        + "\n"
    )
    print(f"  wrote {len(track)} flight samples")

    (assets / "fiesta_balloon_flight.gpx").write_text(
        gpx_track(
            "Fiesta dawn ascent, 8 August 2026",
            "Balloon drift from Ashton Court on the measured winds of the "
            "Saturday dawn mass ascent. Altitude is the pilot's only control; "
            "the track curves where the balloon crosses a wind layer.",
            track,
        )
    )
    print(f"  wrote {len(track)} air track points")

    if args.no_network:
        print("  skipped the chase road route as asked")
        return 0

    road, maneuvers = road_route(LAUNCH, landing)
    # Bundled beside the route for the same reason the inherited demo bundles
    # its own: without them the chase gets "follow the line on the map" instead
    # of turn prompts, which is a worse demo than the one this replaced.
    (assets / "fiesta_chase_maneuvers.json").write_text(
        json.dumps(
            {
                "source": (
                    "OSRM navigation steps for Ashton Court to the landing "
                    "field at West Town, Backwell"
                ),
                "maneuvers": maneuvers,
            },
            indent=2,
        )
        + "\n"
    )
    (assets / "fiesta_chase_route.gpx").write_text(
        gpx_track(
            "Fiesta chase, Ashton Court to the landing field",
            "A driving route from the launch field to where the balloon comes "
            "down. The chase crew cannot follow the air track; they follow "
            "roads to meet it.",
            [{"latitude": lat, "longitude": lon} for lat, lon in road],
        )
    )
    print(f"  wrote {len(road)} road route points")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
