"""Batas margin per outlet untuk penanda margin rendah (IMOGI no. 37).

Revision ID: 0016
Revises: 0015
Create Date: 2026-11-13
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0016"
down_revision: Union[str, None] = "0015"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE pengaturan_outlet ADD COLUMN IF NOT EXISTS batas_margin INTEGER NOT NULL DEFAULT 50;
"""

_DOWNGRADE_SQL = """
ALTER TABLE pengaturan_outlet DROP COLUMN IF EXISTS batas_margin;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
