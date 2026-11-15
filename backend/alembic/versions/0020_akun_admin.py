"""Akun Administrator platform (login dashboard admin).

Revision ID: 0020
Revises: 0019
Create Date: 2026-11-15
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0020"
down_revision: Union[str, None] = "0019"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS akun_admin (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email          varchar(150) NOT NULL UNIQUE,
  nama           varchar(100) NOT NULL,
  password_hash  varchar(100) NOT NULL,
  aktif          boolean NOT NULL DEFAULT true,
  terakhir_login timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_akun_admin_updated_at BEFORE UPDATE ON akun_admin FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS akun_admin;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
