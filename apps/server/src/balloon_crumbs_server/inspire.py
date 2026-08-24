from __future__ import annotations

import argparse
import json
import math
import os
import sqlite3
import tempfile
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

SOURCE_NAME = "HM Land Registry INSPIRE Index Polygons"
SOURCE_URL = "https://use-land-property-data.service.gov.uk/datasets/inspire"
CONDITIONS_URL = f"{SOURCE_URL}/#conditions"
LIMITATION = (
    "Indicative extent of a registered freehold property only. It is not an exact title "
    "boundary, does not identify an owner, does not include every tenure or unregistered land, "
    "and does not grant access or permission."
)
MAXIMUM_QUERY_FEATURES = 100
MAXIMUM_RESPONSE_GEOMETRY_BYTES = 256 * 1024
MAXIMUM_FEATURE_GEOMETRY_BYTES = 64 * 1024
MAXIMUM_FEATURE_POINTS = 20_000


class InspireReferenceUnavailable(RuntimeError):
    pass


@dataclass(frozen=True)
class InspireReferenceQuery:
    latitude: float
    longitude: float
    radius_metres: int


class InspireReferenceCatalogue:
    """Read-only, atomically replaceable HMLR INSPIRE spatial index."""

    def __init__(self, path: Path | None):
        self.path = path

    @property
    def configured(self) -> bool:
        return self.path is not None and self.path.is_file()

    def query(self, query: InspireReferenceQuery) -> dict[str, Any]:
        if not self.configured or self.path is None:
            raise InspireReferenceUnavailable("HMLR reference data is not installed")
        if not _covers_england_wales(query.latitude, query.longitude):
            return _outside_coverage_response()

        latitude_delta = query.radius_metres / 111_320
        longitude_scale = max(0.2, math.cos(math.radians(query.latitude)))
        longitude_delta = query.radius_metres / (111_320 * longitude_scale)
        west = query.longitude - longitude_delta
        east = query.longitude + longitude_delta
        south = query.latitude - latitude_delta
        north = query.latitude + latitude_delta

        try:
            connection = sqlite3.connect(f"{self.path.as_uri()}?mode=ro", uri=True)
            connection.execute("PRAGMA query_only = ON")
            metadata = dict(connection.execute("SELECT key, value FROM metadata"))
            rows = connection.execute(
                """
                SELECT p.inspire_id, p.geometry_json
                FROM polygon_bounds AS b
                JOIN polygons AS p ON p.id = b.id
                WHERE b.min_longitude <= ?
                  AND b.max_longitude >= ?
                  AND b.min_latitude <= ?
                  AND b.max_latitude >= ?
                ORDER BY p.inspire_id
                LIMIT ?
                """,
                (east, west, north, south, MAXIMUM_QUERY_FEATURES + 1),
            ).fetchall()
        except (sqlite3.DatabaseError, OSError) as error:
            raise InspireReferenceUnavailable("HMLR reference data could not be read") from error
        finally:
            if "connection" in locals():
                connection.close()

        try:
            dataset_date = date.fromisoformat(metadata["dataset_date"])
        except (KeyError, ValueError) as error:
            raise InspireReferenceUnavailable("HMLR reference metadata is invalid") from error

        features: list[dict[str, Any]] = []
        geometry_bytes = 0
        truncated = len(rows) > MAXIMUM_QUERY_FEATURES
        for inspire_id, geometry_json in rows[:MAXIMUM_QUERY_FEATURES]:
            encoded_size = len(geometry_json.encode())
            if geometry_bytes + encoded_size > MAXIMUM_RESPONSE_GEOMETRY_BYTES:
                truncated = True
                break
            try:
                geometry = json.loads(geometry_json)
            except json.JSONDecodeError:
                truncated = True
                continue
            geometry_bytes += encoded_size
            features.append(
                {
                    "type": "Feature",
                    "id": inspire_id,
                    "properties": {"inspireId": inspire_id},
                    "geometry": geometry,
                }
            )

        return {
            "type": "FeatureCollection",
            "features": features,
            "metadata": _metadata(dataset_date, truncated=truncated, coverage="England and Wales"),
        }


def _outside_coverage_response() -> dict[str, Any]:
    return {
        "type": "FeatureCollection",
        "features": [],
        "metadata": {
            "available": False,
            "coverage": "England and Wales only",
            "limitation": (
                "HM Land Registry does not supply this open INSPIRE dataset for Scotland or "
                "Northern Ireland. Absence also does not mean land is unregistered."
            ),
        },
    }


def _metadata(dataset_date: date, *, truncated: bool, coverage: str) -> dict[str, Any]:
    year = dataset_date.year
    return {
        "available": True,
        "source": SOURCE_NAME,
        "sourceUrl": SOURCE_URL,
        "conditionsUrl": CONDITIONS_URL,
        "datasetDate": dataset_date.isoformat(),
        "coverage": coverage,
        "registeredInterestsIncluded": "registered freehold subset only",
        "limitation": LIMITATION,
        "attribution": [
            "This information is subject to Crown copyright and database rights "
            f"{year} and is reproduced with the permission of HM Land Registry.",
            "The polygons (including the associated geometry, namely x, y co-ordinates) are "
            f"subject to Crown copyright and database rights {year} Ordnance Survey "
            "AC0000851063.",
        ],
        "truncated": truncated,
    }


def _covers_england_wales(latitude: float, longitude: float) -> bool:
    return 49.8 <= latitude <= 55.9 and -6.5 <= longitude <= 2.0


def build_catalogue(
    inputs: list[Path],
    output: Path,
    *,
    dataset_date: date,
) -> int:
    """Build from WGS84 GeoJSON Sequence, keeping no source attributes but the ID."""

    if not inputs:
        raise ValueError("At least one GeoJSON Sequence input is required")
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary_handle, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.",
        suffix=".tmp",
        dir=output.parent,
    )
    os.close(temporary_handle)
    temporary = Path(temporary_name)
    inserted = 0
    try:
        connection = sqlite3.connect(temporary)
        connection.executescript(
            """
            PRAGMA journal_mode = OFF;
            PRAGMA synchronous = OFF;
            CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT;
            CREATE TABLE polygons (
                id INTEGER PRIMARY KEY,
                inspire_id TEXT NOT NULL UNIQUE,
                geometry_json TEXT NOT NULL
            ) STRICT;
            CREATE VIRTUAL TABLE polygon_bounds USING rtree(
                id,
                min_longitude,
                max_longitude,
                min_latitude,
                max_latitude
            );
            """
        )
        connection.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)",
            [
                ("schema_version", "1"),
                ("dataset_date", dataset_date.isoformat()),
                ("source", SOURCE_NAME),
                ("source_url", SOURCE_URL),
            ],
        )
        for input_path in inputs:
            with input_path.open(encoding="utf-8") as source:
                for line_number, line in enumerate(source, start=1):
                    line = line.lstrip("\x1e").strip()
                    if not line:
                        continue
                    try:
                        feature = json.loads(line)
                        inspire_id, geometry, bounds = _normalise_feature(feature)
                    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as error:
                        raise ValueError(f"{input_path}:{line_number}: {error}") from error
                    geometry_json = json.dumps(geometry, separators=(",", ":"), allow_nan=False)
                    if len(geometry_json.encode()) > MAXIMUM_FEATURE_GEOMETRY_BYTES:
                        raise ValueError(f"{input_path}:{line_number}: geometry exceeds size limit")
                    cursor = connection.execute(
                        "INSERT OR IGNORE INTO polygons(inspire_id, geometry_json) VALUES (?, ?)",
                        (inspire_id, geometry_json),
                    )
                    if cursor.rowcount == 0:
                        continue
                    polygon_id = cursor.lastrowid
                    connection.execute(
                        "INSERT INTO polygon_bounds VALUES (?, ?, ?, ?, ?)",
                        (polygon_id, *bounds),
                    )
                    inserted += 1
        if inserted == 0:
            raise ValueError("The input contained no valid unique polygons")
        connection.execute("PRAGMA optimize")
        connection.commit()
        connection.close()
        os.chmod(temporary, 0o644)
        os.replace(temporary, output)
        return inserted
    finally:
        if "connection" in locals():
            connection.close()
        temporary.unlink(missing_ok=True)


def _normalise_feature(
    feature: dict[str, Any],
) -> tuple[str, dict[str, Any], tuple[float, float, float, float]]:
    if feature.get("type") != "Feature":
        raise ValueError("each line must be one GeoJSON Feature")
    properties = feature.get("properties")
    if not isinstance(properties, dict):
        raise ValueError("feature properties are required")
    inspire_id = next(
        (
            str(properties[key]).strip()
            for key in ("INSPIREID", "inspireId", "INSPIRE_ID", "inspire_id")
            if key in properties and str(properties[key]).strip()
        ),
        "",
    )
    if not inspire_id or len(inspire_id) > 160:
        raise ValueError("a bounded INSPIRE ID is required")
    geometry = feature.get("geometry")
    if not isinstance(geometry, dict) or geometry.get("type") not in {"Polygon", "MultiPolygon"}:
        raise ValueError("geometry must be Polygon or MultiPolygon")
    coordinates = geometry.get("coordinates")
    bounds = _coordinate_bounds(coordinates)
    return inspire_id, {"type": geometry["type"], "coordinates": coordinates}, bounds


def _coordinate_bounds(coordinates: Any) -> tuple[float, float, float, float]:
    points: list[tuple[float, float]] = []

    def visit(value: Any) -> None:
        if len(points) >= MAXIMUM_FEATURE_POINTS:
            raise ValueError("geometry has too many points")
        if (
            isinstance(value, list)
            and len(value) >= 2
            and all(
                isinstance(part, int | float) and not isinstance(part, bool) for part in value[:2]
            )
        ):
            longitude = float(value[0])
            latitude = float(value[1])
            if not math.isfinite(longitude) or not math.isfinite(latitude):
                raise ValueError("geometry contains a non-finite coordinate")
            if not (-7.0 <= longitude <= 2.2 and 49.5 <= latitude <= 56.2):
                raise ValueError("geometry is outside the England and Wales import bounds")
            points.append((longitude, latitude))
            return
        if not isinstance(value, list) or not value:
            raise ValueError("geometry has an invalid coordinate structure")
        for child in value:
            visit(child)

    visit(coordinates)
    if len(points) < 4:
        raise ValueError("geometry has too few points")
    longitudes = [point[0] for point in points]
    latitudes = [point[1] for point in points]
    return min(longitudes), max(longitudes), min(latitudes), max(latitudes)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build the Balloon Crumbs HMLR INSPIRE reference index."
    )
    parser.add_argument("inputs", nargs="+", type=Path, help="WGS84 GeoJSON Sequence files")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--dataset-date", required=True, type=date.fromisoformat)
    args = parser.parse_args()
    count = build_catalogue(args.inputs, args.output, dataset_date=args.dataset_date)
    print(f"Built {count} indicative INSPIRE polygons at {args.output}")


if __name__ == "__main__":
    main()
