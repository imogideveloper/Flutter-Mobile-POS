from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.otp_store import InMemoryOtpStore
from app.core.security import create_refresh_token
from app.models.akun import Pengguna
from app.models.outlet import Perangkat, Toko
from app.models.transaksi import MetodeBayar


async def test_otp_verify_kode_salah_ditolak(client: AsyncClient, db_session: AsyncSession) -> None:
    minta = await client.post("/auth/otp/request", json={"no_hp": "081311112222"})
    assert minta.status_code == 202

    verif = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": "081311112222",
            "kode": "000000",  # salah
            "device_uid": "device-1",
            "nama_perangkat": "HP Kasir 1",
            "nama_toko": "Kopi Senja",
            "nama_pemilik": "Rina",
        },
    )
    assert verif.status_code == 400

    toko_rows = (await db_session.execute(select(Toko))).scalars().all()
    assert toko_rows == []


async def test_otp_verify_sukses_mendaftarkan_toko_baru(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore
) -> None:
    await otp_store.simpan("081311112222", "123456", 300)

    resp = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": "081311112222",
            "kode": "123456",
            "device_uid": "device-1",
            "nama_perangkat": "HP Kasir 1",
            "nama_toko": "Kopi Senja",
            "nama_pemilik": "Rina",
            "pin": "1234",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["toko"]["nama"] == "Kopi Senja"
    assert body["pengguna"]["nama"] == "Rina"
    assert body["access_token"]
    assert body["refresh_token"]

    pengguna = (
        await db_session.execute(select(Pengguna).where(Pengguna.no_hp == "081311112222"))
    ).scalar_one()
    assert pengguna.pin_hash is not None

    perangkat = (await db_session.execute(select(Perangkat))).scalars().all()
    assert len(perangkat) == 1
    assert perangkat[0].device_uid == "device-1"
    assert body["perangkat_id"] == str(perangkat[0].id)

    # Toko baru wajib langsung punya 4 metode bayar dasar (F3.A) - tanpa
    # ini checkout/kasir tidak punya metode apa pun yang bisa dipilih.
    metode_rows = (
        await db_session.execute(select(MetodeBayar).where(MetodeBayar.toko_id == pengguna.toko_id))
    ).scalars().all()
    by_tipe = {m.tipe: m for m in metode_rows}
    assert set(by_tipe) == {"tunai", "qris", "kartu", "transfer"}
    assert by_tipe["tunai"].masuk_laci is True
    assert by_tipe["qris"].masuk_laci is False
    assert by_tipe["kartu"].masuk_laci is False
    assert by_tipe["transfer"].masuk_laci is False

    # OTP sekali pakai - kode yang sama tidak boleh dipakai ulang.
    ulang = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": "081311112222",
            "kode": "123456",
            "device_uid": "device-1",
            "nama_perangkat": "HP Kasir 1",
        },
    )
    assert ulang.status_code == 400


async def test_otp_verify_akun_belum_terdaftar_wajib_data_registrasi(
    client: AsyncClient, otp_store: InMemoryOtpStore
) -> None:
    await otp_store.simpan("089900001111", "654321", 300)

    resp = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": "089900001111",
            "kode": "654321",
            "device_uid": "device-2",
            "nama_perangkat": "HP Kasir 2",
        },
    )
    assert resp.status_code == 422


async def test_otp_verify_akun_lama_pairing_device_baru(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, toko_a
) -> None:
    await db_session.refresh(toko_a.pengguna)
    toko_a.pengguna.no_hp = "081399998888"
    await db_session.commit()

    await otp_store.simpan("081399998888", "111111", 300)

    resp = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": "081399998888",
            "kode": "111111",
            "device_uid": "device-baru",
            "nama_perangkat": "HP Kasir Baru",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["toko"]["id"] == str(toko_a.toko.id)
    assert body["pengguna"]["id"] == str(toko_a.pengguna.id)


async def test_otp_verify_akun_lama_dgn_pin_mereset_pin_lupa(
    client: AsyncClient, db_session: AsyncSession, otp_store: InMemoryOtpStore, toko_a
) -> None:
    """Jalur "lupa PIN kasir" - OTP WhatsApp yang sudah diverifikasi cukup
    utk reset PIN tanpa perlu tahu PIN lama (beda dari
    /pengguna/{id}/reset-pin yang butuh sudah login)."""
    await db_session.refresh(toko_a.pengguna)
    toko_a.pengguna.no_hp = "081399998888"
    pin_hash_lama = toko_a.pengguna.pin_hash
    await db_session.commit()

    await otp_store.simpan("081399998888", "222222", 300)

    resp = await client.post(
        "/auth/otp/verify",
        json={
            "no_hp": "081399998888",
            "kode": "222222",
            "device_uid": "device-lupa-pin",
            "nama_perangkat": "HP Kasir Lupa PIN",
            "pin": "999999",
        },
    )
    assert resp.status_code == 200

    await db_session.refresh(toko_a.pengguna)
    assert toko_a.pengguna.pin_hash != pin_hash_lama
    assert toko_a.pengguna.pin_hash is not None


async def test_refresh_token_mengeluarkan_access_token_baru(toko_a) -> None:
    refresh = create_refresh_token(
        pengguna_id=toko_a.pengguna.id, toko_id=toko_a.toko.id, role_id=toko_a.role.id
    )

    from app.main import app as fastapi_app

    transport = ASGITransport(app=fastapi_app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post("/auth/refresh", json={"refresh_token": refresh})
    assert resp.status_code == 200
    assert resp.json()["access_token"]
