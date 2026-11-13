"""Promo ulang tahun: penanda promo khusus pelanggan yang berulang tahun (IMOGI no. 56).

Revision ID: 0017
Revises: 0016
Create Date: 2026-11-13
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0017"
down_revision: Union[str, None] = "0016"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE promo ADD COLUMN IF NOT EXISTS khusus_ulang_tahun BOOLEAN NOT NULL DEFAULT FALSE;
"""

_DOWNGRADE_SQL = """
ALTER TABLE promo DROP COLUMN IF EXISTS khusus_ulang_tahun;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
