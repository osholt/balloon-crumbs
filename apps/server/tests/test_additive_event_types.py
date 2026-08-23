"""Issue #128 on the relay: two additive event types plus their capabilities.

The relay stays deliberately dumb about ride semantics - it authenticates, bounds
and forwards - so what has to be tested here is that the new types are carried at
all, that their retention is capped tightly enough for what they contain, and that
neither of them can reach a trusted observer (#36) through the observer channel.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from balloon_crumbs_server.models import StoredEvent
from balloon_crumbs_server.service import RelayService

from .conftest import event, ride_token, sync_request

SECRET = "0123456789abcdef0123456789abcdef"
OBSERVER_SECRET = "observer-extra-field-secret-01234"


def test_new_event_retention_is_capped_tightly(client, synchronize, make_event) -> None:
    ride_id = "ride-craft-retention"
    before = datetime.now(UTC)
    events = [
        make_event(ride_id, "event-craft-1", event_type="craftChaseAssigned"),
        make_event(ride_id, "event-plain", event_type="statusMessage"),
    ]

    assert synchronize(client, ride_id=ride_id, secret=SECRET, events=events).status_code == 200

    factory = client.app.state.session_factory
    with factory() as session:
        stored = {
            row.event_id: row.expires_at.replace(tzinfo=UTC)
            for row in session.scalars(select(StoredEvent).where(StoredEvent.ride_id == ride_id))
        }

    # A chase assignment outlives a position report, because it is structure
    # rather than a fix: the 24-hour band a ride's own shape gets.
    assert stored["event-craft-1"] > before + timedelta(hours=23)


def test_retention_table_matches_the_documented_bands() -> None:
    retention = RelayService._maximum_event_retention
    # Issue #188. A rider's own phone number gets exactly the cap an ICE share
    # gets, and is capped independently of whatever expiry a client asks for.
    assert retention("riderContactShared") == timedelta(hours=2)
    assert retention("riderContactShared") == retention("iceInfoShared")
    assert retention("flightStartedByCrew") == timedelta(hours=72)
    assert retention("flightLanded") == timedelta(hours=72)
    assert retention("flightLandingRetracted") == timedelta(hours=72)


def test_ground_crew_start_is_accepted_and_relayed(client, synchronize, make_event) -> None:
    ride_id = "ride-ground-crew-start"
    start = make_event(
        ride_id,
        "event-ground-start",
        event_type="flightStartedByCrew",
        payload={
            "crewRiderId": "device-a",
            "crewDisplayName": "Alex",
            "flightRole": "chaseCrew",
        },
    )

    uploaded = synchronize(client, ride_id=ride_id, secret=SECRET, events=[start])
    assert uploaded.status_code == 200
    assert uploaded.json()["acceptedEventIds"] == ["event-ground-start"]

    downloaded = synchronize(
        client,
        ride_id=ride_id,
        secret=SECRET,
        device_id="device-b",
        cursor=None,
    )
    assert downloaded.status_code == 200
    assert [event["type"] for event in downloaded.json()["events"]] == ["flightStartedByCrew"]


def test_landing_and_retraction_are_accepted_and_relayed(client, synchronize, make_event) -> None:
    ride_id = "flight-landing-lifecycle"
    shared = [
        make_event(
            ride_id,
            "event-landed",
            event_type="flightLanded",
            payload={
                "declaredByDeviceId": "device-a",
                "declaredByDisplayName": "Alex",
                "declaredByRole": "chaseCrew",
                "evidence": "radioConfirmed",
            },
        ),
        make_event(
            ride_id,
            "event-retracted",
            event_type="flightLandingRetracted",
            payload={
                "landingEventId": "event-landed",
                "retractedByDeviceId": "device-a",
                "retractedByDisplayName": "Alex",
                "retractedByRole": "chaseCrew",
            },
        ),
    ]

    uploaded = synchronize(client, ride_id=ride_id, secret=SECRET, events=shared)
    assert uploaded.status_code == 200
    assert uploaded.json()["acceptedEventIds"] == ["event-landed", "event-retracted"]

    downloaded = synchronize(
        client,
        ride_id=ride_id,
        secret=SECRET,
        device_id="device-b",
        cursor=None,
    )
    assert downloaded.status_code == 200
    assert [item["type"] for item in downloaded.json()["events"]] == [
        "flightLanded",
        "flightLandingRetracted",
    ]


def test_a_shared_phone_number_is_accepted_and_capped(client, synchronize, make_event) -> None:
    ride_id = "ride-rider-contact"
    before = datetime.now(UTC)
    contact_event = make_event(
        ride_id,
        "event-contact-1",
        event_type="riderContactShared",
        payload={
            "contact": {
                "riderId": "device-a",
                "displayName": "Rider A",
                # A reserved, non-dialable placeholder: no real number belongs in
                # a fixture.
                "phone": "+00 0000 000000",
                "sharedByRole": "rider",
            },
            "recipientRiderIds": ["device-b"],
        },
    )

    response = synchronize(client, ride_id=ride_id, secret=SECRET, events=[contact_event])

    assert response.status_code == 200
    assert response.json()["acceptedEventIds"] == ["event-contact-1"]

    factory = client.app.state.session_factory
    with factory() as session:
        stored = session.scalars(select(StoredEvent).where(StoredEvent.ride_id == ride_id)).one()

    expires_at = stored.expires_at.replace(tzinfo=UTC)
    assert expires_at < before + timedelta(hours=3)
    assert expires_at > before + timedelta(hours=1)


def test_an_unknown_event_type_is_still_refused(client, synchronize, make_event) -> None:
    ride_id = "ride-unknown-type"
    response = synchronize(
        client,
        ride_id=ride_id,
        secret=SECRET,
        events=[make_event(ride_id, "event-future", event_type="tecRoleRevoked")],
    )

    # The relay's allowlist is deliberately closed: a client that invents a type
    # is rejected here, and forward compatibility is the *client's* per-event
    # skip, not a server that stores anything at all.
    assert response.status_code == 400
    assert "type" in response.json()["error"].lower()


def test_an_unrecognised_field_is_not_something_a_snapshot_can_carry(client) -> None:
    """#36 observers get their own authorisation decision, so the observer channel
    carries only what its schema names - and widening it has to be a deliberate
    change that fails this test first."""
    ride_id = "ride-observer-extra-field"
    now = datetime.now(UTC)
    assert (
        sync_request(
            client,
            ride_id=ride_id,
            secret=OBSERVER_SECRET,
            events=[event(ride_id, "created")],
        ).status_code
        == 200
    )
    grant = client.post(
        f"/api/v1/rides/{ride_id}/observer-grants",
        headers={
            "authorization": f"Bearer {ride_token(ride_id, OBSERVER_SECRET)}",
            "x-balloon-crumbs-device": "device-a",
        },
        json={"label": "Home contact", "durationMinutes": 60, "consentConfirmed": True},
    )
    assert grant.status_code == 201
    body = grant.json()

    snapshot = {
        "subjectName": "Bill",
        "snapshotGeneratedAt": now.isoformat(),
        "rideStatus": "active",
        "statusUpdatedAt": now.isoformat(),
        "position": None,
        "assistanceUpdatedAt": now.isoformat(),
        "assistance": None,
    }
    accepted = client.put(
        f"/api/v1/observer-grants/{body['id']}/snapshot",
        headers={"authorization": f"Bearer {body['publisherToken']}"},
        json=snapshot,
    )
    assert accepted.status_code == 204

    smuggled = client.put(
        f"/api/v1/observer-grants/{body['id']}/snapshot",
        headers={"authorization": f"Bearer {body['publisherToken']}"},
        json={
            **snapshot,
            "riderTrack": {"points": [[51.5, -0.1], [51.51, -0.09]]},
        },
    )
    # `extra="forbid"` on the publish schema: an unrecognised field is refused
    # outright rather than stored and quietly served on.
    assert smuggled.status_code == 400

    observed = client.get(
        f"/api/v1/observer-grants/{body['id']}",
        headers={"authorization": f"Bearer {body['observerToken']}"},
    )
    assert observed.status_code == 200
    served = observed.json()
    assert "riderTrack" not in served
    assert "points" not in str(served)


def test_craft_events_are_accepted_and_relayed(client, synchronize, make_event) -> None:
    """WP3. A device that knows crafts must be able to tell its peers.

    Craft structure is what lets several phones in one basket resolve to one
    balloon track, so if the relay refuses these the whole model degrades to the
    flat rider list on every device that was not present for the registration.
    """
    ride_id = "ride-crafts"
    shared = [
        make_event(
            ride_id,
            "event-craft-balloon",
            event_type="craftRegistered",
            payload={"craftId": "balloon", "kind": "balloon", "label": "Balloon"},
        ),
        make_event(
            ride_id,
            "event-craft-vehicle",
            event_type="craftRegistered",
            payload={"craftId": "v1", "kind": "vehicle", "label": "Land Rover"},
        ),
        make_event(
            ride_id,
            "event-attach",
            event_type="deviceAttachedToCraft",
            payload={"deviceId": "device-b", "craftId": "balloon"},
        ),
        make_event(
            ride_id,
            "event-primary",
            event_type="craftPrimaryDeviceNominated",
            payload={"craftId": "balloon", "deviceId": "device-b"},
        ),
        make_event(
            ride_id,
            "event-chase",
            event_type="craftChaseAssigned",
            payload={"craftId": "v1", "chasing": "balloon"},
        ),
        make_event(
            ride_id,
            "event-chase-target",
            event_type="chaseGuidanceTargetSelected",
            payload={"craftId": "v1", "target": "landingArea"},
        ),
        make_event(
            ride_id,
            "event-pilot-offer",
            event_type="pilotHandoverOffered",
            payload={
                "transferId": "transfer-1",
                "fromDeviceId": "device-a",
                "toDeviceId": "device-b",
                "expiresAt": "2026-08-23T12:10:00Z",
            },
        ),
        make_event(
            ride_id,
            "event-pilot-accept",
            event_type="pilotHandoverAccepted",
            payload={
                "transferId": "transfer-1",
                "fromDeviceId": "device-a",
                "toDeviceId": "device-b",
            },
        ),
    ]

    uploaded = synchronize(client, ride_id=ride_id, secret=SECRET, events=shared)
    assert uploaded.status_code == 200
    assert uploaded.json()["acceptedEventIds"] == [event["id"] for event in shared]

    downloaded = synchronize(client, ride_id=ride_id, secret=SECRET, device_id="device-b")
    assert downloaded.status_code == 200
    assert downloaded.json()["events"] == shared


def test_craft_structure_outlives_a_position_report() -> None:
    """Expiring craft structure before positions would leave a replaying device
    with fixes and no crafts to attach them to: the balloon would disappear while
    its track stayed on the map."""
    retention = RelayService._maximum_event_retention
    for event_type in (
        "craftRegistered",
        "deviceAttachedToCraft",
        "craftPrimaryDeviceNominated",
        "craftChaseAssigned",
        "chaseGuidanceTargetSelected",
        "pilotHandoverOffered",
        "pilotHandoverAccepted",
    ):
        assert retention(event_type) > retention("riderLocationUpdated")


def test_balloon_flight_context_is_accepted_and_relayed(client, synchronize, make_event) -> None:
    ride_id = "flight-context"
    shared = [
        make_event(
            ride_id,
            "landing-area",
            event_type="landingAreaNoted",
            payload={
                "latitude": 51.45,
                "longitude": -2.6,
                "radiusMeters": 500,
                "label": "North field",
            },
        ),
        make_event(
            ride_id,
            "wind-context",
            event_type="windContextNoted",
            payload={
                "validAt": "2026-08-22T06:00:00Z",
                "source": "UKMO test forecast",
                "isForecast": True,
                "latitude": 51.45,
                "longitude": -2.6,
                "speedUnit": "km/h",
                "vectors": [{"altitudeMetersMsl": 100, "fromDegrees": 240, "speedKmh": 12}],
            },
        ),
        make_event(
            ride_id,
            "boundary-upsert",
            event_type="operationalBoundaryUpserted",
            payload={
                "leaderRiderId": "device-a",
                "boundary": {
                    "id": "restricted-edge",
                    "label": "Restricted airspace edge",
                    "kind": "line",
                    "points": [
                        {"latitude": 51.4, "longitude": -2.7},
                        {"latitude": 51.5, "longitude": -2.6},
                    ],
                    "source": "Pilot briefing",
                    "updatedAt": "2026-08-22T06:00:00Z",
                },
            },
        ),
        make_event(
            ride_id,
            "boundary-remove",
            event_type="operationalBoundaryRemoved",
            payload={"leaderRiderId": "device-a", "boundaryId": "restricted-edge"},
        ),
    ]

    uploaded = synchronize(client, ride_id=ride_id, secret=SECRET, events=shared)
    assert uploaded.status_code == 200
    assert uploaded.json()["acceptedEventIds"] == [event["id"] for event in shared]

    downloaded = synchronize(client, ride_id=ride_id, secret=SECRET, device_id="device-b")
    assert downloaded.status_code == 200
    assert downloaded.json()["events"] == shared
