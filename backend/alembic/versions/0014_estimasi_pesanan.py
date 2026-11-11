"""Estimasi selesai pesanan: lama pengerjaan bawaan per outlet (IMOGI no. 26).

Revision ID: 0014
Revises: 0013
Create Date: 2026-11-12
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0014"
down_revision: Union[str, None] = "0013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE pengaturan_outlet ADD COLUMN IF NOT EXISTS estimasi_menit INTEGER NOT NULL DEFAULT 0;
"""

_DOWNGRADE_SQL = """
ALTER TABLE pengaturan_outlet DROP COLUMN IF EXISTS estimasi_menit;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
