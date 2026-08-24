from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from fastapi.testclient import TestClient

from balloon_crumbs_server.app import create_app
from balloon_crumbs_server.gpx import GpxValidationError, validate_gpx
from balloon_crumbs_server.models import RidePlan
from balloon_crumbs_server.schemas import ForecastPlanBoundary
from balloon_crumbs_server.service import PLAN_CODE_ALPHABET, PLAN_CODE_LENGTH, purge_expired

GPX_TWO_POINTS = """<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><name>Loop</name><trkseg>
<trkpt lat="51.5" lon="-0.1"></trkpt>
<trkpt lat="51.6" lon="-0.2"></trkpt>
</trkseg></trk></gpx>"""


def _forecast_plan(gpx: str = GPX_TWO_POINTS) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "id": "plan-2026-08-23",
        "name": "Sunday flight",
        "createdAt": "2026-08-23T06:00:00Z",
        "source": "Balloon Crumbs web planner",
        "launch": {
            "point": {"latitude": 51.5, "longitude": -2.6},
            "elevationMsl": 80,
            "datum": "wgs84Geoid",
        },
        "destination": {
            "point": {"latitude": 51.6, "longitude": -2.4},
            "toleranceMetres": 100,
        },
        "intendedLandingArea": {
            "centre": {"latitude": 51.6, "longitude": -2.4},
            "radiusMetres": 400,
            "updatedAt": "2026-08-23T06:00:00Z",
        },
        "forecastLanding": {"latitude": 51.599, "longitude": -2.401},
        "departure": {
            "selectedAt": "2026-08-23T07:00:00Z",
            "matchingWindowStart": "2026-08-23T06:55:00Z",
            "matchingWindowEnd": "2026-08-23T07:05:00Z",
        },
        "constraints": {
            "altitudeCeilingMsl": 1200,
            "maximumAscentRateMps": 3,
            "maximumDescentRateMps": 4,
            "minimumDurationMinutes": 10,
            "maximumDurationMinutes": 180,
        },
        "altitudeStages": [
            {
                "fraction": 0,
                "plannedAt": "2026-08-23T07:00:00Z",
                "altitudeMsl": 80,
                "changeRateMps": 0,
            },
            {
                "fraction": 1,
                "plannedAt": "2026-08-23T08:00:00Z",
                "altitudeMsl": 80,
                "changeRateMps": -1,
            },
        ],
        "plannedTrack": [
            {
                "latitude": 51.5,
                "longitude": -2.6,
                "altitudeMsl": 80,
                "elapsedSeconds": 0,
            },
            {
                "latitude": 51.599,
                "longitude": -2.401,
                "altitudeMsl": 80,
                "elapsedSeconds": 3600,
            },
        ],
        "landingEnvelope": [
            {"latitude": 51.59, "longitude": -2.41},
            {"latitude": 51.61, "longitude": -2.41},
            {"latitude": 51.60, "longitude": -2.39},
        ],
        "wind": {
            "provider": "Open-Meteo",
            "model": "UKMO seamless",
            "requestedAt": "2026-08-23T06:00:00Z",
            "validFrom": "2026-08-23T06:00:00Z",
            "validTo": "2026-08-24T06:00:00Z",
            "attribution": "Open-Meteo",
            "licence": "CC BY 4.0",
            "forecastOnly": True,
            "fieldDigest": "sha256:test",
        },
        "operationalBoundaries": [],
        "result": {
            "kind": "optimised",
            "reachesDestination": True,
            "missDistanceMetres": 42,
        },
        "gpxFallback": gpx,
    }


def _create(
    client,
    *,
    name: str | None = "Sunday loop",
    gpx: str = GPX_TWO_POINTS,
    forecast_plan: dict[str, Any] | None = None,
):
    body: dict[str, Any] = {"gpx": gpx}
    if name is not None:
        body["name"] = name
    if forecast_plan is not None:
        body["forecastPlan"] = forecast_plan
    return client.post("/api/v1/plans", json=body)


class TestValidateGpx:
    def test_valid_gpx_returns_point_count(self) -> None:
        assert validate_gpx(GPX_TWO_POINTS, maximum_bytes=1_000_000, maximum_points=1000) == 2

    def test_rejects_empty(self) -> None:
        with pytest.raises(GpxValidationError):
            validate_gpx("", maximum_bytes=1_000_000, maximum_points=1000)

    def test_rejects_oversized(self) -> None:
        with pytest.raises(GpxValidationError):
            validate_gpx(GPX_TWO_POINTS, maximum_bytes=10, maximum_points=1000)

    def test_rejects_doctype(self) -> None:
        with pytest.raises(GpxValidationError):
            validate_gpx(
                '<?xml version="1.0"?><!DOCTYPE gpx [<!ENTITY x "y">]><gpx></gpx>',
                maximum_bytes=1_000_000,
                maximum_points=1000,
            )

    def test_rejects_malformed_xml(self) -> None:
        with pytest.raises(GpxValidationError):
            validate_gpx("<gpx><trk>", maximum_bytes=1_000_000, maximum_points=1000)

    def test_rejects_wrong_root(self) -> None:
        with pytest.raises(GpxValidationError):
            validate_gpx("<kml></kml>", maximum_bytes=1_000_000, maximum_points=1000)

    def test_rejects_empty_geometry(self) -> None:
        with pytest.raises(GpxValidationError):
            validate_gpx("<gpx></gpx>", maximum_bytes=1_000_000, maximum_points=1000)

    def test_rejects_out_of_range_coordinate(self) -> None:
        with pytest.raises(GpxValidationError):
            validate_gpx(
                '<gpx><trk><trkseg><trkpt lat="500" lon="-0.1"></trkpt></trkseg></trk></gpx>',
                maximum_bytes=1_000_000,
                maximum_points=1000,
            )

    def test_rejects_over_point_limit(self) -> None:
        with pytest.raises(GpxValidationError):
            validate_gpx(GPX_TWO_POINTS, maximum_bytes=1_000_000, maximum_points=1)

    def test_counts_routes_and_waypoints_too(self) -> None:
        gpx = '<gpx><rte><rtept lat="1" lon="1"></rtept></rte><wpt lat="2" lon="2"></wpt></gpx>'
        assert validate_gpx(gpx, maximum_bytes=1_000_000, maximum_points=1000) == 2


def test_create_and_fetch_plan_round_trips(client) -> None:
    created = _create(client)
    assert created.status_code == 200
    body = created.json()
    assert len(body["code"]) == PLAN_CODE_LENGTH
    assert set(body["code"]) <= set(PLAN_CODE_ALPHABET)

    fetched = client.get(f"/api/v1/plans/{body['code']}")
    assert fetched.status_code == 200
    assert fetched.json()["gpx"] == GPX_TWO_POINTS
    assert fetched.json()["name"] == "Sunday loop"


def test_plan_without_a_name_round_trips(client) -> None:
    created = _create(client, name=None)
    assert created.status_code == 200

    fetched = client.get(f"/api/v1/plans/{created.json()['code']}")
    assert fetched.json()["name"] is None


def test_structured_forecast_plan_round_trips_with_gpx_fallback(client) -> None:
    forecast_plan = _forecast_plan()
    forecast_plan["futureAdditiveField"] = "ignored"
    created = _create(client, forecast_plan=forecast_plan)
    assert created.status_code == 200

    fetched = client.get(f"/api/v1/plans/{created.json()['code']}")
    assert fetched.status_code == 200
    assert fetched.json()["gpx"] == GPX_TWO_POINTS
    assert fetched.json()["forecastPlan"]["schemaVersion"] == 1
    assert fetched.json()["forecastPlan"]["constraints"]["altitudeCeilingMsl"] == 1200
    assert "futureAdditiveField" not in fetched.json()["forecastPlan"]


def test_structured_plan_rejects_unknown_schema_and_mismatched_fallback(client) -> None:
    future = _forecast_plan()
    future["schemaVersion"] = 2
    assert _create(client, forecast_plan=future).status_code == 400

    mismatched = _forecast_plan("<gpx>different</gpx>")
    response = _create(client, forecast_plan=mismatched)
    assert response.status_code == 400
    assert "fallback" in response.json()["error"].lower()


def test_structured_plan_rejects_empty_altitude_boundary(client) -> None:
    forecast_plan = _forecast_plan()
    boundary = {
        "id": "empty-altitude-band",
        "label": "Missing limits",
        "kind": "altitudeBand",
        "points": [],
        "source": "Pilot briefing",
        "updatedAt": "2026-08-23T06:00:00Z",
        "altitudeDatum": "wgs84Geoid",
    }
    forecast_plan["operationalBoundaries"] = [boundary]

    with pytest.raises(ValueError, match="at least one altitude limit"):
        ForecastPlanBoundary.model_validate(boundary)

    response = _create(client, forecast_plan=forecast_plan)

    assert response.status_code == 400
    assert response.json()["error"] == "Malformed plan request"


def test_unknown_plan_code_is_not_found(client) -> None:
    assert client.get("/api/v1/plans/ZZZZZZZZ").status_code == 404


def test_malformed_plan_code_is_not_found(client) -> None:
    assert client.get("/api/v1/plans/not-a-valid-code!!").status_code == 404


def test_create_rejects_invalid_gpx(client) -> None:
    response = _create(client, gpx="<kml></kml>")
    assert response.status_code == 400


def test_create_rejects_overlong_name(client) -> None:
    response = _create(client, name="x" * 201)
    assert response.status_code == 400


def test_plan_gpx_is_encrypted_at_rest(client) -> None:
    created = _create(client, forecast_plan=_forecast_plan())
    factory = client.app.state.session_factory
    with factory() as session:
        stored = session.get(RidePlan, created.json()["code"])
        assert stored is not None
        assert b"51.5" not in stored.gpx_ciphertext
        assert b"Loop" not in stored.gpx_ciphertext
        assert b"altitudeCeilingMsl" not in stored.gpx_ciphertext


def test_expired_plan_is_not_found_and_purge_removes_it(client) -> None:
    created = _create(client)
    code = created.json()["code"]
    factory = client.app.state.session_factory
    with factory() as session:
        plan = session.get(RidePlan, code)
        plan.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        session.commit()

    assert client.get(f"/api/v1/plans/{code}").status_code == 404

    with factory() as session:
        purge_expired(session)
    with factory() as session:
        assert session.get(RidePlan, code) is None


def test_plan_create_is_rate_limited(settings) -> None:
    limited = settings.model_copy(update={"plan_create_rate_limit_requests": 1})
    with TestClient(create_app(limited)) as client:
        assert _create(client).status_code == 200
        assert _create(client).status_code == 429


def test_plan_lookup_is_rate_limited(settings) -> None:
    limited = settings.model_copy(update={"plan_lookup_rate_limit_requests": 1})
    with TestClient(create_app(limited)) as client:
        created = _create(client)
        code = created.json()["code"]
        assert client.get(f"/api/v1/plans/{code}").status_code == 200
        assert client.get(f"/api/v1/plans/{code}").status_code == 429


def test_oversized_plan_upload_is_rejected(settings) -> None:
    tiny = settings.model_copy(update={"maximum_plan_bytes": 64})
    with TestClient(create_app(tiny)) as client:
        response = _create(client)
        assert response.status_code == 413
