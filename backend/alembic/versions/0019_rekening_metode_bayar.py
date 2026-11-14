"""Rekening tujuan pada metode bayar transfer/e-wallet (IMOGI no. 14).

Revision ID: 0019
Revises: 0018
Create Date: 2026-11-14
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0019"
down_revision: Union[str, None] = "0018"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE metode_bayar ADD COLUMN IF NOT EXISTS rekening_bank varchar(50);
ALTER TABLE metode_bayar ADD COLUMN IF NOT EXISTS rekening_nomor varchar(40);
ALTER TABLE metode_bayar ADD COLUMN IF NOT EXISTS rekening_nama varchar(80);
"""

_DOWNGRADE_SQL = """
ALTER TABLE metode_bayar DROP COLUMN IF EXISTS rekening_nama;
ALTER TABLE metode_bayar DROP COLUMN IF EXISTS rekening_nomor;
ALTER TABLE metode_bayar DROP COLUMN IF EXISTS rekening_bank;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
