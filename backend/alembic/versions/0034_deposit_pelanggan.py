"""Deposit pelanggan / pendapatan diterima di muka (IMOGI no. 79): buku mutasi saldo deposit.

Revision ID: 0034
Revises: 0033
Create Date: 2026-11-17
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0034"
down_revision: Union[str, None] = "0033"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS deposit_pelanggan (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id          uuid NOT NULL REFERENCES toko(id),
  pelanggan_id     uuid NOT NULL REFERENCES pelanggan(id),
  jenis            varchar(10) NOT NULL CHECK (jenis IN ('topup','pakai','koreksi')),
  jumlah           numeric(14,2) NOT NULL CHECK (jumlah > 0),
  metode_bayar_id  uuid REFERENCES metode_bayar(id),
  catatan          text,
  dibuat_oleh      uuid REFERENCES pengguna(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  deleted_at       timestamptz
);
CREATE INDEX IF NOT EXISTS idx_deposit_pelanggan ON deposit_pelanggan (toko_id, pelanggan_id);
CREATE TRIGGER trg_deposit_pelanggan_updated_at BEFORE UPDATE ON deposit_pelanggan FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS deposit_pelanggan;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
