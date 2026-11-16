"""Peran bawaan kru F&B: "Barista & Dapur" dan "Gudang" (panduan IMOGI, Batch B).

Hak akses awal sengaja sempit (lihat docs/perlu_konfirmasi.md Z8); pemilik bisa
mengubahnya lewat peran kustom.

Revision ID: 0028
Revises: 0027
Create Date: 2026-11-16
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0028"
down_revision: Union[str, None] = "0027"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
INSERT INTO role (nama, is_system)
SELECT 'Barista & Dapur', true
WHERE NOT EXISTS (SELECT 1 FROM role WHERE nama = 'Barista & Dapur' AND is_system);

INSERT INTO role (nama, is_system)
SELECT 'Gudang', true
WHERE NOT EXISTS (SELECT 1 FROM role WHERE nama = 'Gudang' AND is_system);

INSERT INTO role_izin (role_id, izin_id)
SELECT r.id, i.id FROM role r CROSS JOIN izin i
WHERE r.nama = 'Barista & Dapur' AND r.is_system AND i.kode IN ('transaksi.buat')
  AND NOT EXISTS (SELECT 1 FROM role_izin x WHERE x.role_id = r.id AND x.izin_id = i.id);

INSERT INTO role_izin (role_id, izin_id)
SELECT r.id, i.id FROM role r CROSS JOIN izin i
WHERE r.nama = 'Gudang' AND r.is_system AND i.kode IN ('stok.kelola', 'pembelian.kelola')
  AND NOT EXISTS (SELECT 1 FROM role_izin x WHERE x.role_id = r.id AND x.izin_id = i.id);
"""

_DOWNGRADE_SQL = """
DELETE FROM role_izin WHERE role_id IN (SELECT id FROM role WHERE nama IN ('Barista & Dapur', 'Gudang') AND is_system);
DELETE FROM role WHERE nama IN ('Barista & Dapur', 'Gudang') AND is_system
  AND NOT EXISTS (SELECT 1 FROM pengguna p WHERE p.role_id = role.id);
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
