"""QRIS & Virtual Account LANGSUNG di app (tanpa redirect browser) - lewat
API Xendit yang lebih baru (/v3/payment_requests, satu endpoint utk QRIS
maupun VA via channel_code), bukan Invoice API lama (migrasi 0007) yang
selalu bikin halaman checkout ter-hosted Xendit. Kolom invoice_id lama
TETAP ada (jangan dihapus - baris lama/jalur lama masih valid), kolom
baru ini dipakai jalur baru saja.

Revision ID: 0008
Revises: 0007
Create Date: 2026-10-22
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0008"
down_revision: Union[str, None] = "0007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_UPGRADE_SQL = """
ALTER TABLE permintaan_upgrade
  ADD COLUMN xendit_payment_request_id varchar(100),
  ADD COLUMN metode_bayar varchar(30),
  ADD COLUMN detail_bayar jsonb;

CREATE UNIQUE INDEX ux_permintaan_upgrade_xendit_payment_request_id
  ON permintaan_upgrade (xendit_payment_request_id)
  WHERE xendit_payment_request_id IS NOT NULL;
"""

_DOWNGRADE_SQL = """
DROP INDEX IF EXISTS ux_permintaan_upgrade_xendit_payment_request_id;
ALTER TABLE permintaan_upgrade
  DROP COLUMN IF EXISTS xendit_payment_request_id,
  DROP COLUMN IF EXISTS metode_bayar,
  DROP COLUMN IF EXISTS detail_bayar;
"""


def upgrade() -> None:
    for statement in split_statements(_UPGRADE_SQL):
        op.execute(statement)


def downgrade() -> None:
    for statement in split_statements(_DOWNGRADE_SQL):
        op.execute(statement)
