"""Kategori: masuk tiket dapur atau tidak (IMOGI no. 35).

Revision ID: 0013
Revises: 0012
Create Date: 2026-11-10
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0013"
down_revision: Union[str, None] = "0012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE kategori ADD COLUMN IF NOT EXISTS masuk_tiket_dapur BOOLEAN NOT NULL DEFAULT TRUE;
"""

_DOWNGRADE_SQL = """
ALTER TABLE kategori DROP COLUMN IF EXISTS masuk_tiket_dapur;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
