"""Metode bayar: pengaturan wajib nomor referensi (kartu/EDC, transfer, e-wallet) - IMOGI no. 13.

Revision ID: 0023
Revises: 0022
Create Date: 2026-11-15
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0023"
down_revision: Union[str, None] = "0022"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE metode_bayar ADD COLUMN IF NOT EXISTS wajib_referensi boolean NOT NULL DEFAULT false;
"""

_DOWNGRADE_SQL = """
ALTER TABLE metode_bayar DROP COLUMN IF EXISTS wajib_referensi;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
