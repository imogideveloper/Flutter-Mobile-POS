"""Tabel pengaturan_platform + nilai awal masa trial berdasarkan usia akun.

Arahan lead (2026-11-08): semua tier paket dibuka dulu tanpa pembatasan,
tier baru berlaku setelah usia akun (dihitung dari toko.created_at)
mencapai batas - awalnya 4 bulan, dan durasinya harus bisa dikonfigurasi
(nanti lewat dashboard admin Imogi). Nilai 0 = masa trial dimatikan.
Toko yang sudah ada ikut dihitung dari toko.created_at-nya.

Revision ID: 0009
Revises: 0008
Create Date: 2026-11-08
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0009"
down_revision: Union[str, None] = "0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE pengaturan_platform (
  kunci       varchar(50) PRIMARY KEY,
  nilai       text NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

INSERT INTO pengaturan_platform (kunci, nilai) VALUES
  ('usia_akun_bulan', '4'),
  ('trial_notifikasi_hari', '7');
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS pengaturan_platform;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
