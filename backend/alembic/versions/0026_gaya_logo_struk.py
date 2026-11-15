"""Pengaturan outlet: gaya logo struk siap pakai (IMOGI no. 24).

Revision ID: 0026
Revises: 0025
Create Date: 2026-11-15
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0026"
down_revision: Union[str, None] = "0025"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE pengaturan_outlet ADD COLUMN IF NOT EXISTS gaya_logo varchar(12) NOT NULL DEFAULT 'unggah';
ALTER TABLE pengaturan_outlet ADD CONSTRAINT ck_pengaturan_outlet_gaya_logo CHECK (gaya_logo IN ('unggah','lingkaran','cincin','inisial'));
"""

_DOWNGRADE_SQL = """
ALTER TABLE pengaturan_outlet DROP CONSTRAINT IF EXISTS ck_pengaturan_outlet_gaya_logo;
ALTER TABLE pengaturan_outlet DROP COLUMN IF EXISTS gaya_logo;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
