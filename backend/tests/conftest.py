"""Fixture pytest bersama - SQLite in-memory via aiosqlite (bukan Postgres
sungguhan, lihat plan B.5: lebih cepat, cukup untuk tes logika; migrasi ke
Postgres asli tetap wajib dites ulang di mesin yang punya Docker sebelum
deploy, lihat README.md backend)."""

import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime
from decimal import Decimal

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401 - registrasi semua tabel ke Base.metadata
from app.core.db import Base, get_db
from app.core.otp_store import InMemoryOtpStore, get_otp_store
from app.core.security import create_access_token
from app.core.seed import seed_paket_fitur, seed_role_izin
from app.main import app as fastapi_app
from app.models.akun import AksesOutlet, Pengguna, Role
from app.models.outlet import Langganan, Outlet, Paket, Perangkat, Toko
from app.models.produk import Produk
from app.models.transaksi import MetodeBayar


@pytest_asyncio.fixture
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as session:
        await seed_role_izin(session)
        await seed_paket_fitur(session)
        yield session

    await engine.dispose()


@pytest_asyncio.fixture
async def otp_store() -> InMemoryOtpStore:
    return InMemoryOtpStore()


@pytest_asyncio.fixture
async def client(
    db_session: AsyncSession, otp_store: InMemoryOtpStore
) -> AsyncGenerator[AsyncClient, None]:
    async def _get_db_override() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    fastapi_app.dependency_overrides[get_db] = _get_db_override
    # Instance TUNGGAL dibagi ke semua request dalam satu test - kalau tiap
    # request dapat InMemoryOtpStore() baru, kode OTP yang disimpan di
    # /otp/request tidak akan terlihat lagi saat /otp/verify dipanggil.
    fastapi_app.dependency_overrides[get_otp_store] = lambda: otp_store

    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac

    fastapi_app.dependency_overrides.clear()


class DataToko:
    """Bundel toko+outlet+role+pengguna siap pakai + token akses - dipakai
    hampir semua test router supaya tidak menulis ulang setup yang sama."""

    def __init__(self, toko: Toko, outlet: Outlet, pengguna: Pengguna, role: Role, token: str):
        self.toko = toko
        self.outlet = outlet
        self.pengguna = pengguna
        self.role = role
        self.token = token

    @property
    def headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


async def buat_toko_siap_pakai(
    db: AsyncSession, *, nama_role: str = "Owner", nama_paket: str = "Gratis", jumlah_outlet: int = 1
) -> DataToko:
    role = (
        await db.execute(select(Role).where(Role.nama == nama_role, Role.is_system.is_(True)))
    ).scalar_one()
    paket = (await db.execute(select(Paket).where(Paket.nama == nama_paket))).scalar_one()

    toko = Toko(nama="Toko Uji Coba")
    db.add(toko)
    await db.flush()

    outlet = Outlet(toko_id=toko.id, kode="OUT1", nama="Outlet Pusat")
    db.add(outlet)
    await db.flush()

    pengguna = Pengguna(toko_id=toko.id, role_id=role.id, nama="Penguji", no_hp="081200000000")
    db.add(pengguna)
    await db.flush()

    db.add(AksesOutlet(pengguna_id=pengguna.id, outlet_id=outlet.id))
    db.add(
        Langganan(toko_id=toko.id, paket_id=paket.id, jumlah_outlet=jumlah_outlet, mulai=datetime.now(UTC), status="aktif")
    )
    await db.commit()

    token = create_access_token(pengguna_id=pengguna.id, toko_id=toko.id, role_id=role.id)
    return DataToko(toko=toko, outlet=outlet, pengguna=pengguna, role=role, token=token)


@pytest_asyncio.fixture
async def toko_a(db_session: AsyncSession) -> DataToko:
    return await buat_toko_siap_pakai(db_session)


@pytest_asyncio.fixture
async def toko_b(db_session: AsyncSession) -> DataToko:
    return await buat_toko_siap_pakai(db_session)


async def buat_produk(
    db: AsyncSession, toko_id: uuid.UUID, *, nama: str = "Kopi Hitam", harga_jual: Decimal = Decimal("15000")
) -> Produk:
    produk = Produk(toko_id=toko_id, nama=nama, harga_jual=harga_jual)
    db.add(produk)
    await db.commit()
    await db.refresh(produk)
    return produk


async def buat_metode_bayar(
    db: AsyncSession, toko_id: uuid.UUID, *, tipe: str = "tunai", masuk_laci: bool | None = None
) -> MetodeBayar:
    metode = MetodeBayar(
        toko_id=toko_id,
        nama=tipe.capitalize(),
        tipe=tipe,
        masuk_laci=masuk_laci if masuk_laci is not None else (tipe == "tunai"),
    )
    db.add(metode)
    await db.commit()
    await db.refresh(metode)
    return metode


async def buat_perangkat(
    db: AsyncSession, toko_id: uuid.UUID, outlet_id: uuid.UUID, *, device_uid: str = "device-test-1"
) -> Perangkat:
    perangkat = Perangkat(toko_id=toko_id, outlet_id=outlet_id, nama="HP Uji Coba", device_uid=device_uid)
    db.add(perangkat)
    await db.commit()
    await db.refresh(perangkat)
    return perangkat
