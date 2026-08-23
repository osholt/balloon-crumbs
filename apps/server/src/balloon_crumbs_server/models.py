from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class Ride(Base):
    __tablename__ = "rides"

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    token_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    delete_after: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    stored_event_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    stored_event_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    membership_projection_ready: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
    )

    events: Mapped[list[StoredEvent]] = relationship(
        back_populates="ride",
        cascade="all, delete-orphan",
    )
    replays: Mapped[list[IdempotencyReplay]] = relationship(
        back_populates="ride",
        cascade="all, delete-orphan",
    )
    push_registrations: Mapped[list[PushRegistration]] = relationship(
        back_populates="ride",
        cascade="all, delete-orphan",
    )
    observer_grants: Mapped[list[ObserverGrant]] = relationship(
        back_populates="ride",
        cascade="all, delete-orphan",
    )
    pre_start_positions: Mapped[list[PreStartPosition]] = relationship(
        back_populates="ride",
        cascade="all, delete-orphan",
    )
    members: Mapped[list[RideMember]] = relationship(
        back_populates="ride",
        cascade="all, delete-orphan",
    )


class RideJoinCode(Base):
    """A short-lived, encrypted lookup record for a six-digit ride code."""

    __tablename__ = "ride_join_codes"
    __table_args__ = (Index("ix_ride_join_codes_expiry", "expires_at"),)

    code: Mapped[str] = mapped_column(String(6), primary_key=True)
    ride_id: Mapped[str] = mapped_column(String(128), nullable=False)
    token_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    secret_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class CrewRoom(Base):
    """Persistent named crew directory containing only encrypted room data."""

    __tablename__ = "crew_rooms"
    __table_args__ = (
        UniqueConstraint("alias_digest", name="uq_crew_room_alias_digest"),
        Index("ix_crew_rooms_operation_expiry", "operation_expires_at"),
    )

    id: Mapped[str] = mapped_column(String(128), primary_key=True)
    alias_digest: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    alias_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    owner_device_digest: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    invite_token_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    operation_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    operation_generation: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    operation_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    devices: Mapped[list[CrewRoomDevice]] = relationship(
        back_populates="room",
        cascade="all, delete-orphan",
    )


class CrewRoomDevice(Base):
    """One independently revocable returning-device credential."""

    __tablename__ = "crew_room_devices"
    __table_args__ = (
        UniqueConstraint("room_id", "device_digest", name="uq_crew_room_device_identity"),
        Index("ix_crew_room_devices_active", "room_id", "revoked_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    room_id: Mapped[str] = mapped_column(
        String(128),
        ForeignKey("crew_rooms.id", ondelete="CASCADE"),
        nullable=False,
    )
    device_digest: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    credential_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    profile_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    room: Mapped[CrewRoom] = relationship(back_populates="devices")


class RidePlan(Base):
    """An encrypted, pre-ride forecast plan behind a short lookup code.

    Unrelated to the live ride/join-code tables: a plan never carries a ride
    secret and a fetched plan never claims a ride. The phone that loads one
    still runs its own unchanged create-ride flow.
    """

    __tablename__ = "ride_plans"
    __table_args__ = (Index("ix_ride_plans_expiry", "expires_at"),)

    code: Mapped[str] = mapped_column(String(16), primary_key=True)
    name: Mapped[str | None] = mapped_column(String(200))
    # Kept under its deployed column name. Older rows decrypt to a GPX string;
    # structured rows decrypt to {gpx, forecastPlan}, so no plaintext migration
    # or compatibility-breaking schema change is required.
    gpx_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class StoredEvent(Base):
    __tablename__ = "ride_events"
    __table_args__ = (
        UniqueConstraint("ride_id", "event_id", name="uq_ride_event_identity"),
        Index("ix_ride_events_cursor", "ride_id", "sequence"),
        Index("ix_ride_events_expiry", "expires_at"),
    )

    sequence: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ride_id: Mapped[str] = mapped_column(
        String(128),
        ForeignKey("rides.id", ondelete="CASCADE"),
        nullable=False,
    )
    event_id: Mapped[str] = mapped_column(String(128), nullable=False)
    device_id: Mapped[str] = mapped_column(String(128), nullable=False)
    event_type: Mapped[str] = mapped_column(String(48), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    body_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    body_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)

    ride: Mapped[Ride] = relationship(back_populates="events")


class RideMember(Base):
    """Current push-recipient state projected from the encrypted event journal."""

    __tablename__ = "ride_members"

    ride_id: Mapped[str] = mapped_column(
        String(128),
        ForeignKey("rides.id", ondelete="CASCADE"),
        primary_key=True,
    )
    device_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    state: Mapped[str] = mapped_column(String(16), nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    ride: Mapped[Ride] = relationship(back_populates="members")


class PreStartPosition(Base):
    """One encrypted, short-lived pre-start snapshot per rider.

    This is deliberately not an event or history table. Publishing again
    replaces the same row, and every read purges expired rows first.
    """

    __tablename__ = "pre_start_positions"
    __table_args__ = (Index("ix_pre_start_positions_expiry", "expires_at"),)

    ride_id: Mapped[str] = mapped_column(
        String(128),
        ForeignKey("rides.id", ondelete="CASCADE"),
        primary_key=True,
    )
    rider_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    snapshot_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    ride: Mapped[Ride] = relationship(back_populates="pre_start_positions")


class IdempotencyReplay(Base):
    __tablename__ = "idempotency_replays"
    __table_args__ = (
        UniqueConstraint("ride_id", "idempotency_key", name="uq_ride_idempotency_key"),
        Index("ix_idempotency_replays_expiry", "expires_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ride_id: Mapped[str] = mapped_column(
        String(128),
        ForeignKey("rides.id", ondelete="CASCADE"),
        nullable=False,
    )
    idempotency_key: Mapped[str] = mapped_column(String(64), nullable=False)
    request_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    response_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    ride: Mapped[Ride] = relationship(back_populates="replays")


class PushRegistration(Base):
    """Encrypted provider token bound to one installation and live ride."""

    __tablename__ = "push_registrations"
    __table_args__ = (
        UniqueConstraint(
            "ride_id",
            "installation_id",
            "provider",
            name="uq_push_registration_installation",
        ),
        Index("ix_push_registrations_active", "ride_id", "revoked_at"),
        Index("ix_push_registrations_token", "provider", "token_hash"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ride_id: Mapped[str] = mapped_column(
        String(128),
        ForeignKey("rides.id", ondelete="CASCADE"),
        nullable=False,
    )
    installation_id: Mapped[str] = mapped_column(String(128), nullable=False)
    platform: Mapped[str] = mapped_column(String(16), nullable=False)
    provider: Mapped[str] = mapped_column(String(16), nullable=False)
    token_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    token_ciphertext: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    safety_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    administrative_enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    ride: Mapped[Ride] = relationship(back_populates="push_registrations")
    deliveries: Mapped[list[PushDelivery]] = relationship(
        back_populates="registration",
        cascade="all, delete-orphan",
    )


class PushDelivery(Base):
    """One provider attempt per durable event and recipient registration."""

    __tablename__ = "push_deliveries"
    __table_args__ = (
        UniqueConstraint(
            "ride_id",
            "event_id",
            "registration_id",
            name="uq_push_delivery_event_recipient",
        ),
        Index("ix_push_deliveries_status", "status", "attempted_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    ride_id: Mapped[str] = mapped_column(String(128), nullable=False)
    event_id: Mapped[str] = mapped_column(String(128), nullable=False)
    registration_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("push_registrations.id", ondelete="CASCADE"),
        nullable=False,
    )
    category: Mapped[str] = mapped_column(String(24), nullable=False)
    status: Mapped[str] = mapped_column(String(24), nullable=False)
    provider_message_id: Mapped[str | None] = mapped_column(String(256))
    error_code: Mapped[str | None] = mapped_column(String(80))
    attempted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    registration: Mapped[PushRegistration] = relationship(back_populates="deliveries")


class ObserverGrant(Base):
    """Time-bounded, independently managed/published/read observer state."""

    __tablename__ = "observer_grants"
    __table_args__ = (
        Index("ix_observer_grants_ride", "ride_id"),
        Index("ix_observer_grants_expiry", "expires_at"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    ride_id: Mapped[str] = mapped_column(
        String(128),
        ForeignKey("rides.id", ondelete="CASCADE"),
        nullable=False,
    )
    label: Mapped[str] = mapped_column(String(80), nullable=False)
    scope: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        default="rider",
        server_default="rider",
    )
    management_token_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    publisher_token_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    observer_token_hash: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    snapshot_ciphertext: Mapped[bytes | None] = mapped_column(LargeBinary)
    snapshot_updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    snapshot_version_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    ride: Mapped[Ride] = relationship(back_populates="observer_grants")
