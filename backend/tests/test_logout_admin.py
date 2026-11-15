"""Tahap 1 (permintaan lead): logout usaha dari perangkat dan akun
Administrator platform (login email+password, terpisah dari karyawan toko)."""

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import create_access_token, create_refresh_token
from app.models.outlet import Perangkat
from tests.conftest import buat_toko_siap_pakai


async def _toko_dengan_perangkat(db: AsyncSession, nama_role: str = "Owner"):
    data = await buat_toko_siap_pakai(db, nama_role=nama_role)
    perangkat = Perangkat(
        toko_id=data.toko.id, outlet_id=data.outlet.id, nama="HP Uji", device_uid="uid-uji", platform="android"
    )
    db.add(perangkat)
    await db.commit()
    await db.refresh(perangkat)
    akses = create_access_token(
        pengguna_id=data.pengguna.id, toko_id=data.toko.id, role_id=data.role.id, perangkat_id=perangkat.id
    )
    segar = create_refresh_token(
        pengguna_id=data.pengguna.id, toko_id=data.toko.id, role_id=data.role.id, perangkat_id=perangkat.id
    )
    return data, perangkat, {"Authorization": f"Bearer {akses}"}, segar


async def test_logout_owner_mencabut_refresh_token_perangkat(client: AsyncClient, db_session: AsyncSession) -> None:
    _, perangkat, headers, refresh = await _toko_dengan_perangkat(db_session)

    sebelum = await client.post("/auth/refresh", json={"refresh_token": refresh})
    assert sebelum.status_code == 200

    resp = await client.post("/auth/logout", headers=headers)
    assert resp.status_code == 204

    await db_session.refresh(perangkat)
    assert perangkat.aktif is False

    sesudah = await client.post("/auth/refresh", json={"refresh_token": refresh})
    assert sesudah.status_code == 401


async def test_logout_ditolak_untuk_kasir(client: AsyncClient, db_session: AsyncSession) -> None:
    _, perangkat, headers, _ = await _toko_dengan_perangkat(db_session, nama_role="Kasir")

    resp = await client.post("/auth/logout", headers=headers)
    assert resp.status_code == 403

    await db_session.refresh(perangkat)
    assert perangkat.aktif is True


async def test_logout_butuh_token(client: AsyncClient) -> None:
    resp = await client.post("/auth/logout")
    assert resp.status_code == 401


async def test_pin_login_ditolak_di_perangkat_yang_sudah_logout(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    data, perangkat, headers, _ = await _toko_dengan_perangkat(db_session)
    await client.post("/auth/logout", headers=headers)

    resp = await client.post(
        "/auth/pin-login",
        json={"pengguna_id": str(data.pengguna.id), "perangkat_id": str(perangkat.id), "pin": "123456"},
    )
    assert resp.status_code == 404


async def test_akun_admin_dibuat_dgn_api_key_lalu_login(client: AsyncClient, monkeypatch) -> None:
    monkeypatch.setenv("ADMIN_API_KEY", "kunci-rahasia-tes")
    get_settings.cache_clear()
    try:
        kunci = {"X-Admin-Api-Key": "kunci-rahasia-tes"}
        baru = {"email": "Lead@Contoh.test", "nama": "Lead", "password": "sandi-uji-panjang"}

        tanpa_kunci = await client.post("/admin/akun", json=baru)
        assert tanpa_kunci.status_code == 401

        buat = await client.post("/admin/akun", headers=kunci, json=baru)
        assert buat.status_code == 201
        assert buat.json()["email"] == "lead@contoh.test"
        assert "password" not in buat.json() and "password_hash" not in buat.json()

        ganda = await client.post("/admin/akun", headers=kunci, json=baru)
        assert ganda.status_code == 409

        pendek = await client.post(
            "/admin/akun", headers=kunci, json={"email": "x@y.test", "nama": "X", "password": "pendek"}
        )
        assert pendek.status_code == 422

        salah = await client.post("/admin/auth/login", json={"email": "lead@contoh.test", "password": "salah-sekali"})
        assert salah.status_code == 401
        tidak_ada = await client.post("/admin/auth/login", json={"email": "tak@ada.test", "password": "sandi-uji-panjang"})
        assert tidak_ada.status_code == 401
        assert salah.json() == tidak_ada.json()

        login = await client.post("/admin/auth/login", json={"email": "LEAD@contoh.test", "password": "sandi-uji-panjang"})
        assert login.status_code == 200
        token = login.json()["access_token"]
        bearer = {"Authorization": f"Bearer {token}"}

        saya = await client.get("/admin/auth/saya", headers=bearer)
        assert saya.status_code == 200 and saya.json()["nama"] == "Lead"

        # JWT admin sah di endpoint admin lain tanpa API key.
        platform = await client.get("/admin/pengaturan-platform", headers=bearer)
        assert platform.status_code == 200

        # ...tapi TIDAK boleh membuat admin baru (itu khusus API key).
        lagi = await client.post("/admin/akun", headers=bearer, json={**baru, "email": "lain@contoh.test"})
        assert lagi.status_code == 401
    finally:
        get_settings.cache_clear()


async def test_token_karyawan_tidak_bisa_dipakai_sebagai_admin(client: AsyncClient, toko_a, monkeypatch) -> None:
    monkeypatch.setenv("ADMIN_API_KEY", "kunci-rahasia-tes")
    get_settings.cache_clear()
    try:
        resp = await client.get("/admin/pengaturan-platform", headers=toko_a.headers)
        assert resp.status_code == 401
    finally:
        get_settings.cache_clear()


async def test_token_admin_tidak_bisa_dipakai_di_endpoint_toko(client: AsyncClient, monkeypatch) -> None:
    monkeypatch.setenv("ADMIN_API_KEY", "kunci-rahasia-tes")
    get_settings.cache_clear()
    try:
        kunci = {"X-Admin-Api-Key": "kunci-rahasia-tes"}
        await client.post(
            "/admin/akun", headers=kunci, json={"email": "a@b.test", "nama": "A", "password": "sandi-uji-panjang"}
        )
        token = (
            await client.post("/admin/auth/login", json={"email": "a@b.test", "password": "sandi-uji-panjang"})
        ).json()["access_token"]
        resp = await client.get("/produk", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 401
    finally:
        get_settings.cache_clear()
