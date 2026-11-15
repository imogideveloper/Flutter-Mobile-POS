"""Metode bayar: daftar label tujuan pembayaran untuk rekonsiliasi (IMOGI no. 18).

Revision ID: 0025
Revises: 0024
Create Date: 2026-11-15
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0025"
down_revision: Union[str, None] = "0024"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE metode_bayar ADD COLUMN IF NOT EXISTS label_tujuan varchar(300);
"""

_DOWNGRADE_SQL = """
ALTER TABLE metode_bayar DROP COLUMN IF EXISTS label_tujuan;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
