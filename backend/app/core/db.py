from collections.abc import AsyncGenerator
from datetime import datetime

from sqlalchemy import DateTime
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .config import get_settings


class Base(DeclarativeBase):
    """Base class semua model. Lihat app/models/*.py - satu file per modul
    skema (bukan per tabel) sesuai rencana di B.2.

    type_annotation_map: TANPA ini, `Mapped[datetime]` polos (tanpa
    `mapped_column(DateTime(timezone=True))` eksplisit - mis.
    Langganan.mulai, Shift.dibuka_pada, Transaksi.tanggal) dipetakan
    SQLAlchemy ke `TIMESTAMP WITHOUT TIME ZONE`, padahal DDL resmi
    (migrasi 0001) mendefinisikan semua kolom timestamp bisnis sbg
    `timestamptz`. Mismatch ini LOLOS di seluruh test pytest (SQLite tidak
    membedakan aware/naive di level skema) dan baru menyebabkan error nyata
    (asyncpg "can't subtract offset-naive and offset-aware datetimes")
    begitu endpoint registrasi toko dijalankan ke Postgres sungguhan utk
    PERTAMA KALINYA. Field yg SUDAH eksplisit (mis. TimestampMixin di
    types.py) tidak terpengaruh - map ini cuma dipakai kalau tidak ada
    override eksplisit."""

    type_annotation_map = {datetime: DateTime(timezone=True)}


_settings = get_settings()
engine = create_async_engine(_settings.database_url, pool_pre_ping=True, future=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session
