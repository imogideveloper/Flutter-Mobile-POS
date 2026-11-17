"""Tutup buku (IMOGI no. 78): periode pembukuan yang dikunci.

Revision ID: 0033
Revises: 0032
Create Date: 2026-11-17
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0033"
down_revision: Union[str, None] = "0032"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS tutup_buku (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id      uuid NOT NULL REFERENCES toko(id),
  sampai       date NOT NULL,
  ditutup_oleh uuid REFERENCES pengguna(id),
  catatan      text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at   timestamptz
);
CREATE INDEX IF NOT EXISTS idx_tutup_buku_toko ON tutup_buku (toko_id, sampai);
CREATE TRIGGER trg_tutup_buku_updated_at BEFORE UPDATE ON tutup_buku FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS tutup_buku;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
