"""Isi paket_fitur.batas utk fitur laporan_dasar - skema 0001 (seed resmi
dari dokumen) membuka paket_fitur lewat cross-join `tingkat <= urutan`
TANPA pernah mengisi kolom `batas` sama sekali (NULL semua baris), jadi
tidak ada pembatasan rentang laporan per paket sama sekali. Migrasi ini
HANYA mengisi `batas` utk satu fitur (`laporan_dasar`) - tingkat 0 (lihat
dokumen tech stack bagian 4.2, keputusan bisnis: toko Gratis cuma bisa
lihat laporan 30 hari ke belakang, Pro 365 hari, Bisnis tanpa batas).

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-11
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
UPDATE paket_fitur pf
SET batas = 30
FROM paket p, fitur f
WHERE pf.paket_id = p.id AND pf.fitur_id = f.id AND p.nama = 'Gratis' AND f.kode = 'laporan_dasar';

UPDATE paket_fitur pf
SET batas = 365
FROM paket p, fitur f
WHERE pf.paket_id = p.id AND pf.fitur_id = f.id AND p.nama = 'Pro' AND f.kode = 'laporan_dasar';

-- Bisnis: tanpa batas - sudah NULL by default, eksplisit di sini supaya
-- migrasi ini idempotent & jelas niatnya (bukan kelupaan).
UPDATE paket_fitur pf
SET batas = NULL
FROM paket p, fitur f
WHERE pf.paket_id = p.id AND pf.fitur_id = f.id AND p.nama = 'Bisnis' AND f.kode = 'laporan_dasar';
"""

_DOWNGRADE_SQL = """
UPDATE paket_fitur pf
SET batas = NULL
FROM fitur f
WHERE pf.fitur_id = f.id AND f.kode = 'laporan_dasar';
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
