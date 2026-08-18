"""Drop the four discovery tables the withdrawn API used to write.

Revision ID: 0011
Revises: 0010
Create Date: 2026-08-18

The endpoints went in the previous cut (WP4, #19). The tables outlived them on
purpose: withdrawing an API is reversible, dropping the rows it wrote is not,
and `discovery_suggestions` plus `discovery_moderation_events` held
user-contributed text and the moderation history behind each decision. That
deserved its own decision rather than riding along with a route deletion.

The decision: the tables go. Balloon Crumbs is a balloon chase app and the
discovery layer catalogued twisty roads, mountain passes and biker stops for
motorcyclists — there is no version of the chase crew's job that wants it back,
so the schema is not worth carrying in every future migration. Confirmed with
the owner that no deployed Balloon Crumbs database holds anything of value:
each Compose project runs its own Postgres in its own namespaced volume, so
nothing here can reach the Tail End Charlie deployment's data.

`downgrade` rebuilds the schema exactly as 0004 and 0008 created it, so the
migration is reversible in structure. It cannot bring the rows back. Anyone
who needs those must restore from a backup taken before this ran.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Children first: `discovery_features` and `discovery_moderation_events`
    # both carry a foreign key onto `discovery_suggestions`.
    op.drop_index("ix_discovery_features_public", table_name="discovery_features")
    op.drop_table("discovery_features")
    op.drop_index(
        "ix_discovery_moderation_suggestion",
        table_name="discovery_moderation_events",
    )
    op.drop_table("discovery_moderation_events")
    op.drop_index(
        "ix_discovery_suggestions_status",
        table_name="discovery_suggestions",
    )
    op.drop_table("discovery_suggestions")
    # Standalone: road ratings were deliberately never linked to a suggestion,
    # because a rating carried no identity to link with.
    op.drop_index(
        "ix_discovery_road_ratings_source",
        table_name="discovery_road_ratings",
    )
    op.drop_table("discovery_road_ratings")


def downgrade() -> None:
    op.create_table(
        "discovery_suggestions",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("client_submission_id", sa.String(length=128), nullable=False),
        sa.Column("request_hash", sa.LargeBinary(length=32), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column("action", sa.String(length=16), nullable=False),
        sa.Column("target_feature_id", sa.String(length=128), nullable=True),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("evidence_url", sa.String(length=500), nullable=True),
        sa.Column("geometry_json", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("submitted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reviewer", sa.String(length=120), nullable=True),
        sa.Column("moderation_reason", sa.Text(), nullable=True),
        sa.Column("published_feature_id", sa.String(length=128), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "client_submission_id",
            name="uq_discovery_suggestion_client_submission",
        ),
    )
    op.create_index(
        "ix_discovery_suggestions_status",
        "discovery_suggestions",
        ["status", "submitted_at"],
    )
    op.create_table(
        "discovery_moderation_events",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("suggestion_id", sa.String(length=36), nullable=False),
        sa.Column("action", sa.String(length=24), nullable=False),
        sa.Column("actor", sa.String(length=120), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["suggestion_id"],
            ["discovery_suggestions.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_discovery_moderation_suggestion",
        "discovery_moderation_events",
        ["suggestion_id", "created_at"],
    )
    op.create_table(
        "discovery_features",
        sa.Column("id", sa.String(length=128), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("geometry_json", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("confidence", sa.String(length=16), nullable=False),
        sa.Column("source_name", sa.String(length=120), nullable=False),
        sa.Column("source_feature_id", sa.String(length=128), nullable=False),
        sa.Column("source_url", sa.String(length=500), nullable=True),
        sa.Column("warning", sa.Text(), nullable=False),
        sa.Column("approved_revision_id", sa.String(length=36), nullable=False),
        sa.Column("last_verified_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["approved_revision_id"],
            ["discovery_suggestions.id"],
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_discovery_features_public",
        "discovery_features",
        ["status", "category"],
    )
    op.create_table(
        "discovery_road_ratings",
        sa.Column("feature_id", sa.String(length=128), nullable=False),
        sa.Column("catalogue_version", sa.String(length=64), nullable=False),
        sa.Column("verdict", sa.String(length=24), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column("source_feature_id", sa.String(length=128), nullable=True),
        sa.Column("rating_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("first_rated_on", sa.Date(), nullable=False),
        sa.Column("last_rated_on", sa.Date(), nullable=False),
        sa.PrimaryKeyConstraint(
            "feature_id",
            "catalogue_version",
            "verdict",
            name="pk_discovery_road_ratings",
        ),
    )
    op.create_index(
        "ix_discovery_road_ratings_source",
        "discovery_road_ratings",
        ["source_feature_id"],
        unique=False,
    )
