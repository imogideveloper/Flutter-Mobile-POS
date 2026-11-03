"""Tahap 3b-1: kasbon (bayar dengan utang), DP, cicilan, pelunasan.

- pembayaran.shift_id (nullable, FK shift): cicilan/pelunasan yang
  diterima di shift LAIN dari shift transaksi asal harus masuk kas shift
  TEMPAT uangnya benar2 diterima - sebelum ini, pembayaran tidak punya
  kolom shift sendiri sama sekali (kas_seharusnya salah atribusi lewat
  join ke transaksi.shift_id, lihat shift_service.py).
- pelanggan.batas_kasbon (numeric, nullable): opsional, kalau diisi
  kasbon baru yang membuat total utang pelanggan melebihi batas ditolak.
- refund.kas_dikembalikan (numeric, default 0): uang tunai/transfer yang
  BENAR2 keluar dari suatu refund - beda dari `refund.total` (nilai
  barang) utk refund transaksi kasbon yang belum lunas, krn nilai itu
  mengurangi sisa_tagihan dulu sebelum sisanya (kalau ada) dikembalikan
  sbg uang (aturan #5).
- Index tambahan utk laporan piutang (ix_transaksi_kasbon sudah ada sejak
  0001, per toko+jatuh_tempo) - ix_pembayaran_shift utk query
  kas_seharusnya per shift jadi index-scan, bukan seq-scan; ix_transaksi_
  pelanggan_kasbon utk agregasi piutang PER PELANGGAN (laporan #6).

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-13
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE pembayaran ADD COLUMN shift_id uuid REFERENCES shift(id);
ALTER TABLE pelanggan ADD COLUMN batas_kasbon numeric(14,2);
ALTER TABLE refund ADD COLUMN kas_dikembalikan numeric(14,2) NOT NULL DEFAULT 0;

CREATE INDEX ix_pembayaran_shift ON pembayaran (shift_id);
CREATE INDEX ix_transaksi_pelanggan_kasbon ON transaksi (pelanggan_id, jatuh_tempo)
  WHERE status_bayar <> 'lunas' AND deleted_at IS NULL;
"""

_DOWNGRADE_SQL = """
DROP INDEX IF EXISTS ix_transaksi_pelanggan_kasbon;
DROP INDEX IF EXISTS ix_pembayaran_shift;
ALTER TABLE refund DROP COLUMN kas_dikembalikan;
ALTER TABLE pelanggan DROP COLUMN batas_kasbon;
ALTER TABLE pembayaran DROP COLUMN shift_id;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
