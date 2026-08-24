from __future__ import annotations

import base64
import hmac
import json
import re
import secrets
import threading
import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from .config import Settings
from .crypto import DataCipher, base64url, token_hash
from .models import ObserverGrant, Ride, StoredEvent
from .schemas import CreateObserverGrantRequest, PublishObserverSnapshotRequest
from .service import RelayServiceError

IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
MANAGEMENT_TOKEN = re.compile(r"^om1_[A-Za-z0-9_-]{43}$")
PUBLISHER_TOKEN = re.compile(r"^op1_[A-Za-z0-9_-]{43}$")
OBSERVER_TOKEN = re.compile(r"^ro1_[A-Za-z0-9_-]{43}$")
RIDE_TOKEN = re.compile(r"^rr1_[A-Za-z0-9_-]{43}$")
_CREATE_LOCKS = tuple(threading.Lock() for _ in range(64))


def create_observer_grant(
    session: Session,
    *,
    settings: Settings,
    cipher: DataCipher,
    ride_id: str,
    bearer_token: str,
    request: CreateObserverGrantRequest,
    now: datetime | None = None,
) -> tuple[ObserverGrant, str, str, str]:
    now = now or datetime.now(UTC)
    label = " ".join(request.label.split())
    if not label:
        raise RelayServiceError(400, "Observer label is required")
    lock_index = int.from_bytes(ride_id.encode()[:8].ljust(8, b"\0")) % len(_CREATE_LOCKS)
    with _CREATE_LOCKS[lock_index]:
        with session.begin():
            ride = _authenticated_ride(
                session,
                ride_id,
                bearer_token,
                lock_for_update=True,
            )
            if request.scope == "group":
                _verify_group_pilot_authorization(
                    session,
                    cipher=cipher,
                    ride=ride,
                    request=request,
                    now=now,
                )
            active_count = (
                session.scalar(
                    select(func.count(ObserverGrant.id)).where(
                        ObserverGrant.ride_id == ride_id,
                        ObserverGrant.revoked_at.is_(None),
                        ObserverGrant.expires_at > now,
                    )
                )
                or 0
            )
            if active_count >= settings.maximum_observer_grants_per_ride:
                raise RelayServiceError(409, "Active observer limit reached")
            management_token = _new_token("om1")
            publisher_token = _new_token("op1")
            observer_token = _new_token("ro1")
            expires_at = min(
                now + timedelta(minutes=request.durationMinutes),
                _as_utc(ride.delete_after),
            )
            grant = ObserverGrant(
                id=str(uuid.uuid4()),
                ride_id=ride_id,
                label=label,
                scope=request.scope,
                precision=request.precision,
                management_token_hash=token_hash(management_token),
                publisher_token_hash=token_hash(publisher_token),
                observer_token_hash=token_hash(observer_token),
                created_at=now,
                expires_at=expires_at,
            )
            session.add(grant)
            session.flush()
            return grant, management_token, publisher_token, observer_token


def get_managed_observer_grant(
    session: Session,
    *,
    grant_id: str,
    management_token: str,
    now: datetime | None = None,
) -> ObserverGrant:
    return _authorized_grant(
        session,
        grant_id=grant_id,
        supplied_token=management_token,
        pattern=MANAGEMENT_TOKEN,
        expected_hash=lambda grant: grant.management_token_hash,
        now=now,
    )


def revoke_observer_grant(
    session: Session,
    *,
    grant_id: str,
    management_token: str,
    now: datetime | None = None,
) -> None:
    now = now or datetime.now(UTC)
    if not MANAGEMENT_TOKEN.fullmatch(management_token):
        raise RelayServiceError(404, "Observer access is unavailable")
    with session.begin():
        result = session.execute(
            update(ObserverGrant)
            .where(
                ObserverGrant.id == grant_id,
                ObserverGrant.management_token_hash == token_hash(management_token),
                ObserverGrant.revoked_at.is_(None),
                ObserverGrant.expires_at > now,
            )
            .values(
                revoked_at=now,
                snapshot_ciphertext=None,
                snapshot_updated_at=None,
                snapshot_version_at=None,
            )
        )
        if result.rowcount != 1:
            raise RelayServiceError(404, "Observer access is unavailable")


def publish_observer_snapshot(
    session: Session,
    *,
    cipher: DataCipher,
    grant_id: str,
    publisher_token: str,
    request: PublishObserverSnapshotRequest,
    now: datetime | None = None,
) -> None:
    now = now or datetime.now(UTC)
    if request.snapshotGeneratedAt > now + timedelta(minutes=2):
        raise RelayServiceError(400, "Observer snapshot is from the future")
    if request.statusUpdatedAt > now + timedelta(minutes=2):
        raise RelayServiceError(400, "Observer status is from the future")
    if request.assistanceUpdatedAt > now + timedelta(minutes=2):
        raise RelayServiceError(400, "Observer assistance status is from the future")
    if request.position is not None:
        if request.position.recordedAt > now + timedelta(minutes=2):
            raise RelayServiceError(400, "Observer position is from the future")
        if request.position.recordedAt < now - timedelta(hours=24):
            raise RelayServiceError(400, "Observer position is too old")
    for participant in request.participants:
        if participant.position is None:
            continue
        if participant.position.recordedAt > now + timedelta(minutes=2):
            raise RelayServiceError(400, "Observer participant position is from the future")
        if participant.position.recordedAt < now - timedelta(hours=24):
            raise RelayServiceError(400, "Observer participant position is too old")
    if request.assistance is not None:
        if request.assistance.reportedAt > now + timedelta(minutes=2):
            raise RelayServiceError(400, "Observer assistance status is from the future")
        if request.assistance.reportedAt < now - timedelta(hours=2):
            raise RelayServiceError(400, "Observer assistance status is too old")
    if not PUBLISHER_TOKEN.fullmatch(publisher_token):
        raise RelayServiceError(404, "Observer access is unavailable")
    with session.begin():
        grant = _authorized_grant(
            session,
            grant_id=grant_id,
            supplied_token=publisher_token,
            pattern=PUBLISHER_TOKEN,
            expected_hash=lambda value: value.publisher_token_hash,
            now=now,
            lock_for_update=True,
        )
        if grant.scope != request.scope:
            raise RelayServiceError(409, "Observer snapshot scope does not match grant")
        if (
            grant.snapshot_version_at is not None
            and _as_utc(grant.snapshot_version_at) >= request.snapshotGeneratedAt
        ):
            raise RelayServiceError(409, "Observer snapshot is older than current state")

        current: dict[str, Any] = {}
        if grant.snapshot_ciphertext is not None:
            try:
                decrypted = cipher.decrypt_json(
                    grant.snapshot_ciphertext,
                    associated_data=_snapshot_aad(grant.id),
                )
            except ValueError as error:
                raise RelayServiceError(500, "Stored observer state is invalid") from error
            if not isinstance(decrypted, dict):
                raise RelayServiceError(500, "Stored observer state is invalid")
            current = decrypted

        incoming = request.model_dump(mode="json")
        if grant.precision == "reduced":
            incoming = _reduce_snapshot_precision(incoming)
        merged = {
            "scope": grant.scope,
            "subjectName": incoming["subjectName"],
            "rideStatus": current.get("rideStatus", "waiting"),
            "statusUpdatedAt": current.get("statusUpdatedAt"),
            "position": current.get("position"),
            "participants": current.get("participants", []),
            "route": current.get("route"),
            "assistanceUpdatedAt": current.get("assistanceUpdatedAt"),
            "assistance": current.get("assistance"),
        }
        current_status_at = _timestamp(current.get("statusUpdatedAt"))
        if current_status_at is None or request.statusUpdatedAt >= current_status_at:
            merged["rideStatus"] = incoming["rideStatus"]
            merged["statusUpdatedAt"] = incoming["statusUpdatedAt"]

        current_position = current.get("position")
        current_position_at = (
            _timestamp(current_position.get("recordedAt"))
            if isinstance(current_position, dict)
            else None
        )
        if request.position is not None and (
            current_position_at is None or request.position.recordedAt >= current_position_at
        ):
            merged["position"] = incoming["position"]

        if grant.scope == "group":
            merged["position"] = None
            merged["participants"] = incoming["participants"]
            merged["route"] = incoming["route"]
            merged["assistance"] = None

        current_assistance_at = _timestamp(current.get("assistanceUpdatedAt"))
        if current_assistance_at is None or request.assistanceUpdatedAt >= current_assistance_at:
            merged["assistanceUpdatedAt"] = incoming["assistanceUpdatedAt"]
            merged["assistance"] = incoming["assistance"]

        snapshot_ciphertext = cipher.encrypt_json(
            merged,
            associated_data=_snapshot_aad(grant.id),
        )
        result = session.execute(
            update(ObserverGrant)
            .where(
                ObserverGrant.id == grant.id,
                ObserverGrant.publisher_token_hash == token_hash(publisher_token),
                ObserverGrant.revoked_at.is_(None),
                ObserverGrant.expires_at > now,
            )
            .values(
                snapshot_ciphertext=snapshot_ciphertext,
                snapshot_updated_at=now,
                snapshot_version_at=request.snapshotGeneratedAt,
            )
            .execution_options(synchronize_session=False)
        )
        if result.rowcount != 1:
            raise RelayServiceError(404, "Observer access is unavailable")


def observer_snapshot(
    session: Session,
    *,
    cipher: DataCipher,
    grant_id: str,
    observer_token: str,
    now: datetime | None = None,
) -> dict[str, Any]:
    now = now or datetime.now(UTC)
    with session.begin():
        grant = _authorized_grant(
            session,
            grant_id=grant_id,
            supplied_token=observer_token,
            pattern=OBSERVER_TOKEN,
            expected_hash=lambda value: value.observer_token_hash,
            now=now,
        )
        grant.last_read_at = now
        snapshot: dict[str, Any] = {}
        if grant.snapshot_ciphertext is not None:
            try:
                value = cipher.decrypt_json(
                    grant.snapshot_ciphertext,
                    associated_data=_snapshot_aad(grant.id),
                )
            except ValueError as error:
                raise RelayServiceError(500, "Stored observer state is invalid") from error
            if not isinstance(value, dict):
                raise RelayServiceError(500, "Stored observer state is invalid")
            snapshot = value

        scope = grant.scope if grant.scope in {"rider", "group"} else "rider"
        position = snapshot.get("position") if scope == "rider" else None
        recorded_at = _timestamp(position.get("recordedAt")) if isinstance(position, dict) else None
        freshness = "unavailable"
        if recorded_at is not None:
            age = max(timedelta(0), now - recorded_at)
            freshness = (
                "fresh"
                if age <= timedelta(seconds=90)
                else "delayed"
                if age <= timedelta(minutes=5)
                else "offline"
            )
        assistance = snapshot.get("assistance")
        if isinstance(assistance, dict):
            kind = assistance.get("kind")
            reported_at = assistance.get("reportedAt")
            assistance = (
                {
                    "kind": kind,
                    "label": ("Help requested" if kind == "assistance" else "Emergency stop"),
                    "reportedAt": reported_at,
                }
                if kind in {"assistance", "emergencyStop"}
                else None
            )
        else:
            assistance = None
        participants: list[dict[str, Any]] = []
        if scope == "group":
            for raw_participant in snapshot.get("participants", []):
                if not isinstance(raw_participant, dict):
                    continue
                raw_position = raw_participant.get("position")
                participant_recorded_at = (
                    _timestamp(raw_position.get("recordedAt"))
                    if isinstance(raw_position, dict)
                    else None
                )
                participant_freshness = _freshness(participant_recorded_at, now)
                participants.append(
                    {
                        "displayName": raw_participant.get("displayName"),
                        "role": raw_participant.get("role"),
                        "color": raw_participant.get("color"),
                        "position": raw_position,
                        "freshness": participant_freshness,
                    }
                )
            available_freshness = [
                participant["freshness"]
                for participant in participants
                if participant["freshness"] != "unavailable"
            ]
            freshness = (
                max(
                    available_freshness,
                    key={"fresh": 0, "delayed": 1, "offline": 2}.__getitem__,
                )
                if available_freshness
                else "unavailable"
            )
            assistance = None
        return {
            "protocolVersion": 2 if scope == "group" else 1,
            "scope": scope,
            "precision": grant.precision if grant.precision in {"reduced", "exact"} else "reduced",
            "label": grant.label,
            "subjectName": snapshot.get("subjectName"),
            "rideStatus": snapshot.get("rideStatus", "waiting"),
            "statusUpdatedAt": snapshot.get("statusUpdatedAt"),
            "freshness": freshness,
            "serverTime": now,
            "expiresAt": _as_utc(grant.expires_at),
            "position": position,
            "participants": participants,
            "route": snapshot.get("route") if scope == "group" else None,
            "assistance": assistance,
        }


def grant_json(grant: ObserverGrant) -> dict[str, Any]:
    return {
        "id": grant.id,
        "label": grant.label,
        "scope": grant.scope if grant.scope in {"rider", "group"} else "rider",
        "precision": grant.precision if grant.precision in {"reduced", "exact"} else "reduced",
        "createdAt": _as_utc(grant.created_at),
        "expiresAt": _as_utc(grant.expires_at),
        "revokedAt": _as_utc(grant.revoked_at) if grant.revoked_at else None,
    }


def _authenticated_ride(
    session: Session,
    ride_id: str,
    bearer_token: str,
    *,
    lock_for_update: bool = False,
) -> Ride:
    if not IDENTIFIER.fullmatch(ride_id):
        raise RelayServiceError(400, "Ride identity is invalid")
    if not RIDE_TOKEN.fullmatch(bearer_token):
        raise RelayServiceError(403, "Ride credential rejected")
    statement = select(Ride).where(Ride.id == ride_id)
    if lock_for_update:
        statement = statement.with_for_update()
    ride = session.scalar(statement)
    if ride is None:
        raise RelayServiceError(404, "Ride is not ready for observer access")
    if not hmac.compare_digest(ride.token_hash, token_hash(bearer_token)):
        raise RelayServiceError(403, "Ride credential rejected")
    return ride


def _verify_group_pilot_authorization(
    session: Session,
    *,
    cipher: DataCipher,
    ride: Ride,
    request: CreateObserverGrantRequest,
    now: datetime,
) -> None:
    proof = request.pilotAuthorization
    if proof is None or ride.authority_root_public_key is None:
        raise RelayServiceError(403, "Pilot authorization is required")
    signed_at = datetime.fromtimestamp(proof.signedAtMilliseconds / 1000, tz=UTC)
    if signed_at < now - timedelta(minutes=5) or signed_at > now + timedelta(minutes=2):
        raise RelayServiceError(400, "Pilot authorization is outside its time window")
    pilot = _current_pilot_authority(
        session,
        cipher=cipher,
        ride_id=ride.id,
        root_public_key=ride.authority_root_public_key,
    )
    if pilot != (proof.deviceId, proof.devicePublicKey):
        raise RelayServiceError(403, "Pilot authorization was rejected")
    challenge = _group_grant_challenge(
        ride_id=ride.id,
        device_id=proof.deviceId,
        public_key=proof.devicePublicKey,
        signed_at_milliseconds=proof.signedAtMilliseconds,
        label=" ".join(request.label.split()),
        duration_minutes=request.durationMinutes,
        precision=request.precision,
    )
    if not _verify_signature(proof.devicePublicKey, proof.signature, challenge):
        raise RelayServiceError(403, "Pilot authorization was rejected")


def _current_pilot_authority(
    session: Session,
    *,
    cipher: DataCipher,
    ride_id: str,
    root_public_key: str,
) -> tuple[str, str] | None:
    rows = session.scalars(
        select(StoredEvent)
        .where(
            StoredEvent.ride_id == ride_id,
            StoredEvent.event_type.in_(
                [
                    "rideCreated",
                    "riderJoined",
                    "pilotHandoverOffered",
                    "pilotHandoverAccepted",
                    "deviceAuthorityRotated",
                    "deviceAuthorityRevoked",
                ]
            ),
        )
        .order_by(StoredEvent.sequence)
    ).all()
    device_keys: dict[str, str] = {}
    revoked: set[str] = set()
    pilot_device_id: str | None = None
    offers: dict[str, dict[str, Any]] = {}
    for row in rows:
        try:
            body = cipher.decrypt_json(
                row.body_ciphertext,
                associated_data=f"event:{ride_id}:{row.event_id}".encode(),
            )
        except ValueError:
            continue
        if not isinstance(body, dict) or body.get("schemaVersion") != 2:
            continue
        device_id = body.get("deviceId")
        public_key = body.get("devicePublicKey")
        event_type = body.get("type")
        payload = body.get("payload")
        if (
            not isinstance(device_id, str)
            or not isinstance(public_key, str)
            or not isinstance(payload, dict)
            or not _verify_event_signature(body)
        ):
            continue
        known_key = device_keys.get(device_id)
        if event_type in {"rideCreated", "riderJoined"}:
            if known_key is not None or not _device_id_matches(ride_id, device_id, public_key):
                continue
            if event_type == "rideCreated":
                if (
                    pilot_device_id is not None
                    or public_key != root_public_key
                    or payload.get("flightRole") != "pilot"
                ):
                    continue
                pilot_device_id = device_id
            elif payload.get("flightRole") in {"pilot", "observer"}:
                continue
            device_keys[device_id] = public_key
            continue
        if known_key != public_key or device_id in revoked:
            continue
        if event_type == "deviceAuthorityRotated":
            new_key = payload.get("newPublicKey")
            new_signature = payload.get("newDeviceSignature")
            challenge = (
                "balloon-crumbs-device-rotation-v1\n"
                f"{ride_id}\n{device_id}\n{public_key}\n{new_key}"
            )
            if (
                isinstance(new_key, str)
                and isinstance(new_signature, str)
                and _verify_signature(new_key, new_signature, challenge)
            ):
                device_keys[device_id] = new_key
            continue
        if event_type == "deviceAuthorityRevoked" and device_id == pilot_device_id:
            target = payload.get("targetDeviceId")
            if isinstance(target, str) and target != pilot_device_id:
                revoked.add(target)
            continue
        if event_type == "pilotHandoverOffered" and device_id == pilot_device_id:
            transfer_id = payload.get("transferId")
            from_device_id = payload.get("fromDeviceId")
            to_device_id = payload.get("toDeviceId")
            offered_at = _event_time(body.get("createdAt"))
            expires_at = _event_time(payload.get("expiresAt"))
            if (
                isinstance(transfer_id, str)
                and transfer_id
                and from_device_id == pilot_device_id
                and isinstance(to_device_id, str)
                and to_device_id != pilot_device_id
                and offered_at is not None
                and expires_at is not None
                and expires_at > offered_at
            ):
                offers[transfer_id] = {
                    **payload,
                    "offeredAt": offered_at,
                    "expiresAtParsed": expires_at,
                }
            continue
        if event_type == "pilotHandoverAccepted":
            transfer_id = payload.get("transferId")
            offer = offers.get(transfer_id) if isinstance(transfer_id, str) else None
            accepted_at = _event_time(body.get("createdAt"))
            if (
                offer is not None
                and accepted_at is not None
                and offer.get("fromDeviceId") == pilot_device_id
                and offer.get("toDeviceId") == device_id
                and payload.get("fromDeviceId") == pilot_device_id
                and payload.get("toDeviceId") == device_id
                and accepted_at <= offer["expiresAtParsed"]
                and accepted_at >= offer["offeredAt"] - timedelta(minutes=2)
            ):
                pilot_device_id = device_id
    if pilot_device_id is None or pilot_device_id in revoked:
        return None
    pilot_key = device_keys.get(pilot_device_id)
    return (pilot_device_id, pilot_key) if pilot_key is not None else None


def _verify_event_signature(body: dict[str, Any]) -> bool:
    signature = body.get("deviceSignature")
    public_key = body.get("devicePublicKey")
    if not isinstance(signature, str) or not isinstance(public_key, str):
        return False
    signed = {
        key: body.get(key)
        for key in (
            "schemaVersion",
            "id",
            "rideId",
            "deviceId",
            "type",
            "priority",
            "createdAt",
            "expiresAt",
            "payload",
            "devicePublicKey",
        )
    }
    canonical = json.dumps(
        signed,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    )
    return _verify_signature(public_key, signature, canonical)


def _event_time(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        return None
    return parsed.astimezone(UTC)


def _verify_signature(public_key: str, signature: str, challenge: str) -> bool:
    try:
        key_bytes = base64.urlsafe_b64decode(public_key + "=")
        signature_bytes = base64.urlsafe_b64decode(signature + "==")
        if len(key_bytes) != 32 or len(signature_bytes) != 64:
            return False
        Ed25519PublicKey.from_public_bytes(key_bytes).verify(
            signature_bytes,
            challenge.encode(),
        )
        return True
    except (InvalidSignature, ValueError):
        return False


def _device_id_matches(ride_id: str, device_id: str, public_key: str) -> bool:
    import hashlib

    digest = hashlib.sha256(
        f"balloon-crumbs-device-id-v1\n{ride_id}\n{public_key}".encode()
    ).digest()
    expected = f"bcd1_{base64.urlsafe_b64encode(digest).decode().rstrip('=')}"
    return hmac.compare_digest(device_id, expected)


def _group_grant_challenge(
    *,
    ride_id: str,
    device_id: str,
    public_key: str,
    signed_at_milliseconds: int,
    label: str,
    duration_minutes: int,
    precision: str,
) -> str:
    body = {
        "deviceId": device_id,
        "devicePublicKey": public_key,
        "durationMinutes": duration_minutes,
        "label": label,
        "precision": precision,
        "rideId": ride_id,
        "scope": "group",
        "signedAtMilliseconds": signed_at_milliseconds,
    }
    return "balloon-crumbs-observer-group-grant-v1\n" + json.dumps(
        body,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    )


def _reduce_snapshot_precision(snapshot: dict[str, Any]) -> dict[str, Any]:
    def reduce_position(value: Any, *, include_accuracy: bool = True) -> Any:
        if not isinstance(value, dict):
            return value
        reduced = dict(value)
        latitude = reduced.get("latitude")
        longitude = reduced.get("longitude")
        if isinstance(latitude, int | float) and isinstance(longitude, int | float):
            reduced["latitude"] = round(latitude, 2)
            reduced["longitude"] = round(longitude, 2)
            if include_accuracy:
                reduced["accuracyMeters"] = max(
                    float(reduced.get("accuracyMeters", 0)),
                    1500.0,
                )
        return reduced

    result = dict(snapshot)
    result["position"] = reduce_position(result.get("position"))
    participants = result.get("participants")
    if isinstance(participants, list):
        result["participants"] = [
            {**participant, "position": reduce_position(participant.get("position"))}
            if isinstance(participant, dict)
            else participant
            for participant in participants
        ]
    route = result.get("route")
    if isinstance(route, dict) and isinstance(route.get("points"), list):
        result["route"] = {
            **route,
            "points": [reduce_position(point, include_accuracy=False) for point in route["points"]],
        }
    return result


def _authorized_grant(
    session: Session,
    *,
    grant_id: str,
    supplied_token: str,
    pattern: re.Pattern[str],
    expected_hash: Callable[[ObserverGrant], bytes],
    now: datetime | None,
    lock_for_update: bool = False,
) -> ObserverGrant:
    now = now or datetime.now(UTC)
    if not pattern.fullmatch(supplied_token):
        raise RelayServiceError(404, "Observer access is unavailable")
    statement = select(ObserverGrant).where(ObserverGrant.id == grant_id)
    if lock_for_update:
        statement = statement.with_for_update()
    grant = session.scalar(statement)
    if (
        grant is None
        or grant.revoked_at is not None
        or _as_utc(grant.expires_at) <= now
        or not hmac.compare_digest(
            expected_hash(grant),
            token_hash(supplied_token),
        )
    ):
        raise RelayServiceError(404, "Observer access is unavailable")
    return grant


def _new_token(prefix: str) -> str:
    return f"{prefix}_{base64url(secrets.token_bytes(32))}"


def _timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or len(value) > 40:
        return None
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if result.tzinfo is None:
        return None
    return result.astimezone(UTC)


def _freshness(recorded_at: datetime | None, now: datetime) -> str:
    if recorded_at is None:
        return "unavailable"
    age = max(timedelta(0), now - recorded_at)
    return (
        "fresh"
        if age <= timedelta(seconds=90)
        else "delayed"
        if age <= timedelta(minutes=5)
        else "offline"
    )


def _snapshot_aad(grant_id: str) -> bytes:
    return f"observer-snapshot:{grant_id}".encode()


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
