"""Delapan izin baru dari daftar 18 hak akses panduan IMOGI (hlm. 28-29).

Pemberian "paritas": setiap peran (bawaan maupun buatan) yang sudah punya
izin lama otomatis mendapat izin padanannya, jadi perilaku yang berjalan
sekarang tidak berubah. Penegakan izin baru dilakukan di tahap berikutnya.

  bon.jual             <- transaksi.buat
  bon.lihat            <- transaksi.buat
  pesanan.status       <- transaksi.buat
  persetujuan.pin      <- transaksi.batal_pesanan
  produk.lihat_margin  <- produk.kelola
  stok.opname_posting  <- stok.kelola
  pengeluaran.catat    <- laporan.lihat
  laporan.keuangan     <- laporan.lihat

Revision ID: 0035
Revises: 0034
Create Date: 2026-11-22
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0035"
down_revision: Union[str, None] = "0034"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
INSERT INTO izin (kode, modul, deskripsi) VALUES
  ('bon.jual', 'penjualan', 'Jual bon / uang muka (DP)'),
  ('bon.lihat', 'penjualan', 'Melihat daftar bon'),
  ('pesanan.status', 'penjualan', 'Mengubah status pesanan dan antrian'),
  ('persetujuan.pin', 'penjualan', 'Menyetujui tindakan dengan PIN'),
  ('produk.lihat_margin', 'produk', 'Melihat harga beli dan margin'),
  ('stok.opname_posting', 'stok', 'Memposting hasil stok opname'),
  ('pengeluaran.catat', 'laporan', 'Mencatat pengeluaran'),
  ('laporan.keuangan', 'laporan', 'Melihat laba rugi, pajak, dan margin')
ON CONFLICT (kode) DO NOTHING;

INSERT INTO role_izin (role_id, izin_id)
SELECT ri.role_id, baru.id
FROM role_izin ri
JOIN izin lama ON lama.id = ri.izin_id
JOIN (VALUES
  ('transaksi.buat', 'bon.jual'),
  ('transaksi.buat', 'bon.lihat'),
  ('transaksi.buat', 'pesanan.status'),
  ('transaksi.batal_pesanan', 'persetujuan.pin'),
  ('produk.kelola', 'produk.lihat_margin'),
  ('stok.kelola', 'stok.opname_posting'),
  ('laporan.lihat', 'pengeluaran.catat'),
  ('laporan.lihat', 'laporan.keuangan')
) AS peta(kode_lama, kode_baru) ON peta.kode_lama = lama.kode
JOIN izin baru ON baru.kode = peta.kode_baru
WHERE NOT EXISTS (
  SELECT 1 FROM role_izin x WHERE x.role_id = ri.role_id AND x.izin_id = baru.id
);

-- Panduan: kru F&B (Barista & Dapur) hanya mengurus status pesanan, bukan bon.
DELETE FROM role_izin WHERE role_id IN (SELECT id FROM role WHERE nama = 'Barista & Dapur' AND is_system)
  AND izin_id IN (SELECT id FROM izin WHERE kode IN ('bon.jual', 'bon.lihat'));
"""

_DOWNGRADE_SQL = """
DELETE FROM role_izin WHERE izin_id IN (SELECT id FROM izin WHERE kode IN
  ('bon.jual','bon.lihat','pesanan.status','persetujuan.pin','produk.lihat_margin',
   'stok.opname_posting','pengeluaran.catat','laporan.keuangan'));
DELETE FROM izin WHERE kode IN
  ('bon.jual','bon.lihat','pesanan.status','persetujuan.pin','produk.lihat_margin',
   'stok.opname_posting','pengeluaran.catat','laporan.keuangan');
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
