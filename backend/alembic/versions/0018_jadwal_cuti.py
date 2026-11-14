"""Jadwal shift mingguan dan pengajuan cuti/sakit/izin (IMOGI no. 63).

Revision ID: 0018
Revises: 0017
Create Date: 2026-11-14
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0018"
down_revision: Union[str, None] = "0017"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
CREATE TABLE IF NOT EXISTS jadwal_kerja (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id      uuid NOT NULL REFERENCES toko(id),
  pengguna_id  uuid NOT NULL REFERENCES pengguna(id),
  hari         integer NOT NULL CHECK (hari BETWEEN 1 AND 7),
  shift        varchar(10) NOT NULL CHECK (shift IN ('libur','pagi','siang')),
  jam_mulai    varchar(5),
  jam_selesai  varchar(5),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  deleted_at   timestamptz,
  CONSTRAINT uq_jadwal_kerja_pengguna_hari UNIQUE (pengguna_id, hari)
);
CREATE TRIGGER trg_jadwal_kerja_updated_at BEFORE UPDATE ON jadwal_kerja FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE IF NOT EXISTS pengajuan_cuti (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id            uuid NOT NULL REFERENCES toko(id),
  pengguna_id        uuid NOT NULL REFERENCES pengguna(id),
  jenis              varchar(10) NOT NULL CHECK (jenis IN ('cuti','sakit','izin')),
  tanggal_mulai      date NOT NULL,
  tanggal_selesai    date NOT NULL,
  alasan             text,
  status             varchar(12) NOT NULL DEFAULT 'menunggu' CHECK (status IN ('menunggu','disetujui','ditolak','dibatalkan')),
  diputuskan_oleh    uuid REFERENCES pengguna(id),
  diputuskan_pada    timestamptz,
  catatan_keputusan  text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz,
  CONSTRAINT ck_pengajuan_cuti_tanggal CHECK (tanggal_selesai >= tanggal_mulai)
);
CREATE INDEX IF NOT EXISTS idx_pengajuan_cuti_toko ON pengajuan_cuti (toko_id, tanggal_mulai);
CREATE TRIGGER trg_pengajuan_cuti_updated_at BEFORE UPDATE ON pengajuan_cuti FOR EACH ROW EXECUTE FUNCTION set_updated_at();
"""

_DOWNGRADE_SQL = """
DROP TABLE IF EXISTS pengajuan_cuti;
DROP TABLE IF EXISTS jadwal_kerja;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
