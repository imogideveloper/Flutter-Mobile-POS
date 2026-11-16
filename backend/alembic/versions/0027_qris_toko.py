"""Toko: gambar QRIS statis milik usaha (IMOGI no. 10).

Revision ID: 0027
Revises: 0026
Create Date: 2026-11-16
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0027"
down_revision: Union[str, None] = "0026"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE toko ADD COLUMN IF NOT EXISTS qris_url text;
"""

_DOWNGRADE_SQL = """
ALTER TABLE toko DROP COLUMN IF EXISTS qris_url;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
