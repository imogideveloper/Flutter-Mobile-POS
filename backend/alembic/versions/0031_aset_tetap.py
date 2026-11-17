"""Aset tetap & penyusutan garis lurus (IMOGI no. 83).

Revision ID: 0031
Revises: 0030
Create Date: 2026-11-17
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0031"
down_revision: Union[str, None] = "0030"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS aset_tetap (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id           uuid NOT NULL REFERENCES toko(id),
  nama              varchar(150) NOT NULL,
  tanggal_perolehan date NOT NULL,
  harga_perolehan   numeric(14,2) NOT NULL CHECK (harga_perolehan > 0),
  nilai_residu      numeric(14,2) NOT NULL DEFAULT 0 CHECK (nilai_residu >= 0),
  umur_bulan        integer NOT NULL CHECK (umur_bulan > 0),
  catatan           text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  CHECK (nilai_residu < harga_perolehan)
);
CREATE INDEX IF NOT EXISTS idx_aset_tetap_toko ON aset_tetap (toko_id);
CREATE TRIGGER trg_aset_tetap_updated_at BEFORE UPDATE ON aset_tetap FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS aset_tetap;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
