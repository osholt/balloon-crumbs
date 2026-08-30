from __future__ import annotations

from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient
from sqlalchemy import select

from balloon_crumbs_server.app import create_app
from balloon_crumbs_server.models import CrewRoom

from .conftest import ride_token

SECRET_ONE = "0123456789abcdef0123456789abcdef"
SECRET_TWO = "fedcba9876543210fedcba9876543210"
RESOLVE_ONE = "resolve-token-operation-one"
RESOLVE_TWO = "resolve-token-operation-two"


def _operation(
    ride_id: str = "operation-one",
    ride_code: str = "123456",
    secret: str = SECRET_ONE,
    resolve_token: str = RESOLVE_ONE,
) -> dict[str, str]:
    return {
        "rideId": ride_id,
        "rideCode": ride_code,
        "inviteSecret": secret,
        "resolveToken": resolve_token,
    }


def _create(client, *, alias: str = "TUCKER"):
    operation = _operation()
    return client.post(
        "/api/v1/crew-rooms/create",
        json={
            "alias": alias,
            "deviceId": "room-device-owner",
            "displayName": "Oliver",
            "operation": operation,
        },
        headers={
            "authorization": f"Bearer {ride_token(operation['rideId'], operation['inviteSecret'])}"
        },
    )


def _auth(created: dict[str, object], *, device_id: str = "room-device-owner"):
    return {
        "alias": created["alias"],
        "deviceId": device_id,
        "deviceCredential": created["deviceCredential"],
    }


def test_room_alias_is_not_a_credential_and_stays_encrypted_at_rest(client, settings) -> None:
    response = _create(client, alias="tucker")
    assert response.status_code == 201
    created = response.json()
    assert created["alias"] == "TUCKER"
    assert created["owner"] is True
    assert created["operation"] == _operation()
    assert created["operationGeneration"] == 1

    # There is deliberately no alias-only operation lookup. Guessing a valid
    # alias with an invented returning credential reveals the same 404 as a
    # room that does not exist.
    guessed = client.post(
        "/api/v1/crew-rooms/open",
        json={
            "alias": "TUCKER",
            "deviceId": "guessed-device",
            "deviceCredential": "crd1_" + "A" * 43,
        },
    )
    missing = client.post(
        "/api/v1/crew-rooms/open",
        json={
            "alias": "ABSENT",
            "deviceId": "guessed-device",
            "deviceCredential": "crd1_" + "A" * 43,
        },
    )
    assert guessed.status_code == missing.status_code == 404
    assert guessed.json() == missing.json() == {"error": "Crew room is not available"}

    factory = client.app.state.session_factory
    with factory() as session:
        stored = session.scalar(select(CrewRoom))
        assert stored is not None
        assert b"TUCKER" not in stored.alias_ciphertext
        assert SECRET_ONE.encode() not in stored.operation_ciphertext
        assert RESOLVE_ONE.encode() not in stored.operation_ciphertext


def test_private_invite_enrols_a_returning_device_and_qr_operation(client) -> None:
    created = _create(client).json()
    joined = client.post(
        "/api/v1/crew-rooms/join",
        json={
            "alias": "TUCKER",
            "inviteToken": created["inviteToken"],
            "deviceId": "room-device-chaser",
            "displayName": "Nigel",
        },
    )
    assert joined.status_code == 200
    member = joined.json()
    assert member["owner"] is False
    assert member["operation"] == _operation()
    assert member["deviceCredential"].startswith("crd1_")

    reopened = client.post(
        "/api/v1/crew-rooms/open",
        json=_auth(member, device_id="room-device-chaser"),
    )
    assert reopened.status_code == 200
    assert reopened.json()["operation"] == _operation()


def test_device_authority_round_trips_when_room_starts_a_fresh_operation(client) -> None:
    authority_root = "A" * 43
    first_operation = {
        **_operation(),
        "authorityRootPublicKey": authority_root,
    }
    created_response = client.post(
        "/api/v1/crew-rooms/create",
        json={
            "alias": "TUCKER",
            "deviceId": "room-device-owner",
            "displayName": "Oliver",
            "operation": first_operation,
        },
        headers={
            "authorization": (
                f"Bearer {ride_token(first_operation['rideId'], first_operation['inviteSecret'])}"
            )
        },
    )
    assert created_response.status_code == 201
    created = created_response.json()

    reopened = client.post("/api/v1/crew-rooms/open", json=_auth(created))
    assert reopened.status_code == 200
    assert reopened.json()["operation"] == first_operation

    second_operation = {
        **_operation(
            ride_id="operation-two",
            ride_code="654321",
            secret=SECRET_TWO,
            resolve_token=RESOLVE_TWO,
        ),
        "authorityRootPublicKey": "B" * 43,
    }
    restarted = client.post(
        "/api/v1/crew-rooms/start-operation",
        json={**_auth(created), "operation": second_operation},
        headers={
            "authorization": (
                f"Bearer {ride_token(second_operation['rideId'], second_operation['inviteSecret'])}"
            )
        },
    )
    assert restarted.status_code == 200
    assert restarted.json()["operation"] == second_operation


def test_reusing_alias_starts_a_fresh_isolated_operation(client) -> None:
    first = _create(client).json()
    second_operation = _operation(
        ride_id="operation-two",
        ride_code="654321",
        secret=SECRET_TWO,
        resolve_token=RESOLVE_TWO,
    )
    second_bearer = ride_token(second_operation["rideId"], second_operation["inviteSecret"])
    started = client.post(
        "/api/v1/crew-rooms/start-operation",
        json={**_auth(first), "operation": second_operation},
        headers={"authorization": f"Bearer {second_bearer}"},
    )
    assert started.status_code == 200
    current = started.json()
    assert current["alias"] == "TUCKER"
    assert current["operationGeneration"] == 2
    assert current["operation"] == second_operation
    assert current["inviteToken"] != first["inviteToken"]

    # The previous invitation cannot enrol a device into the new operation.
    old_invite = client.post(
        "/api/v1/crew-rooms/join",
        json={
            "alias": "TUCKER",
            "inviteToken": first["inviteToken"],
            "deviceId": "late-device",
            "displayName": "Late join",
        },
    )
    assert old_invite.status_code == 404


def test_owner_can_list_transfer_rename_revoke_and_delete(client) -> None:
    owner = _create(client).json()
    joined_response = client.post(
        "/api/v1/crew-rooms/join",
        json={
            "alias": "TUCKER",
            "inviteToken": owner["inviteToken"],
            "deviceId": "room-device-chaser",
            "displayName": "Nigel",
        },
    )
    member = joined_response.json()

    devices = client.post("/api/v1/crew-rooms/devices", json=_auth(owner))
    assert devices.status_code == 200
    assert [(item["displayName"], item["owner"]) for item in devices.json()["devices"]] == [
        ("Oliver", True),
        ("Nigel", False),
    ]

    transferred = client.post(
        "/api/v1/crew-rooms/transfer",
        json={**_auth(owner), "targetDeviceId": "room-device-chaser"},
    )
    assert transferred.status_code == 204
    old_owner_rename = client.post(
        "/api/v1/crew-rooms/rename",
        json={**_auth(owner), "newAlias": "GRAVES"},
    )
    assert old_owner_rename.status_code == 404

    renamed = client.post(
        "/api/v1/crew-rooms/rename",
        json={**_auth(member, device_id="room-device-chaser"), "newAlias": "GRAVES"},
    )
    assert renamed.status_code == 200
    assert renamed.json()["alias"] == "GRAVES"
    member["alias"] = "GRAVES"

    revoked = client.post(
        "/api/v1/crew-rooms/revoke-device",
        json={
            **_auth(member, device_id="room-device-chaser"),
            "targetDeviceId": "room-device-owner",
        },
    )
    assert revoked.status_code == 204
    owner["alias"] = "GRAVES"
    assert client.post("/api/v1/crew-rooms/open", json=_auth(owner)).status_code == 404

    deleted = client.post(
        "/api/v1/crew-rooms/delete",
        json=_auth(member, device_id="room-device-chaser"),
    )
    assert deleted.status_code == 204
    assert (
        client.post(
            "/api/v1/crew-rooms/open",
            json=_auth(member, device_id="room-device-chaser"),
        ).status_code
        == 404
    )


def test_expired_operation_does_not_reappear_as_active(client) -> None:
    created = _create(client).json()
    factory = client.app.state.session_factory
    with factory() as session, session.begin():
        room = session.scalar(select(CrewRoom))
        assert room is not None
        room.operation_expires_at = datetime.now(UTC) - timedelta(seconds=1)

    opened = client.post("/api/v1/crew-rooms/open", json=_auth(created))
    assert opened.status_code == 200
    assert opened.json()["operation"] is None


def test_crew_room_requests_are_rate_limited(settings) -> None:
    limited = settings.model_copy(update={"crew_room_rate_limit_requests": 1})
    with TestClient(create_app(limited)) as client:
        first = client.post(
            "/api/v1/crew-rooms/open",
            json={
                "alias": "TUCKER",
                "deviceId": "some-device",
                "deviceCredential": "crd1_" + "A" * 43,
            },
        )
        second = client.post(
            "/api/v1/crew-rooms/open",
            json={
                "alias": "TUCKER",
                "deviceId": "some-device",
                "deviceCredential": "crd1_" + "A" * 43,
            },
        )
    assert first.status_code == 404
    assert second.status_code == 429
