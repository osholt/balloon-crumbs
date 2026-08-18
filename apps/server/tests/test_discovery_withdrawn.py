"""The discovery API is withdrawn, and stays withdrawn.

Deleting routes is easy to half-do: an unused import or a stray decorator leaves
one endpoint answering, and nothing else fails. These assert on the running app
rather than on the source, so a route that comes back has to fail here first.

The tables the feature wrote to are gone too, in migration 0011 — a separate,
irreversible decision taken after the routes came down, not alongside them.
"""

from __future__ import annotations

import pathlib
import re

from balloon_crumbs_server.models import Base

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


def test_no_discovery_table_survives_in_the_schema() -> None:
    # The relay creates its test schema from this metadata, so a discovery table
    # described here is a table every fresh deployment would still grow. The
    # routes going was the reversible half; this is the half that had to wait.
    assert [name for name in Base.metadata.tables if "discovery" in name] == []


def test_the_migration_chain_stays_linear() -> None:
    # Two migrations claiming the same `down_revision` gives Alembic multiple
    # heads, and the failure surfaces at deploy time on the server rather than
    # here. Cheap to assert while 0011 is being added.
    versions = pathlib.Path(__file__).resolve().parents[1] / "alembic" / "versions"
    revisions = {}
    for path in versions.glob("*.py"):
        source = path.read_text()
        revision = re.search(r'^revision: str = "([^"]+)"', source, re.M)
        down = re.search(r'^down_revision: str \| None = (?:"([^"]+)"|None)', source, re.M)
        assert revision and down, path.name
        revisions[revision.group(1)] = down.group(1)

    assert revisions["0011"] == "0010"
    parents = [parent for parent in revisions.values() if parent is not None]
    assert len(parents) == len(set(parents)), "a revision is claimed as parent twice"
    heads = set(revisions) - set(parents)
    assert heads == {"0011"}, heads
