"""F3.F.2 - permintaan_upgrade: owner toko menekan "Saya tertarik upgrade"
di halaman Paket langganan - TIDAK ada pembayaran di dalam app (dilarang
eksplisit oleh dokumen F3.F.2), baris ini murni catatan minat utk
ditindaklanjuti admin platform manual lewat kanal lain. Trigger
updated_at ditambahkan manual di sini (beda dari tabel-tabel migrasi 0001
yang dapat trigger-nya otomatis lewat loop information_schema SAAT ITU -
tabel yang lahir belakangan wajib trigger sendiri).

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-13
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE permintaan_upgrade (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  paket_tujuan_id uuid NOT NULL REFERENCES paket(id),
  jumlah_outlet   int NOT NULL DEFAULT 1 CHECK (jumlah_outlet > 0),
  periode         varchar(10) NOT NULL DEFAULT 'bulanan' CHECK (periode IN ('bulanan','tahunan')),
  status          varchar(20) NOT NULL DEFAULT 'baru'
                  CHECK (status IN ('baru','dihubungi','selesai','batal')),
  catatan         text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE INDEX ix_permintaan_upgrade_toko ON permintaan_upgrade (toko_id, status);

CREATE TRIGGER trg_permintaan_upgrade_updated_at BEFORE UPDATE ON permintaan_upgrade
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS permintaan_upgrade;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
