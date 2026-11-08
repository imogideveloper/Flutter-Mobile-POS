"""Status pesanan alur IMOGI: tambah tahap 'diantar' dan 'selesai'.

Alur IMOGI (Panduan Menu Pengaturan 4.2): Baru, Diproses, Siap, (Diantar), Selesai; katering:
Dipesan, Dimasak, Siap kirim, Dikirim, Selesai. Kode tahap yang tersimpan tetap sama
(baru, diproses, siap, diantar, selesai); 'diambil' dipertahankan untuk data lama dan
dianggap setara 'selesai'.

Revision ID: 0011
Revises: 0010
Create Date: 2026-11-09
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0011"
down_revision: Union[str, None] = "0010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE transaksi DROP CONSTRAINT IF EXISTS transaksi_status_pesanan_check;
ALTER TABLE transaksi DROP CONSTRAINT IF EXISTS ck_transaksi_status_pesanan;
ALTER TABLE transaksi ADD CONSTRAINT ck_transaksi_status_pesanan
  CHECK (status_pesanan IS NULL OR status_pesanan IN ('baru','diproses','siap','diantar','selesai','diambil','dibatalkan'));
"""

_DOWNGRADE_SQL = """
UPDATE transaksi SET status_pesanan = 'siap' WHERE status_pesanan = 'diantar';
UPDATE transaksi SET status_pesanan = 'diambil' WHERE status_pesanan = 'selesai';
ALTER TABLE transaksi DROP CONSTRAINT IF EXISTS ck_transaksi_status_pesanan;
ALTER TABLE transaksi ADD CONSTRAINT ck_transaksi_status_pesanan
  CHECK (status_pesanan IS NULL OR status_pesanan IN ('baru','diproses','siap','diambil','dibatalkan'));
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
