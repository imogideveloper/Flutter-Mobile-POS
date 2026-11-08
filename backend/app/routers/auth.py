"""Auth - OTP pairing device/akun (sekali saat pasang HP, bukan login
harian - alur harian kasir pilih-pengguna+PIN tetap di app, tidak sentuh
backend ini) + refresh token.

Deviasi dari daftar endpoint di B.3: `/auth/device/register` TIDAK dibuat
terpisah - pendaftaran device sudah jadi bagian dari `/auth/otp/verify`
(baik untuk toko baru maupun toko yang sudah ada) supaya satu alur pairing
tidak terbelah dua request yang harus sukses berurutan."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_db
from app.core.jenis_usaha import normalisasi_jenis_usaha
from app.core.otp_store import OtpStore, get_otp_store
from app.core.deps import require_outlet_access
from app.core.security import (
    InvalidTokenError,
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)
from app.models.akun import AksesOutlet, Pengguna, Role
from app.models.outlet import Langganan, Outlet, Paket, Perangkat, Toko
from app.models.transaksi import MetodeBayar
from app.schemas.auth import (
    AuthOut,
    OtpRequestIn,
    OtpRequestOut,
    OtpVerifyIn,
    OutletOut,
    PenggunaOut,
    PinLoginIn,
    PinLoginOut,
    RefreshIn,
    RefreshOut,
    TokoOut,
)
from app.services.otp_service import buat_kode_otp, get_otp_provider

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/otp/request", response_model=OtpRequestOut, status_code=status.HTTP_202_ACCEPTED)
async def minta_otp(body: OtpRequestIn, store: OtpStore = Depends(get_otp_store)) -> OtpRequestOut:
    from app.core.config import get_settings

    settings = get_settings()
    kode = buat_kode_otp()
    await store.simpan(body.no_hp, kode, settings.otp_expire_seconds)
    await get_otp_provider().kirim(body.no_hp, kode)
    return OtpRequestOut(expires_in=settings.otp_expire_seconds)


@router.post("/otp/verify", response_model=AuthOut)
async def verifikasi_otp(
    body: OtpVerifyIn,
    store: OtpStore = Depends(get_otp_store),
    db: AsyncSession = Depends(get_db),
) -> AuthOut:
    kode_tersimpan = await store.ambil(body.no_hp)
    if kode_tersimpan is None or kode_tersimpan != body.kode:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Kode OTP salah atau sudah kedaluwarsa")
    await store.hapus(body.no_hp)

    pengguna = (
        await db.execute(select(Pengguna).where(Pengguna.no_hp == body.no_hp, Pengguna.deleted_at.is_(None)))
    ).scalar_one_or_none()

    if pengguna is None:
        toko, outlet, pengguna = await _daftarkan_toko_baru(db, body)
    else:
        toko = await db.get(Toko, pengguna.toko_id)
        outlet = await _outlet_pertama(db, pengguna.id)
        if outlet is None:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN, "Akun ini belum punya akses ke outlet manapun"
            )
        if body.pin:
            # Jalur "lupa PIN kasir" - OTP WhatsApp yang BARU SAJA
            # diverifikasi di atas sudah membuktikan kepemilikan nomor HP
            # terdaftar, jadi aman dipakai utk reset PIN tanpa perlu tahu
            # PIN lama. BEDA dari /pengguna/{id}/reset-pin (itu Owner
            # mereset PIN KARYAWAN lain, butuh sudah login) - ini dipakai
            # pemilik akun SENDIRI yang terkunci/lupa PIN device-nya.
            pengguna.pin_hash = hash_password(body.pin)

    perangkat = await _upsert_perangkat(db, toko_id=toko.id, outlet_id=outlet.id, body=body)
    await db.commit()

    access = create_access_token(
        pengguna_id=pengguna.id, toko_id=toko.id, role_id=pengguna.role_id, perangkat_id=perangkat.id
    )
    refresh = create_refresh_token(
        pengguna_id=pengguna.id, toko_id=toko.id, role_id=pengguna.role_id, perangkat_id=perangkat.id
    )
    return AuthOut(
        access_token=access,
        refresh_token=refresh,
        toko=TokoOut(id=toko.id, nama=toko.nama, jenis_usaha=toko.jenis_usaha),
        outlet=OutletOut(id=outlet.id, nama=outlet.nama, kode=outlet.kode),
        pengguna=PenggunaOut(id=pengguna.id, nama=pengguna.nama, role_id=pengguna.role_id),
        perangkat_id=perangkat.id,
    )


async def _daftarkan_toko_baru(db: AsyncSession, body: OtpVerifyIn) -> tuple[Toko, Outlet, Pengguna]:
    if not body.nama_toko or not body.nama_pemilik:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "Nomor HP belum terdaftar - lengkapi nama_toko dan nama_pemilik untuk mendaftar",
        )

    owner_role = (
        await db.execute(select(Role).where(Role.nama == "Owner", Role.is_system.is_(True)))
    ).scalar_one_or_none()
    if owner_role is None:
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "Role bawaan 'Owner' tidak ditemukan - pastikan migrasi 0001 (seed) sudah dijalankan",
        )

    # Paket TERENDAH (urutan paling kecil: Gratis/Free) - dicari lewat urutan,
    # bukan nama, supaya tidak bergantung pada katalog yang dipakai.
    paket_gratis = (
        await db.execute(select(Paket).where(Paket.aktif.is_(True)).order_by(Paket.urutan.asc()))
    ).scalars().first()
    if paket_gratis is None:
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "Tidak ada paket aktif - pastikan migrasi (seed paket) sudah dijalankan",
        )

    toko = Toko(
        nama=body.nama_toko,
        jenis_usaha=normalisasi_jenis_usaha(body.jenis_usaha),
        pemilik_nama=body.nama_pemilik,
        no_hp=body.no_hp,
    )
    db.add(toko)
    await db.flush()

    outlet = Outlet(toko_id=toko.id, kode="OUT1", nama="Outlet Pusat")
    db.add(outlet)
    await db.flush()

    # Setiap toko baru otomatis mulai di paket Gratis (aturan dokumen #4.2
    # - fitur yang dinyalakan ditentukan `paket_fitur`, bukan nama paket
    # langsung) - owner bisa upgrade lewat modul langganan nanti.
    db.add(
        Langganan(
            toko_id=toko.id,
            paket_id=paket_gratis.id,
            jumlah_outlet=1,
            mulai=datetime.now(UTC),
            status="aktif",
        )
    )
    await db.flush()

    pengguna = Pengguna(
        toko_id=toko.id,
        role_id=owner_role.id,
        nama=body.nama_pemilik,
        no_hp=body.no_hp,
        pin_hash=hash_password(body.pin) if body.pin else None,
    )
    db.add(pengguna)
    await db.flush()

    db.add(AksesOutlet(pengguna_id=pengguna.id, outlet_id=outlet.id))

    # Metode bayar dasar - SEBELUMNYA TIDAK PERNAH di-seed sama sekali utk
    # toko baru (ditemukan sambil mengerjakan tahap "4 fitur stub": Flutter
    # cuma pakai id placeholder yang tidak match baris backend manapun).
    # Tunai masuk_laci=true (dihitung di kas_seharusnya shift); QRIS/Kartu/
    # Transfer masuk_laci=false (lihat shift_service.py - uang non-tunai
    # tidak pernah masuk laci fisik).
    db.add_all([
        MetodeBayar(toko_id=toko.id, nama="Tunai", tipe="tunai", masuk_laci=True, urutan=0),
        MetodeBayar(
            toko_id=toko.id, nama="QRIS", tipe="qris", butuh_gateway=True, masuk_laci=False, urutan=1
        ),
        MetodeBayar(toko_id=toko.id, nama="Kartu", tipe="kartu", masuk_laci=False, urutan=2),
        MetodeBayar(toko_id=toko.id, nama="Transfer", tipe="transfer", masuk_laci=False, urutan=3),
    ])
    await db.flush()

    return toko, outlet, pengguna


async def _outlet_pertama(db: AsyncSession, pengguna_id: uuid.UUID) -> Outlet | None:
    return (
        await db.execute(
            select(Outlet)
            .join(AksesOutlet, AksesOutlet.outlet_id == Outlet.id)
            .where(AksesOutlet.pengguna_id == pengguna_id)
            .order_by(Outlet.created_at)
        )
    ).scalars().first()


async def _upsert_perangkat(
    db: AsyncSession, *, toko_id: uuid.UUID, outlet_id: uuid.UUID, body: OtpVerifyIn
) -> Perangkat:
    existing = (
        await db.execute(
            select(Perangkat).where(Perangkat.toko_id == toko_id, Perangkat.device_uid == body.device_uid)
        )
    ).scalar_one_or_none()
    if existing is None:
        perangkat = Perangkat(
            toko_id=toko_id,
            outlet_id=outlet_id,
            nama=body.nama_perangkat,
            device_uid=body.device_uid,
            platform=body.platform,
        )
        db.add(perangkat)
        await db.flush()
        return perangkat

    existing.nama = body.nama_perangkat
    existing.platform = body.platform
    existing.aktif = True
    await db.flush()
    return existing


@router.post("/refresh", response_model=RefreshOut)
async def refresh_token(body: RefreshIn) -> RefreshOut:
    try:
        claims = decode_token(body.refresh_token, expected_type="refresh")
    except InvalidTokenError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Refresh token tidak valid: {exc}") from exc

    access = create_access_token(
        pengguna_id=claims.pengguna_id,
        toko_id=claims.toko_id,
        role_id=claims.role_id,
        perangkat_id=claims.perangkat_id,
    )
    return RefreshOut(access_token=access)


@router.post("/pin-login", response_model=PinLoginOut)
async def pin_login(body: PinLoginIn, db: AsyncSession = Depends(get_db)) -> PinLoginOut:
    """Tahap 5b (desain #6) - login PIN ONLINE menghasilkan token ATAS NAMA
    karyawan ybs, terikat ke perangkat yang sudah terpasang (device wajib
    sudah pernah pairing lewat /auth/otp/verify - endpoint ini TIDAK
    mendaftarkan device baru). Tanpa `Depends(get_current_claims)` krn ini
    SENDIRI yang menghasilkan identitas - sama pola dgn /auth/otp/verify."""

    perangkat = await db.get(Perangkat, body.perangkat_id)
    if perangkat is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Perangkat tidak dikenal - pairing device dulu")

    pengguna = await db.get(Pengguna, body.pengguna_id)
    if (
        pengguna is None
        or pengguna.toko_id != perangkat.toko_id
        or pengguna.deleted_at is not None
        or not pengguna.aktif
        or pengguna.pin_hash is None
        or not verify_password(body.pin, pengguna.pin_hash)
    ):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "PIN salah atau akun tidak aktif")

    if perangkat.outlet_id is not None:
        await require_outlet_access(
            db, pengguna_id=pengguna.id, role_id=pengguna.role_id, outlet_id=perangkat.outlet_id
        )

    access = create_access_token(
        pengguna_id=pengguna.id, toko_id=pengguna.toko_id, role_id=pengguna.role_id, perangkat_id=perangkat.id
    )
    refresh = create_refresh_token(
        pengguna_id=pengguna.id, toko_id=pengguna.toko_id, role_id=pengguna.role_id, perangkat_id=perangkat.id
    )
    pengguna.terakhir_login = datetime.now(UTC)
    await db.commit()

    return PinLoginOut(
        access_token=access,
        refresh_token=refresh,
        pengguna=PenggunaOut(id=pengguna.id, nama=pengguna.nama, role_id=pengguna.role_id),
        perangkat_id=perangkat.id,
    )
