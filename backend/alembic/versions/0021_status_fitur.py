"""Status pengembangan fitur (dashboard Administrator): belum/sedang/sudah/tidak_relevan.

Revision ID: 0021
Revises: 0020
Create Date: 2026-11-15
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0021"
down_revision: Union[str, None] = "0020"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE fitur ADD COLUMN IF NOT EXISTS status_dev varchar(15) NOT NULL DEFAULT 'belum';
ALTER TABLE fitur ADD COLUMN IF NOT EXISTS catatan_dev text;
ALTER TABLE fitur ADD COLUMN IF NOT EXISTS uji_hp boolean NOT NULL DEFAULT false;
ALTER TABLE fitur ADD CONSTRAINT ck_fitur_status_dev CHECK (status_dev IN ('belum','sedang','sudah','tidak_relevan'));
"""

_DOWNGRADE_SQL = """
ALTER TABLE fitur DROP CONSTRAINT IF EXISTS ck_fitur_status_dev;
ALTER TABLE fitur DROP COLUMN IF EXISTS uji_hp;
ALTER TABLE fitur DROP COLUMN IF EXISTS catatan_dev;
ALTER TABLE fitur DROP COLUMN IF EXISTS status_dev;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
