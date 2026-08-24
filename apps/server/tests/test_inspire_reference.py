from __future__ import annotations

import json
from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from balloon_crumbs_server.app import create_app
from balloon_crumbs_server.inspire import (
    InspireReferenceCatalogue,
    InspireReferenceQuery,
    InspireReferenceUnavailable,
    build_catalogue,
)


def _feature(inspire_id: str, longitude: float, latitude: float) -> dict[str, object]:
    return {
        "type": "Feature",
        "properties": {
            "INSPIREID": inspire_id,
            # A source conversion carrying an unexpected attribute must still
            # never turn this public geometry index into an owner directory.
            "ownerName": "must never be retained",
        },
        "geometry": {
            "type": "Polygon",
            "coordinates": [
                [
                    [longitude, latitude],
                    [longitude + 0.001, latitude],
                    [longitude + 0.001, latitude + 0.001],
                    [longitude, latitude + 0.001],
                    [longitude, latitude],
                ]
            ],
        },
    }


def _write_sequence(path: Path, *features: dict[str, object]) -> None:
    path.write_text("".join(f"{json.dumps(feature)}\n" for feature in features))


def test_build_and_bounded_query_expose_geometry_not_owner_data(tmp_path: Path) -> None:
    source = tmp_path / "somerset.geojsonseq"
    output = tmp_path / "current.sqlite"
    _write_sequence(
        source,
        _feature("inspire-near", -2.588, 51.454),
        _feature("inspire-far", -1.4, 52.0),
        _feature("inspire-near", -2.588, 51.454),
    )

    assert (
        build_catalogue(
            [source],
            output,
            dataset_date=date(2026, 8, 2),
            coverage="Bristol and Somerset regional index",
        )
        == 2
    )
    result = InspireReferenceCatalogue(output).query(
        InspireReferenceQuery(latitude=51.4545, longitude=-2.5879, radius_metres=500)
    )

    assert [feature["id"] for feature in result["features"]] == ["inspire-near"]
    assert "ownerName" not in json.dumps(result)
    assert result["metadata"]["datasetDate"] == "2026-08-02"
    assert result["metadata"]["coverage"] == "Bristol and Somerset regional index"
    assert result["metadata"]["registeredInterestsIncluded"] == ("registered freehold subset only")
    assert "does not identify an owner" in result["metadata"]["limitation"]
    assert len(result["metadata"]["attribution"]) == 2


def test_current_hmlr_complex_polygon_fits_bounded_mobile_response(tmp_path: Path) -> None:
    source = tmp_path / "complex.geojsonseq"
    output = tmp_path / "current.sqlite"
    feature = _feature("complex", -2.588, 51.454)
    ring = [
        [-2.588 + (index % 100) * 0.000001, 51.454 + (index // 100) * 0.000001]
        for index in range(5000)
    ]
    ring.append(ring[0])
    feature["geometry"] = {"type": "Polygon", "coordinates": [ring]}
    _write_sequence(source, feature)

    assert source.stat().st_size > 64 * 1024
    assert build_catalogue([source], output, dataset_date=date(2026, 8, 2)) == 1
    result = InspireReferenceCatalogue(output).query(
        InspireReferenceQuery(latitude=51.454, longitude=-2.588, radius_metres=500)
    )
    assert [item["id"] for item in result["features"]] == ["complex"]
    assert result["metadata"]["truncated"] is False


def test_catalogue_rejects_ambiguous_coverage_label(tmp_path: Path) -> None:
    source = tmp_path / "source.geojsonseq"
    _write_sequence(source, _feature("one", -2.588, 51.454))

    with pytest.raises(ValueError, match="Coverage"):
        build_catalogue(
            [source],
            tmp_path / "current.sqlite",
            dataset_date=date(2026, 8, 2),
            coverage=" ",
        )


def test_catalogue_replacement_and_removal_need_no_app_release(tmp_path: Path) -> None:
    source = tmp_path / "monthly.geojsonseq"
    output = tmp_path / "current.sqlite"
    catalogue = InspireReferenceCatalogue(output)
    query = InspireReferenceQuery(latitude=51.4545, longitude=-2.5879, radius_metres=500)

    _write_sequence(source, _feature("july", -2.588, 51.454))
    build_catalogue([source], output, dataset_date=date(2026, 7, 5))
    assert catalogue.query(query)["features"][0]["id"] == "july"

    _write_sequence(source, _feature("august", -2.588, 51.454))
    build_catalogue([source], output, dataset_date=date(2026, 8, 2))
    assert catalogue.query(query)["features"][0]["id"] == "august"

    output.unlink()
    with pytest.raises(InspireReferenceUnavailable):
        catalogue.query(query)


def test_outside_coverage_degrades_without_implying_unregistered_land(tmp_path: Path) -> None:
    source = tmp_path / "england.geojsonseq"
    output = tmp_path / "current.sqlite"
    _write_sequence(source, _feature("england", -2.588, 51.454))
    build_catalogue([source], output, dataset_date=date(2026, 8, 2))

    result = InspireReferenceCatalogue(output).query(
        InspireReferenceQuery(latitude=55.95, longitude=-3.19, radius_metres=500)
    )
    assert result["features"] == []
    assert result["metadata"]["available"] is False
    assert "Scotland" in result["metadata"]["limitation"]
    assert "does not mean land is unregistered" in result["metadata"]["limitation"]


def test_outside_installed_regional_index_is_reported_honestly(tmp_path: Path) -> None:
    source = tmp_path / "bristol.geojsonseq"
    output = tmp_path / "current.sqlite"
    _write_sequence(source, _feature("bristol", -2.588, 51.454))
    build_catalogue(
        [source],
        output,
        dataset_date=date(2026, 8, 2),
        coverage="Bristol regional index",
    )

    result = InspireReferenceCatalogue(output).query(
        InspireReferenceQuery(latitude=53.48, longitude=-2.24, radius_metres=500)
    )
    assert result["features"] == []
    assert result["metadata"]["available"] is False
    assert result["metadata"]["coverage"] == "Bristol regional index"
    assert "outside the installed" in result["metadata"]["limitation"]


def test_endpoint_is_bounded_and_unavailable_data_does_not_affect_health(
    settings, tmp_path: Path
) -> None:
    with TestClient(
        create_app(settings, inspire_catalogue=InspireReferenceCatalogue(None))
    ) as client:
        unavailable = client.get(
            "/api/v1/reference/inspire",
            params={"latitude": 51.45, "longitude": -2.58, "radiusMetres": 500},
        )
        assert unavailable.status_code == 503
        assert client.get("/health/live").status_code == 200
        assert (
            client.get(
                "/api/v1/reference/inspire",
                params={"latitude": 51.45, "longitude": -2.58, "radiusMetres": 2001},
            ).status_code
            == 400
        )

    source = tmp_path / "bristol.geojsonseq"
    output = tmp_path / "current.sqlite"
    _write_sequence(source, _feature("bristol", -2.588, 51.454))
    build_catalogue([source], output, dataset_date=date(2026, 8, 2))
    with TestClient(
        create_app(settings, inspire_catalogue=InspireReferenceCatalogue(output))
    ) as client:
        response = client.get(
            "/api/v1/reference/inspire",
            params={"latitude": 51.4545, "longitude": -2.5879, "radiusMetres": 500},
        )
        assert response.status_code == 200
        assert response.headers["content-type"].startswith("application/geo+json")
        assert response.json()["features"][0]["id"] == "bristol"
