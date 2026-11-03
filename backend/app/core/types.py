"""Tipe kolom portable (Postgres asli, SQLite utk pytest in-memory) dan
mixin kolom standar yang wajib ada di semua tabel sesuai konvensi dokumen:
UUID PK, created_at/updated_at/deleted_at (soft delete)."""

import uuid
from datetime import datetime
from decimal import Decimal

from sqlalchemy import JSON, DateTime, Numeric, String, Uuid, func
from sqlalchemy.dialects.postgresql import INET, JSONB
from sqlalchemy.orm import Mapped, mapped_column

# JSONB asli di Postgres, fallback JSON biasa di SQLite (pytest in-memory).
JSONB_PORTABLE = JSON().with_variant(JSONB(), "postgresql")

# inet asli di Postgres (migration 0001 - audit_log.ip_address), fallback
# VARCHAR biasa di SQLite (pytest in-memory, tidak punya tipe inet). TANPA
# ini, asyncpg menolak bind VARCHAR ke kolom inet sungguhan dgn
# DatatypeMismatchError - celah ini sempat lolos pytest krn SQLite test
# tidak pernah memvalidasi tipe sampai sedetail ini.
Inet = String(45).with_variant(INET(), "postgresql")

# Semua nilai uang: Decimal, numeric(14,2) - tidak pernah float/double.
Money = Numeric(14, 2)
Qty = Numeric(14, 4)


class CreatedAtOnlyMixin:
    """Utk tabel relasi murni (role_izin, akses_outlet, promo_produk, dst.)
    yang di skema resmi hanya punya created_at, tanpa updated_at/deleted_at."""

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class UUIDPkMixin:
    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    # onupdate=func.now() adalah fallback ORM - trigger Postgres `set_updated_at()`
    # (migration 0001) tetap jadi sumber kebenaran utk UPDATE lewat SQL manual
    # di luar ORM. SQLite test tidak menjalankan trigger Postgres, jadi fallback
    # ini juga yang membuat perilaku test konsisten dgn produksi.
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


MoneyType = Decimal
