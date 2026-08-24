"""Bind group observers to pilot authority and store disclosure precision.

Revision ID: 0013
Revises: 0012
Create Date: 2026-08-24
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "rides",
        sa.Column("authority_root_public_key", sa.String(length=43), nullable=True),
    )
    op.add_column(
        "observer_grants",
        sa.Column(
            "precision",
            sa.String(length=16),
            nullable=False,
            server_default="reduced",
        ),
    )


def downgrade() -> None:
    op.drop_column("observer_grants", "precision")
    op.drop_column("rides", "authority_root_public_key")
