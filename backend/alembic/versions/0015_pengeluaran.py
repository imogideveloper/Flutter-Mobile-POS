"""Pengeluaran & biaya operasional (IMOGI no. 67).

Revision ID: 0015
Revises: 0014
Create Date: 2026-11-12
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0015"
down_revision: Union[str, None] = "0014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS pengeluaran (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id      uuid NOT NULL REFERENCES toko(id),
  outlet_id    uuid REFERENCES outlet(id),
  tanggal      date NOT NULL,
  kategori     varchar(30) NOT NULL CHECK (kategori IN ('belanja_bahan','gas_lpg','kemasan','gaji','sewa','listrik_air','pemasaran','perawatan','lainnya')),
  jumlah       numeric(14,2) NOT NULL CHECK (jumlah > 0),
  catatan      text,
  dibuat_oleh  uuid REFERENCES pengguna(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at   timestamptz
);
CREATE INDEX IF NOT EXISTS idx_pengeluaran_toko_tanggal ON pengeluaran (toko_id, tanggal);
CREATE TRIGGER trg_pengeluaran_updated_at BEFORE UPDATE ON pengeluaran FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS pengeluaran;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
