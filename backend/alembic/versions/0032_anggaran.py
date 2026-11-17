"""Anggaran bulanan per kategori biaya (IMOGI no. 82).

Revision ID: 0032
Revises: 0031
Create Date: 2026-11-17
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0032"
down_revision: Union[str, None] = "0031"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS anggaran (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id     uuid NOT NULL REFERENCES toko(id),
  bulan       date NOT NULL CHECK (extract(day FROM bulan) = 1),
  kategori    varchar(30) NOT NULL,
  jumlah      numeric(14,2) NOT NULL CHECK (jumlah >= 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz,
  CONSTRAINT uq_anggaran_toko_bulan_kategori UNIQUE (toko_id, bulan, kategori)
);
CREATE TRIGGER trg_anggaran_updated_at BEFORE UPDATE ON anggaran FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS anggaran;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
