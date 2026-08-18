"""The discovery API is withdrawn, and stays withdrawn.

Deleting routes is easy to half-do: an unused import or a stray decorator leaves
one endpoint answering, and nothing else fails. These assert on the running app
rather than on the source, so a route that comes back has to fail here first.

The tables the feature wrote to are deliberately still present — dropping them is
destructive and needs its own migration, and a preproduction deployment may hold
submitted suggestions. Unreachable is the state being asserted, not absent.
"""

from __future__ import annotations

WITHDRAWN_PATHS = [
    "/api/v1/discovery/features",
    "/api/v1/discovery/suggestions",
    "/api/v1/discovery/road-ratings",
    "/api/v1/admin/discovery/road-ratings",
    "/api/v1/admin/discovery/suggestions",
]


def test_no_discovery_route_is_mounted(client) -> None:
    mounted = [
        route.path for route in client.app.routes if "discovery" in getattr(route, "path", "")
    ]
    assert mounted == []


def test_discovery_paths_answer_404(client) -> None:
    # A withdrawn route must be absent, not merely refusing: a 401 or 503 would
    # mean the endpoint is still there waiting for a credential.
    for path in WITHDRAWN_PATHS:
        assert client.get(path).status_code == 404, path
        assert client.post(path, json={}).status_code == 404, path


def test_the_moderation_endpoint_is_gone_too(client) -> None:
    # Credentialed surface with a moderation queue behind it, kept alive for a
    # feature nothing could reach — the reason this was worth doing promptly.
    response = client.post(
        "/api/v1/admin/discovery/suggestions/any-id:moderate",
        json={"decision": "approve"},
    )
    assert response.status_code == 404


def test_road_ratings_is_no_longer_advertised(client) -> None:
    capabilities = client.get("/api/v1/compatibility").json()["capabilities"]
    assert "road-ratings-v1" not in capabilities
    # The surviving capabilities are untouched by the withdrawal.
    assert {"live-presence-v2", "membership-v1", "route-revisions-v1"} <= set(capabilities)
