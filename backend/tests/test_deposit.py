"""IMOGI no. 79: deposit pelanggan / pendapatan diterima di muka (buku mutasi saldo)."""

from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pelanggan import Pelanggan
from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai


async def _pelanggan(db: AsyncSession, toko_id, nama: str = "Budi") -> Pelanggan:
    p = Pelanggan(toko_id=toko_id, nama=nama)
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return p


async def _catat(client, toko, pid, jenis, jumlah, **extra):
    return await client.post(
        "/deposit", headers=toko.headers, json={"pelanggan_id": str(pid), "jenis": jenis, "jumlah": jumlah, **extra}
    )


async def test_topup_pakai_dan_saldo(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    p = await _pelanggan(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    pid = p.id

    r = await _catat(client, toko, pid, "topup", "500000", metode_bayar_id=str(metode.id))
    assert r.status_code == 201, r.text
    assert Decimal(r.json()["saldo_baru"]) == 500000
    r = await _catat(client, toko, pid, "pakai", "120000", catatan="Ngopi")
    assert Decimal(r.json()["saldo_baru"]) == 380000

    detail = (await client.get(f"/deposit/pelanggan/{pid}", headers=toko.headers)).json()
    assert Decimal(detail["saldo"]) == 380000 and len(detail["riwayat"]) == 2
    assert {m["jenis"] for m in detail["riwayat"]} == {"topup", "pakai"}


async def test_pakai_melebihi_saldo_ditolak_dan_koreksi_butuh_catatan(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    pid = (await _pelanggan(db_session, toko.toko.id)).id
    await _catat(client, toko, pid, "topup", "100000")
    assert (await _catat(client, toko, pid, "pakai", "100001")).status_code == 409
    assert (await _catat(client, toko, pid, "koreksi", "1000")).status_code == 422
    ok = await _catat(client, toko, pid, "koreksi", "1000", catatan="Salah input")
    assert ok.status_code == 201 and Decimal(ok.json()["saldo_baru"]) == 99000
    assert (await _catat(client, toko, pid, "ngawur", "1")).status_code == 422
    assert (await _catat(client, toko, pid, "topup", "0")).status_code == 422


async def test_ringkasan_total_dan_hanya_saldo_positif(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    a = (await _pelanggan(db_session, toko.toko.id, "Ani")).id
    b = (await _pelanggan(db_session, toko.toko.id, "Budi")).id
    c = (await _pelanggan(db_session, toko.toko.id, "Cici")).id
    await _catat(client, toko, a, "topup", "300000")
    await _catat(client, toko, b, "topup", "700000")
    await _catat(client, toko, c, "topup", "50000")
    await _catat(client, toko, c, "pakai", "50000")  # habis, tidak tampil
    data = (await client.get("/deposit/ringkasan", headers=toko.headers)).json()
    assert Decimal(data["total_saldo"]) == 1000000 and data["jumlah_pelanggan"] == 2
    assert [x["nama"] for x in data["pelanggan"]] == ["Budi", "Ani"], "terbesar dulu"


async def test_isolasi_dan_paket(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    lain = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    pid = (await _pelanggan(db_session, toko.toko.id)).id
    await _catat(client, toko, pid, "topup", "1000")
    assert (await _catat(client, lain, pid, "topup", "1000")).status_code == 404
    assert (await client.get(f"/deposit/pelanggan/{pid}", headers=lain.headers)).status_code == 404
    assert (await client.get("/deposit/ringkasan", headers=lain.headers)).json()["jumlah_pelanggan"] == 0
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/deposit/ringkasan", headers=gratis.headers)).status_code == 403
