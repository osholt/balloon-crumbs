"""Add persistent, privacy-bounded named crew rooms.

Revision ID: 0012
Revises: 0011
Create Date: 2026-08-23
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "crew_rooms",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("alias_digest", sa.LargeBinary(length=32), nullable=False),
        sa.Column("alias_ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("owner_device_digest", sa.LargeBinary(length=32), nullable=False),
        sa.Column("invite_token_hash", sa.LargeBinary(length=32), nullable=False),
        sa.Column("operation_ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("operation_generation", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("operation_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("alias_digest", name="uq_crew_room_alias_digest"),
    )
    op.create_index(
        "ix_crew_rooms_operation_expiry",
        "crew_rooms",
        ["operation_expires_at"],
    )
    op.create_table(
        "crew_room_devices",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("room_id", sa.String(length=128), nullable=False),
        sa.Column("device_digest", sa.LargeBinary(length=32), nullable=False),
        sa.Column("credential_hash", sa.LargeBinary(length=32), nullable=False),
        sa.Column("profile_ciphertext", sa.LargeBinary(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["room_id"], ["crew_rooms.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("room_id", "device_digest", name="uq_crew_room_device_identity"),
    )
    op.create_index(
        "ix_crew_room_devices_active",
        "crew_room_devices",
        ["room_id", "revoked_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_crew_room_devices_active", table_name="crew_room_devices")
    op.drop_table("crew_room_devices")
    op.drop_index("ix_crew_rooms_operation_expiry", table_name="crew_rooms")
    op.drop_table("crew_rooms")
