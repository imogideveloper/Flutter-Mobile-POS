"""Siapkan database SQLite lokal (file, bukan in-memory) untuk server dev
sungguhan - dipakai saat testing manual dari HP fisik (lihat README: belum
pernah dicoba jalan sbg server hidup sebelumnya, cuma lewat pytest).

Pola create_all() + seed ini sama persis dgn tests/conftest.py::db_session -
BUKAN lewat Alembic, krn migrasi 0001 pakai raw DDL Postgres yg tidak
portable ke SQLite. Jangan dipakai utk produksi (lihat config.py: default
produksi tetap Postgres via DATABASE_URL)."""

import asyncio

from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

import app.models  # noqa: F401 - registrasi semua tabel ke Base.metadata
from app.core.db import Base
from app.core.seed import seed_paket_fitur, seed_role_izin

DB_PATH = "dev_manual.db"


async def main() -> None:
    engine = create_async_engine(f"sqlite+aiosqlite:///{DB_PATH}")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as session:
        await seed_role_izin(session)
        await seed_paket_fitur(session)
        await session.commit()

    await engine.dispose()
    print(f"OK - {DB_PATH} siap (tabel dibuat + role/izin/paket/fitur di-seed)")


if __name__ == "__main__":
    asyncio.run(main())
