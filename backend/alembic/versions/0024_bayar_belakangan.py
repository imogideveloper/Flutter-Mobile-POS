"""Transaksi: penanda order diterima dulu, dibayar belakangan (IMOGI no. 27).

Revision ID: 0024
Revises: 0023
Create Date: 2026-11-15
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0024"
down_revision: Union[str, None] = "0023"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE transaksi ADD COLUMN IF NOT EXISTS bayar_belakangan boolean NOT NULL DEFAULT false;
"""

_DOWNGRADE_SQL = """
ALTER TABLE transaksi DROP COLUMN IF EXISTS bayar_belakangan;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
