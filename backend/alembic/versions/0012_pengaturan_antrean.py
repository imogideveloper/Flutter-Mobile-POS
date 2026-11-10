"""Pengaturan nomor antrian: awalan dan angka awal per outlet (IMOGI no. 34).

Revision ID: 0012
Revises: 0011
Create Date: 2026-11-10
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0012"
down_revision: Union[str, None] = "0011"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE pengaturan_outlet ADD COLUMN IF NOT EXISTS antrean_awalan VARCHAR(5) NOT NULL DEFAULT 'A';
ALTER TABLE pengaturan_outlet ADD COLUMN IF NOT EXISTS antrean_mulai INTEGER NOT NULL DEFAULT 1;
"""

_DOWNGRADE_SQL = """
ALTER TABLE pengaturan_outlet DROP COLUMN IF EXISTS antrean_mulai;
ALTER TABLE pengaturan_outlet DROP COLUMN IF EXISTS antrean_awalan;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
