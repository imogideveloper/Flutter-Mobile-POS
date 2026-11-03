"""Pembayaran upgrade paket SUNGGUHAN lewat Xendit - sebelumnya
permintaan_upgrade murni catatan minat manual (lihat migrasi 0004,
F3.F.2 "TIDAK ada pembayaran di dalam app"). Keputusan itu DIBALIK atas
permintaan eksplisit pemilik produk: begitu bayar sukses, paket aktif
otomatis tanpa campur tangan admin. Kolom baru TIDAK mengubah CHECK
constraint `status` yang sudah ada (tetap baru/dihubungi/selesai/batal) -
alur baru cukup pakai 'baru' (invoice dibuat, menunggu bayar) ->
'selesai' (sudah dibayar & paket aktif) / 'batal' (invoice kedaluwarsa).

Revision ID: 0007
Revises: 0006
Create Date: 2026-10-21
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0007"
down_revision: Union[str, None] = "0006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE permintaan_upgrade
  ADD COLUMN xendit_invoice_id varchar(100),
  ADD COLUMN invoice_url text,
  ADD COLUMN jumlah_bayar numeric(14,2);

CREATE UNIQUE INDEX ux_permintaan_upgrade_xendit_invoice_id
  ON permintaan_upgrade (xendit_invoice_id)
  WHERE xendit_invoice_id IS NOT NULL;
"""

_DOWNGRADE_SQL = """
DROP INDEX IF EXISTS ux_permintaan_upgrade_xendit_invoice_id;
ALTER TABLE permintaan_upgrade
  DROP COLUMN IF EXISTS xendit_invoice_id,
  DROP COLUMN IF EXISTS invoice_url,
  DROP COLUMN IF EXISTS jumlah_bayar;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
