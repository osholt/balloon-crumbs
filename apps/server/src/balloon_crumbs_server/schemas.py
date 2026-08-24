from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)


class SyncRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocolVersion: Literal[1]
    deviceId: str = Field(min_length=1, max_length=128)
    cursor: str | None = Field(default=None, max_length=512)
    events: list[dict[str, Any]]


class SyncResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocolVersion: Literal[1] = 1
    cursor: str
    acceptedEventIds: list[str]
    events: list[dict[str, Any]]


class PresencePoint(BaseModel):
    model_config = ConfigDict(extra="forbid")

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class PresenceLocationSample(BaseModel):
    model_config = ConfigDict(extra="forbid")

    position: PresencePoint
    recordedAt: datetime
    accuracyMeters: float = Field(ge=0, le=500)
    speedMetersPerSecond: float | None = Field(default=None, ge=0, le=100)
    headingDegrees: float | None = Field(default=None, ge=0, lt=360)
    altitudeMeters: float | None = Field(default=None, ge=-1000, le=30000)
    altitudeSource: str | None = Field(default=None, min_length=1, max_length=40)
    altitudeDatum: str | None = Field(default=None, min_length=1, max_length=40)
    altitudeAccuracyMeters: float | None = Field(default=None, ge=0, le=10000)
    verticalSpeedMetersPerSecond: float | None = Field(default=None, ge=-100, le=100)


class PresencePositionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    displayName: str = Field(min_length=1, max_length=80)
    role: Literal["lead", "rider", "tailEndCharlie"]
    craftStyle: str | None = Field(default=None, min_length=1, max_length=40)
    riderSymbol: str | None = Field(default=None, min_length=1, max_length=40)
    motorcycleStyle: str | None = Field(default=None, min_length=1, max_length=40)
    riderColor: str = Field(min_length=1, max_length=40)
    sample: PresenceLocationSample

    @model_validator(mode="after")
    def normalize_craft_style(self) -> PresencePositionRequest:
        """Accept either key and echo both during the mixed-build migration."""

        style = self.craftStyle or self.motorcycleStyle
        if style is None:
            raise ValueError("A presence position requires a craft style")
        self.craftStyle = style
        self.motorcycleStyle = style
        return self


class PresenceSyncRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocolVersion: Literal[1]
    deviceId: str = Field(min_length=1, max_length=128)
    position: PresencePositionRequest | None = None
    clear: bool = False
    authorityVersion: Literal[1] | None = None
    signedAtMilliseconds: int | None = Field(default=None, ge=0)
    devicePublicKey: str | None = Field(default=None, pattern=r"^[A-Za-z0-9_-]{43}$")
    deviceSignature: str | None = Field(default=None, pattern=r"^[A-Za-z0-9_-]{86}$")

    @model_validator(mode="after")
    def clear_cannot_publish(self) -> PresenceSyncRequest:
        if self.clear and self.position is not None:
            raise ValueError("A presence request cannot publish and clear together")
        authority = (
            self.authorityVersion,
            self.signedAtMilliseconds,
            self.devicePublicKey,
            self.deviceSignature,
        )
        if any(value is not None for value in authority) and not all(
            value is not None for value in authority
        ):
            raise ValueError("A presence authority proof must be complete")
        return self


class PresencePositionResponse(PresencePositionRequest):
    riderId: str
    receivedAt: datetime
    expiresAt: datetime

    # False when the publishing build only advertised the legacy pre-start
    # capability, so a peer can name the limitation instead of showing an
    # unexplained gap once the ride starts.
    livePresence: bool = False
    clientProtocol: int = Field(default=1, ge=1, le=1000)
    authorityVersion: Literal[1] | None = None
    signedAtMilliseconds: int | None = Field(default=None, ge=0)
    devicePublicKey: str | None = Field(default=None, pattern=r"^[A-Za-z0-9_-]{43}$")
    deviceSignature: str | None = Field(default=None, pattern=r"^[A-Za-z0-9_-]{86}$")


class PresenceMemberResponse(BaseModel):
    """One rider derived from durable membership events, with no cursor.

    This is what lets a join reach the other devices even when their bulk event
    batch is wedged or backed off.
    """

    model_config = ConfigDict(extra="forbid")

    riderId: str = Field(min_length=1, max_length=128)
    displayName: str = Field(min_length=1, max_length=80)
    role: str = Field(min_length=1, max_length=40)
    joinedAt: datetime
    left: bool = False

    # When the departure was recorded, so a caller can say *when* a rider left
    # and can order that departure against a later rejoin without waiting for
    # the bulk event batch (issue #144). Absent unless ``left`` is true;
    # additive, so an older client simply ignores it.
    leftAt: datetime | None = None


class PresenceSyncResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocolVersion: Literal[1] = 1
    ttlSeconds: int
    positions: list[PresencePositionResponse]
    phase: Literal["open", "started", "ended"] = "open"
    members: list[PresenceMemberResponse] = Field(default_factory=list)

    # The relay's own current time, alongside the arrival stamps it puts on every
    # position. Two phones do not share a clock, so a peer's position can only be
    # aged honestly against the clock that stamped its arrival. Additive: an older
    # client ignores it and keeps using its own clock.
    serverTime: datetime | None = None


class PushPreferences(BaseModel):
    model_config = ConfigDict(extra="forbid")

    safety: bool = True
    status: bool = True
    administrative: bool = True


class PushRegistrationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    platform: Literal["ios", "android"]
    provider: Literal["apns", "fcm"]
    token: str = Field(min_length=16, max_length=4096)
    role: Literal["lead", "rider", "tailEndCharlie"]
    preferences: PushPreferences = Field(default_factory=PushPreferences)

    @model_validator(mode="after")
    def provider_matches_platform(self) -> PushRegistrationRequest:
        if self.platform == "ios" and self.provider != "apns":
            raise ValueError("iOS registrations must use APNs")
        if self.platform == "android" and self.provider != "fcm":
            raise ValueError("Android registrations must use FCM")
        return self


class PushRegistrationResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    installationId: str
    platform: Literal["ios", "android"]
    provider: Literal["apns", "fcm"]
    role: Literal["lead", "rider", "tailEndCharlie"]
    preferences: PushPreferences
    registeredAt: datetime
    updatedAt: datetime


class RegisterJoinCodeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rideId: str = Field(min_length=1, max_length=128)
    inviteSecret: str = Field(min_length=16, max_length=512)
    resolveToken: str = Field(min_length=16, max_length=128)
    authorityRootPublicKey: str | None = Field(default=None, pattern=r"^[A-Za-z0-9_-]{43}$")


class JoinCodeResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rideId: str
    rideCode: str
    inviteSecret: str
    resolveToken: str
    authorityRootPublicKey: str | None = None


class CrewRoomOperation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rideId: str = Field(min_length=1, max_length=128)
    rideCode: str = Field(pattern=r"^\d{6}$")
    inviteSecret: str = Field(min_length=16, max_length=512)
    resolveToken: str = Field(min_length=16, max_length=128)
    authorityRootPublicKey: str | None = Field(default=None, pattern=r"^[A-Za-z0-9_-]{43}$")


class CreateCrewRoomRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    alias: str = Field(min_length=5, max_length=12)
    deviceId: str = Field(min_length=1, max_length=128)
    displayName: str = Field(min_length=1, max_length=80)
    operation: CrewRoomOperation


class CrewRoomAuthRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    alias: str = Field(min_length=5, max_length=12)
    deviceId: str = Field(min_length=1, max_length=128)
    deviceCredential: str = Field(min_length=48, max_length=48)


class JoinCrewRoomRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    alias: str = Field(min_length=5, max_length=12)
    inviteToken: str = Field(min_length=48, max_length=48)
    deviceId: str = Field(min_length=1, max_length=128)
    displayName: str = Field(min_length=1, max_length=80)


class StartCrewRoomOperationRequest(CrewRoomAuthRequest):
    operation: CrewRoomOperation


class RenameCrewRoomRequest(CrewRoomAuthRequest):
    newAlias: str = Field(min_length=5, max_length=12)


class CrewRoomTargetDeviceRequest(CrewRoomAuthRequest):
    targetDeviceId: str = Field(min_length=1, max_length=128)


class CrewRoomDeviceResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    deviceId: str
    displayName: str
    owner: bool
    revoked: bool
    lastSeenAt: datetime


class CrewRoomDeviceListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    alias: str
    devices: list[CrewRoomDeviceResponse]


class CrewRoomResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    roomId: str
    alias: str
    deviceCredential: str
    inviteToken: str | None = None
    operationGeneration: int = Field(ge=1)
    operation: CrewRoomOperation | None
    operationExpiresAt: datetime
    owner: bool


class CompatibilityResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    serverBuildCommit: str
    serverProtocol: int
    minimumClientProtocol: int
    maximumClientProtocol: int
    capabilities: list[str]
    requiredCapabilities: list[str]
    cacheSeconds: int
    updateUrls: dict[str, str]


class TrafficRoutePoint(BaseModel):
    model_config = ConfigDict(extra="forbid")

    latitude: float = Field(ge=49.0, le=61.5)
    longitude: float = Field(ge=-11.5, le=3.0)


class TrafficAvoidArea(BaseModel):
    model_config = ConfigDict(extra="forbid")

    west: float = Field(ge=-11.5, le=3.0)
    south: float = Field(ge=49.0, le=61.5)
    east: float = Field(ge=-11.5, le=3.0)
    north: float = Field(ge=49.0, le=61.5)

    @model_validator(mode="after")
    def bounds_are_ordered(self) -> TrafficAvoidArea:
        if self.west >= self.east or self.south >= self.north:
            raise ValueError("Avoid-area bounds must be ordered")
        return self


class TrafficRerouteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    path: list[TrafficRoutePoint] = Field(min_length=2, max_length=1000)
    avoidAreas: list[TrafficAvoidArea] = Field(min_length=1, max_length=10)
    incidentIds: list[str] = Field(min_length=1, max_length=10)

    @field_validator("incidentIds")
    @classmethod
    def incident_ids_are_bounded(cls, values: list[str]) -> list[str]:
        cleaned = [value.strip() for value in values]
        if any(not value or len(value) > 200 for value in cleaned):
            raise ValueError("Incident IDs must contain 1 to 200 characters")
        if len(set(cleaned)) != len(cleaned):
            raise ValueError("Incident IDs must be unique")
        return cleaned


class ForecastPlanPoint(BaseModel):
    model_config = ConfigDict(extra="ignore")

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class ForecastPlanLaunch(BaseModel):
    model_config = ConfigDict(extra="ignore")

    point: ForecastPlanPoint
    elevationMsl: float = Field(ge=-500, le=20_000)
    datum: str = Field(min_length=1, max_length=64)


class ForecastPlanDestination(BaseModel):
    model_config = ConfigDict(extra="ignore")

    point: ForecastPlanPoint
    toleranceMetres: float = Field(gt=0, le=100_000)


class ForecastPlanLandingArea(BaseModel):
    model_config = ConfigDict(extra="ignore")

    centre: ForecastPlanPoint
    radiusMetres: float | None = Field(default=None, gt=0, le=100_000)
    polygon: list[ForecastPlanPoint] = Field(default_factory=list, max_length=512)
    updatedAt: datetime

    @model_validator(mode="after")
    def has_bounded_area(self) -> ForecastPlanLandingArea:
        if self.radiusMetres is None and len(self.polygon) < 3:
            raise ValueError("An intended landing area needs a radius or polygon")
        return self


class ForecastPlanDeparture(BaseModel):
    model_config = ConfigDict(extra="ignore")

    selectedAt: datetime
    matchingWindowStart: datetime | None = None
    matchingWindowEnd: datetime | None = None

    @model_validator(mode="after")
    def window_is_ordered(self) -> ForecastPlanDeparture:
        if (
            self.matchingWindowStart is not None
            and self.matchingWindowEnd is not None
            and self.matchingWindowEnd < self.matchingWindowStart
        ):
            raise ValueError("The matching departure window is reversed")
        return self


class ForecastPlanConstraints(BaseModel):
    model_config = ConfigDict(extra="ignore")

    altitudeCeilingMsl: float = Field(ge=-500, le=20_000)
    maximumAscentRateMps: float = Field(gt=0, le=30)
    maximumDescentRateMps: float = Field(gt=0, le=30)
    minimumDurationMinutes: float = Field(gt=0, le=24 * 60)
    maximumDurationMinutes: float = Field(gt=0, le=24 * 60)

    @model_validator(mode="after")
    def durations_are_ordered(self) -> ForecastPlanConstraints:
        if self.maximumDurationMinutes < self.minimumDurationMinutes:
            raise ValueError("Maximum duration must not precede minimum duration")
        return self


class ForecastPlanStage(BaseModel):
    model_config = ConfigDict(extra="ignore")

    fraction: float = Field(ge=0, le=1)
    plannedAt: datetime
    altitudeMsl: float = Field(ge=-500, le=20_000)
    changeRateMps: float = Field(ge=-30, le=30)


class ForecastPlanTrackPoint(ForecastPlanPoint):
    altitudeMsl: float = Field(ge=-500, le=20_000)
    elapsedSeconds: float = Field(ge=0, le=24 * 60 * 60)


class ForecastPlanWind(BaseModel):
    model_config = ConfigDict(extra="ignore")

    provider: str = Field(min_length=1, max_length=120)
    model: str = Field(min_length=1, max_length=120)
    requestedAt: datetime
    validFrom: datetime
    validTo: datetime
    attribution: str = Field(min_length=1, max_length=500)
    licence: str = Field(min_length=1, max_length=500)
    forecastOnly: Literal[True]
    fieldDigest: str = Field(min_length=1, max_length=128)


class ForecastPlanBoundary(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: str = Field(min_length=1, max_length=96)
    label: str = Field(min_length=1, max_length=96)
    kind: Literal["line", "area", "altitudeBand"]
    points: list[ForecastPlanPoint] = Field(default_factory=list, max_length=512)
    source: str = Field(min_length=1, max_length=160)
    updatedAt: datetime
    lowerAltitudeMeters: float | None = Field(default=None, ge=-500, le=20_000)
    upperAltitudeMeters: float | None = Field(default=None, ge=-500, le=20_000)
    altitudeDatum: str = Field(min_length=1, max_length=64)

    @model_validator(mode="after")
    def geometry_matches_kind(self) -> ForecastPlanBoundary:
        if self.kind == "line" and len(self.points) < 2:
            raise ValueError("A boundary line needs two points")
        if self.kind == "area" and len(self.points) < 3:
            raise ValueError("A boundary area needs three points")
        if self.kind == "altitudeBand" and self.points:
            raise ValueError("An altitude band cannot contain points")
        if (
            self.lowerAltitudeMeters is not None
            and self.upperAltitudeMeters is not None
            and self.lowerAltitudeMeters >= self.upperAltitudeMeters
        ):
            raise ValueError("Boundary altitude limits are reversed")
        return self


class ForecastPlanResult(BaseModel):
    model_config = ConfigDict(extra="ignore")

    kind: str = Field(min_length=1, max_length=80)
    reachesDestination: bool | None = None
    missDistanceMetres: float | None = Field(default=None, ge=0, le=50_000_000)


class ForecastPlanDocument(BaseModel):
    """Bounded version-one planner evidence; additive fields are ignored."""

    model_config = ConfigDict(extra="ignore")

    schemaVersion: Literal[1]
    id: str = Field(min_length=1, max_length=128)
    name: str = Field(min_length=1, max_length=200)
    createdAt: datetime
    expiresAt: datetime | None = None
    source: Literal["Balloon Crumbs web planner"]
    launch: ForecastPlanLaunch
    destination: ForecastPlanDestination | None = None
    intendedLandingArea: ForecastPlanLandingArea
    forecastLanding: ForecastPlanPoint
    departure: ForecastPlanDeparture
    constraints: ForecastPlanConstraints
    altitudeStages: list[ForecastPlanStage] = Field(min_length=2, max_length=32)
    plannedTrack: list[ForecastPlanTrackPoint] = Field(min_length=2, max_length=20_000)
    landingEnvelope: list[ForecastPlanPoint] = Field(default_factory=list, max_length=512)
    wind: ForecastPlanWind
    operationalBoundaries: list[ForecastPlanBoundary] = Field(default_factory=list, max_length=64)
    result: ForecastPlanResult
    gpxFallback: str = Field(min_length=1)

    def geometry_point_count(self) -> int:
        return (
            len(self.plannedTrack)
            + len(self.landingEnvelope)
            + len(self.intendedLandingArea.polygon)
            + sum(len(boundary.points) for boundary in self.operationalBoundaries)
        )


class CreatePlanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, max_length=200)
    gpx: str = Field(min_length=1)
    forecastPlan: ForecastPlanDocument | None = None


class CreatePlanResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str
    expiresAt: str


class GetPlanResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: str
    name: str | None
    gpx: str
    forecastPlan: dict[str, Any] | None = None
    createdAt: str
    expiresAt: str


class CreateObserverGrantRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    label: str = Field(min_length=1, max_length=80)
    durationMinutes: int = Field(ge=30, le=24 * 60)
    consentConfirmed: Literal[True]
    scope: Literal["rider", "group"] = "rider"
    groupDisclosureConfirmed: Literal[True] | None = None

    @model_validator(mode="after")
    def group_scope_requires_disclosure(self) -> CreateObserverGrantRequest:
        if self.scope == "group" and self.groupDisclosureConfirmed is not True:
            raise ValueError("Group observer access requires group disclosure")
        if self.scope == "rider" and self.groupDisclosureConfirmed is not None:
            raise ValueError("Personal observer access has no group disclosure")
        return self


class ObserverGrantResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    label: str
    scope: Literal["rider", "group"] = "rider"
    createdAt: datetime
    expiresAt: datetime
    revokedAt: datetime | None


class CreateObserverGrantResponse(ObserverGrantResponse):
    managementToken: str
    publisherToken: str
    observerToken: str


class ObserverPosition(BaseModel):
    model_config = ConfigDict(extra="forbid")

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracyMeters: float = Field(ge=0, le=500)
    recordedAt: datetime

    @field_validator("recordedAt")
    @classmethod
    def recorded_at_requires_timezone(cls, value: datetime) -> datetime:
        return _aware_utc(value)


class PublishObserverAssistance(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["assistance", "emergencyStop"]
    reportedAt: datetime

    @field_validator("reportedAt")
    @classmethod
    def reported_at_requires_timezone(cls, value: datetime) -> datetime:
        return _aware_utc(value)


class PublishObserverGroupParticipant(BaseModel):
    model_config = ConfigDict(extra="forbid")

    displayName: str = Field(min_length=1, max_length=80)
    role: Literal["lead", "rider", "tailEndCharlie"]
    color: str = Field(pattern=r"^#[0-9A-Fa-f]{6}$")
    position: ObserverPosition | None


class ObserverRoutePoint(BaseModel):
    model_config = ConfigDict(extra="forbid")

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class ObserverRoute(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=80)
    points: list[ObserverRoutePoint] = Field(min_length=2, max_length=500)


class PublishObserverSnapshotRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scope: Literal["rider", "group"] = "rider"
    subjectName: str = Field(min_length=1, max_length=80)
    snapshotGeneratedAt: datetime
    rideStatus: Literal["waiting", "active", "paused", "ended"]
    statusUpdatedAt: datetime
    position: ObserverPosition | None
    participants: list[PublishObserverGroupParticipant] = Field(
        default_factory=list,
        max_length=50,
    )
    route: ObserverRoute | None = None
    assistanceUpdatedAt: datetime
    assistance: PublishObserverAssistance | None

    @field_validator(
        "snapshotGeneratedAt",
        "statusUpdatedAt",
        "assistanceUpdatedAt",
    )
    @classmethod
    def timestamps_require_timezone(cls, value: datetime) -> datetime:
        return _aware_utc(value)

    @model_validator(mode="after")
    def scope_matches_payload(self) -> PublishObserverSnapshotRequest:
        if self.scope == "rider":
            if self.participants or self.route is not None:
                raise ValueError("Personal observer snapshots cannot contain group data")
        elif self.position is not None or self.assistance is not None:
            raise ValueError("Group observer snapshots cannot contain personal-only state")
        return self


class ObserverAssistance(PublishObserverAssistance):
    label: str


class ObserverGroupParticipant(PublishObserverGroupParticipant):
    freshness: Literal["unavailable", "fresh", "delayed", "offline"]


class ObserverSnapshotResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    protocolVersion: Literal[1, 2] = 1
    scope: Literal["rider", "group"] = "rider"
    label: str
    subjectName: str | None
    rideStatus: Literal["waiting", "active", "paused", "ended"]
    statusUpdatedAt: datetime | None
    freshness: Literal["unavailable", "fresh", "delayed", "offline"]
    serverTime: datetime
    expiresAt: datetime
    position: ObserverPosition | None
    participants: list[ObserverGroupParticipant] = Field(default_factory=list)
    route: ObserverRoute | None = None
    assistance: ObserverAssistance | None


def _aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Timestamp timezone is required")
    return value.astimezone(UTC)
