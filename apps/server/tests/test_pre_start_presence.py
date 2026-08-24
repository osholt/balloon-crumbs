from __future__ import annotations

import base64
import json
from datetime import UTC, datetime, timedelta

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from sqlalchemy import func, select

from balloon_crumbs_server.crypto import CursorCodec, DataCipher
from balloon_crumbs_server.models import PreStartPosition, StoredEvent
from balloon_crumbs_server.schemas import PresenceSyncRequest
from balloon_crumbs_server.service import RelayService

from .conftest import event, ride_token

SECRET = "0123456789abcdef0123456789abcdef"


def _b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode().rstrip("=")


def _authority_proof(
    *,
    ride_id: str,
    rider_id: str,
    position: dict | None,
    clear: bool,
    signed_at: datetime,
    seed: bytes,
) -> dict:
    signed_at_milliseconds = int(signed_at.timestamp() * 1000)
    body = {
        "rideId": ride_id,
        "riderId": rider_id,
        "signedAtMilliseconds": signed_at_milliseconds,
        "clear": clear,
        "position": position,
    }
    challenge = "balloon-crumbs-live-presence-v1\n" + json.dumps(
        body,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    private_key = Ed25519PrivateKey.from_private_bytes(seed)
    return {
        "authorityVersion": 1,
        "signedAtMilliseconds": signed_at_milliseconds,
        "devicePublicKey": _b64(private_key.public_key().public_bytes_raw()),
        "deviceSignature": _b64(private_key.sign(challenge.encode())),
    }


def _position(
    latitude: float,
    *,
    recorded_at: datetime | None = None,
    display_name: str = "Alex",
) -> dict:
    return {
        "displayName": display_name,
        "role": "rider",
        "motorcycleStyle": "adventure",
        "riderColor": "blue",
        "sample": {
            "position": {"latitude": latitude, "longitude": -2.4},
            "recordedAt": (recorded_at or datetime.now(UTC)).isoformat().replace("+00:00", "Z"),
            "accuracyMeters": 4,
            "speedMetersPerSecond": 0,
            "headingDegrees": 90,
        },
    }


def _presence(client, ride_id: str, device_id: str, **body):
    return client.post(
        f"/api/v1/rides/{ride_id}/presence:sync",
        json={"protocolVersion": 1, "deviceId": device_id, **body},
        headers={
            "authorization": f"Bearer {ride_token(ride_id, SECRET)}",
            "x-balloon-crumbs-device": device_id,
            "x-tailendcharlie-protocol": "1",
            "x-tailendcharlie-capabilities": "pre-start-presence-v1",
        },
    )


def test_presence_replaces_latest_position_without_storing_events(client, synchronize) -> None:
    ride_id = "ride-presence"
    assert synchronize(client, ride_id=ride_id, secret=SECRET).status_code == 200

    first = _presence(client, ride_id, "rider-a", position=_position(51.0))
    second = _presence(client, ride_id, "rider-a", position=_position(51.1))
    observed = _presence(client, ride_id, "leader")

    assert first.status_code == 200
    assert second.status_code == 200
    positions = observed.json()["positions"]
    assert len(positions) == 1
    assert positions[0]["riderId"] == "rider-a"
    assert positions[0]["craftStyle"] == "adventure"
    assert positions[0]["motorcycleStyle"] == "adventure"
    assert positions[0]["sample"]["position"]["latitude"] == 51.1
    with client.app.state.session_factory() as session:
        assert session.scalar(select(func.count(StoredEvent.sequence))) == 0
        assert session.scalar(select(func.count()).select_from(PreStartPosition)) == 1


def test_presence_accepts_the_canonical_craft_style_without_the_legacy_key(
    client, synchronize
) -> None:
    ride_id = "ride-canonical-craft-style"
    assert synchronize(client, ride_id=ride_id, secret=SECRET).status_code == 200
    position = _position(51.0)
    position["craftStyle"] = position.pop("motorcycleStyle")
    position["riderSymbol"] = "initials:v1::white"

    published = _presence(client, ride_id, "rider-a", position=position)
    observed = _presence(client, ride_id, "leader")

    assert published.status_code == 200
    assert observed.status_code == 200
    assert observed.json()["positions"][0]["craftStyle"] == "adventure"
    assert observed.json()["positions"][0]["riderSymbol"] == "initials:v1::white"
    assert observed.json()["positions"][0]["motorcycleStyle"] == "adventure"


def test_presence_is_shared_between_relay_processes(client, settings, synchronize) -> None:
    ride_id = "ride-presence-shared"
    assert synchronize(client, ride_id=ride_id, secret=SECRET).status_code == 200
    assert _presence(client, ride_id, "rider-a", position=_position(51.2)).status_code == 200

    second_process = RelayService(
        settings,
        DataCipher(settings.decoded_key("data_encryption_key")),
        CursorCodec(settings.decoded_key("cursor_signing_key")),
    )
    with client.app.state.session_factory() as session:
        observed = second_process.synchronize_pre_start_presence(
            session,
            ride_id=ride_id,
            bearer_token=ride_token(ride_id, SECRET),
            device_header="leader",
            request=PresenceSyncRequest(
                protocolVersion=1,
                deviceId="leader",
            ),
        )

    assert len(observed["positions"]) == 1
    assert observed["positions"][0]["riderId"] == "rider-a"
    assert observed["positions"][0]["sample"]["position"]["latitude"] == 51.2


def test_presence_expires_on_ttl_and_a_legacy_client_reads_nothing_after_start(
    client, synchronize
) -> None:
    """The legacy read contract is preserved without destroying stored rows.

    A build that only advertises ``pre-start-presence-v1`` still sees nothing
    once the ride has started, but the rows survive for live-presence peers. An
    older phone in a mixed group must not be able to blank a newer one.
    """
    ride_id = "ride-presence-lifecycle"
    assert synchronize(client, ride_id=ride_id, secret=SECRET).status_code == 200
    assert _presence(client, ride_id, "rider-a", position=_position(51.0)).json()["positions"]

    service = client.app.state.service
    with client.app.state.session_factory() as session:
        expired = service.synchronize_pre_start_presence(
            session,
            ride_id=ride_id,
            bearer_token=ride_token(ride_id, SECRET),
            device_header="leader",
            request=PresenceSyncRequest(
                protocolVersion=1,
                deviceId="leader",
            ),
            now=datetime.now(UTC)
            + timedelta(seconds=client.app.state.settings.pre_start_presence_ttl_seconds + 1),
        )
    assert expired["positions"] == []

    assert _presence(client, ride_id, "rider-a", position=_position(51.0)).status_code == 200
    started = event(
        ride_id,
        "ride-started",
        event_type="rideStarted",
        payload={"leaderRiderId": "leader"},
    )
    assert (
        synchronize(
            client,
            ride_id=ride_id,
            secret=SECRET,
            device_id="leader",
            events=[started],
        ).status_code
        == 200
    )
    with client.app.state.session_factory() as session:
        assert session.scalar(select(func.count()).select_from(PreStartPosition)) == 1
    legacy = _presence(client, ride_id, "leader").json()
    assert legacy["positions"] == []
    assert legacy["phase"] == "started"


def test_presence_requires_matching_authenticated_device(client, synchronize) -> None:
    ride_id = "ride-presence-auth"
    assert synchronize(client, ride_id=ride_id, secret=SECRET).status_code == 200

    response = client.post(
        f"/api/v1/rides/{ride_id}/presence:sync",
        json={"protocolVersion": 1, "deviceId": "rider-a"},
        headers={
            "authorization": f"Bearer {ride_token(ride_id, SECRET)}",
            "x-balloon-crumbs-device": "rider-b",
        },
    )

    assert response.status_code == 400


def test_device_authority_flight_requires_and_verifies_live_position_proof(
    client, synchronize
) -> None:
    ride_id = "ride-device-presence"
    now = datetime.now(UTC)
    seed = bytes(range(32))
    private_key = Ed25519PrivateKey.from_private_bytes(seed)
    public_key = _b64(private_key.public_key().public_bytes_raw())
    created = event(ride_id, "ride-created", device_id="pilot")
    created.update(
        {
            "schemaVersion": 2,
            "devicePublicKey": public_key,
            "deviceSignature": "A" * 86,
        }
    )
    assert (
        synchronize(
            client,
            ride_id=ride_id,
            secret=SECRET,
            device_id="pilot",
            events=[created],
        ).status_code
        == 200
    )

    position = _position(51.2, recorded_at=now)
    without_proof = _presence(client, ride_id, "pilot", position=position)
    assert without_proof.status_code == 403
    proof = _authority_proof(
        ride_id=ride_id,
        rider_id="pilot",
        position=position,
        clear=False,
        signed_at=now,
        seed=seed,
    )
    published = _presence(client, ride_id, "pilot", position=position, **proof)
    assert published.status_code == 200
    assert published.json()["positions"][0]["devicePublicKey"] == public_key

    tampered = _position(51.3, recorded_at=now)
    rejected = _presence(client, ride_id, "pilot", position=tampered, **proof)
    assert rejected.status_code == 403


def test_five_devices_survive_a_45_minute_pre_launch_without_ghosts(client, synchronize) -> None:
    """The long field lobby is a heartbeat test, not a sleep in CI.

    Five synthetic devices publish every 30 seconds for the observed 45-minute
    setup window. Reusing one installation id after a process restart must
    replace that row rather than invent a sixth crew member.
    """

    ride_id = "synthetic-long-pre-launch"
    bearer_token = ride_token(ride_id, SECRET)
    assert synchronize(client, ride_id=ride_id, secret=SECRET).status_code == 200
    service = client.app.state.service
    session_factory = client.app.state.session_factory
    start = datetime(2026, 8, 24, 9, tzinfo=UTC)
    devices = [f"synthetic-device-{index}" for index in range(5)]

    def publish(device_id: str, at: datetime, *, restarted: bool = False) -> dict:
        index = devices.index(device_id)
        request = PresenceSyncRequest(
            protocolVersion=1,
            deviceId=device_id,
            position=_position(
                52.0 + index * 0.001,
                recorded_at=at,
                display_name=(
                    f"Synthetic crew {index} (restarted)"
                    if restarted
                    else f"Synthetic crew {index}"
                ),
            ),
        )
        with session_factory() as session:
            return service.synchronize_pre_start_presence(
                session,
                ride_id=ride_id,
                bearer_token=bearer_token,
                device_header=device_id,
                request=request,
                live_presence=True,
                now=at,
            )

    latest: dict = {}
    for heartbeat in range(91):
        at = start + timedelta(seconds=heartbeat * 30)
        for device_id in devices:
            latest = publish(device_id, at)
        assert len(latest["positions"]) == 5
        assert {item["riderId"] for item in latest["positions"]} == set(devices)

    restarted_at = start + timedelta(minutes=45, seconds=5)
    latest = publish(devices[2], restarted_at, restarted=True)

    assert len(latest["positions"]) == 5
    restarted = next(item for item in latest["positions"] if item["riderId"] == devices[2])
    assert restarted["displayName"].endswith("(restarted)")
    with session_factory() as session:
        assert (
            session.scalar(
                select(func.count())
                .select_from(PreStartPosition)
                .where(PreStartPosition.ride_id == ride_id)
            )
            == 5
        )
