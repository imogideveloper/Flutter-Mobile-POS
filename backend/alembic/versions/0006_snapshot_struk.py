"""Temuan A.2 (tahap 5) - transaksi.snapshot_struk: JSON lengkap (StrukData
+ PengaturanStrukData) yang dipakai lib/core/struk/penyusun_struk.dart
SAAT transaksi dibuat - disimpan apa adanya dari HP (push) supaya cetak
ulang nanti PERSIS sama walau pengaturan outlet/harga berubah belakangan.
NULL = transaksi lama (sebelum kolom ini ada) atau client lama yang belum
kirim snapshot - cetak ulang utk baris semacam itu turun ke rekonstruksi
dari data saat ini (keterbatasan lama, dicatat di docs/aturan_harga.md).

Revision ID: 0006
Revises: 0005
Create Date: 2026-10-13
"""

from typing import Sequence, Union

from alembic import op

revision: str = "0006"
down_revision: Union[str, None] = "0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE transaksi ADD COLUMN snapshot_struk jsonb;
"""

_DOWNGRADE_SQL = """
ALTER TABLE transaksi DROP COLUMN IF EXISTS snapshot_struk;
"""


def upgrade() -> None:
    op.execute(_UPGRADE_SQL)


def downgrade() -> None:
    op.execute(_DOWNGRADE_SQL)
