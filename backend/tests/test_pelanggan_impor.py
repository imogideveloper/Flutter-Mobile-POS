from datetime import date

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pelanggan import Pelanggan
from app.routers.pelanggan_impor import bersihkan_hp, kunci_hp
from tests.conftest import buat_toko_siap_pakai


async def _pelanggan(db: AsyncSession, toko_id) -> list[Pelanggan]:
    return list((await db.execute(select(Pelanggan).where(Pelanggan.toko_id == toko_id))).scalars())


def test_normalisasi_nomor_hp() -> None:
    assert bersihkan_hp("+62 812-3456-7890") == "6281234567890"
    assert bersihkan_hp("(0812) 345 6789") == "08123456789"
    assert bersihkan_hp("   ") is None and bersihkan_hp(None) is None
    # 0812.., 62812.., +62812.. adalah nomor yang sama
    assert kunci_hp("081234567890") == kunci_hp("6281234567890") == "6281234567890"


async def test_impor_menyimpan_pelanggan_dengan_nomor_dibersihkan(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    r = await client.post(
        "/pelanggan/impor",
        headers=toko.headers,
        json={
            "baris": [
                {"nama": "Sari", "no_hp": "0812-3456-7890", "email": "sari@example.com", "tanggal_lahir": "1995-04-12"},
                {"nama": "Budi", "no_hp": "+62 856 111 2222", "catatan": "Suka kopi hitam"},
                {"nama": "Tanpa HP"},
            ]
        },
    )
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["diterima"] == 3 and b["ditolak"] == 0
    data = {p.nama: p for p in await _pelanggan(db_session, toko.toko.id)}
    assert data["Sari"].no_hp == "081234567890"
    assert data["Sari"].tanggal_lahir == date(1995, 4, 12)
    assert data["Sari"].email == "sari@example.com"
    assert data["Budi"].no_hp == "628561112222" and data["Budi"].catatan == "Suka kopi hitam"
    assert data["Tanpa HP"].no_hp is None


async def test_impor_menolak_baris_salah_dan_nomor_ganda(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    db_session.add(Pelanggan(toko_id=toko.toko.id, nama="Lama", no_hp="081234567890"))
    await db_session.commit()

    r = await client.post(
        "/pelanggan/impor",
        headers=toko.headers,
        json={
            "baris": [
                {"nama": "Dup Lama", "no_hp": "+62 812 3456 7890"},  # sama dengan pelanggan lama (0812 vs +62812)
                {"nama": "Baru", "no_hp": "0899 0000 1111"},
                {"nama": "Dup Batch", "no_hp": "6289900001111"},  # sama dengan baris sebelumnya
                {"nama": "", "no_hp": "0877 1234 5678"},
                {"nama": "HP Pendek", "no_hp": "123"},
                {"nama": "Email Rusak", "email": "bukan-email"},
                {"nama": "Dua Tanpa HP A"},
                {"nama": "Dua Tanpa HP B"},  # tanpa HP boleh banyak
            ]
        },
    )
    assert r.status_code == 200, r.text
    b = r.json()
    status_per_nomor = {h["nomor"]: h["status"] for h in b["hasil"]}
    assert status_per_nomor == {1: "ditolak", 2: "diterima", 3: "ditolak", 4: "ditolak", 5: "ditolak", 6: "ditolak", 7: "diterima", 8: "diterima"}
    assert "sudah terdaftar" in b["hasil"][0]["pesan"] and "sudah terdaftar" in b["hasil"][2]["pesan"]
    assert "tidak valid" in b["hasil"][4]["pesan"] and "Email" in b["hasil"][5]["pesan"]
    assert {p.nama for p in await _pelanggan(db_session, toko.toko.id)} == {"Lama", "Baru", "Dua Tanpa HP A", "Dua Tanpa HP B"}


async def test_impor_simulasi_tidak_menyimpan(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    r = await client.post(
        "/pelanggan/impor", headers=toko.headers,
        json={"simulasi": True, "baris": [{"nama": "A", "no_hp": "081200000001"}, {"nama": ""}]},
    )
    assert r.json()["simulasi"] is True and r.json()["diterima"] == 1 and r.json()["ditolak"] == 1
    assert await _pelanggan(db_session, toko.toko.id) == []


async def test_impor_terisolasi_antar_toko_dan_digate(client: AsyncClient, db_session: AsyncSession) -> None:
    a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    db_session.add(Pelanggan(toko_id=a.toko.id, nama="Milik A", no_hp="081234567890"))
    await db_session.commit()
    # Nomor yang sama di toko lain boleh (unik per toko)
    r = await client.post("/pelanggan/impor", headers=b.headers, json={"baris": [{"nama": "Milik B", "no_hp": "081234567890"}]})
    assert r.json()["diterima"] == 1

    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    g = await client.post("/pelanggan/impor", headers=gratis.headers, json={"baris": [{"nama": "X"}]})
    assert g.status_code == 403 and g.json()["detail"]["fitur"] == "customer_import"

    pro = await buat_toko_siap_pakai(db_session, nama_paket="Pro")
    p = await client.post("/pelanggan/impor", headers=pro.headers, json={"baris": [{"nama": "X"}]})
    assert p.status_code == 403 and p.json()["detail"]["fitur"] == "customer_import"  # Professional = tingkat 2

    assert (await client.post("/pelanggan/impor", headers=b.headers, json={"baris": []})).status_code == 422
    banyak = [{"nama": f"P{i}"} for i in range(501)]
    assert (await client.post("/pelanggan/impor", headers=b.headers, json={"baris": banyak})).status_code == 422
