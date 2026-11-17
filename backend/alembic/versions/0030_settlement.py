"""Settlement & rekonsiliasi QRIS/e-wallet (IMOGI no. 74): pencatatan dana yang diterima dari penyedia pembayaran.

Revision ID: 0030
Revises: 0029
Create Date: 2026-11-17
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0030"
down_revision: Union[str, None] = "0029"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS settlement (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id          uuid NOT NULL REFERENCES toko(id),
  metode_bayar_id  uuid NOT NULL REFERENCES metode_bayar(id),
  tanggal          date NOT NULL,
  jumlah_diterima  numeric(14,2) NOT NULL CHECK (jumlah_diterima >= 0),
  biaya            numeric(14,2) NOT NULL DEFAULT 0 CHECK (biaya >= 0),
  referensi        varchar(100),
  catatan          text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz
);
CREATE INDEX IF NOT EXISTS idx_settlement_toko_tanggal ON settlement (toko_id, tanggal);
CREATE TRIGGER trg_settlement_updated_at BEFORE UPDATE ON settlement FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS settlement;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
