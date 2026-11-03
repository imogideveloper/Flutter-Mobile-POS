"""Temuan#2 (rapikan F3) - izin baru `transaksi.batal_pesanan`: approval
PIN owner/manajer wajib utk Kasir yang membatalkan pesanan tersimpan
(open bill) di atas nilai tertentu (default Rp0 - selalu, lihat
app/core/config.py::batas_approval_batal_pesanan). Role Owner/Manajer
ADALAH baris global (is_system=true, dibuat sekali di migrasi 0001) -
cukup satu INSERT role_izin per role di sini, bukan per-toko. Kasir
SENGAJA tidak diberi izin ini (persis pola transaksi.refund/void).

Revision ID: 0005
Revises: 0004
Create Date: 2026-10-13
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
INSERT INTO izin (kode, modul, deskripsi) VALUES
  ('transaksi.batal_pesanan', 'penjualan', 'Approval batalkan pesanan tersimpan');

INSERT INTO role_izin (role_id, izin_id)
SELECT r.id, i.id FROM role r CROSS JOIN izin i
WHERE r.nama IN ('Owner', 'Manajer') AND r.is_system AND i.kode = 'transaksi.batal_pesanan';
"""

_DOWNGRADE_SQL = """
DELETE FROM role_izin WHERE izin_id IN (SELECT id FROM izin WHERE kode = 'transaksi.batal_pesanan');
DELETE FROM izin WHERE kode = 'transaksi.batal_pesanan';
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
