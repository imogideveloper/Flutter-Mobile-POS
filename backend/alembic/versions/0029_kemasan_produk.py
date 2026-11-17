"""Jual per kemasan (IMOGI no. 43): katalog kemasan per produk + snapshot kemasan di item transaksi.

Stok tetap dihitung di satuan dasar produk. Baris transaksi menyimpan jumlah KEMASAN dan harga per
kemasan (hitungan uang tidak berubah); stok berkurang sebesar qty x isi_kemasan.

Revision ID: 0029
Revises: 0028
Create Date: 2026-11-17
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0029"
down_revision: Union[str, None] = "0028"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS produk_kemasan (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id     uuid NOT NULL REFERENCES toko(id),
  produk_id   uuid NOT NULL REFERENCES produk(id),
  nama        varchar(50) NOT NULL,
  isi         numeric(14,4) NOT NULL CHECK (isi > 1),
  harga       numeric(14,2) NOT NULL CHECK (harga >= 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);
CREATE INDEX IF NOT EXISTS idx_produk_kemasan_produk ON produk_kemasan (produk_id);
CREATE TRIGGER trg_produk_kemasan_updated_at BEFORE UPDATE ON produk_kemasan FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE item_transaksi ADD COLUMN IF NOT EXISTS isi_kemasan numeric(14,4) NOT NULL DEFAULT 1 CHECK (isi_kemasan >= 1);
ALTER TABLE item_transaksi ADD COLUMN IF NOT EXISTS nama_kemasan varchar(50);
"""

_DOWNGRADE_SQL = """
ALTER TABLE item_transaksi DROP COLUMN IF EXISTS nama_kemasan;
ALTER TABLE item_transaksi DROP COLUMN IF EXISTS isi_kemasan;
DROP TABLE IF EXISTS produk_kemasan;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
