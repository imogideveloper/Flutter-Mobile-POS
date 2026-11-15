"""Perbaikan 0020: akun_admin kurang kolom deleted_at yang dipakai model (TimestampMixin).

Tanpa kolom ini INSERT akun admin gagal di Postgres (tes SQLite tidak
menangkapnya karena tabel uji dibuat dari model, bukan dari migrasi).

Revision ID: 0022
Revises: 0021
Create Date: 2026-11-15
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0022"
down_revision: Union[str, None] = "0021"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE akun_admin ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
"""

_DOWNGRADE_SQL = """
ALTER TABLE akun_admin DROP COLUMN IF EXISTS deleted_at;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
