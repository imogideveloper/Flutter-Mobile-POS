"""IMOGI no. 78: tutup buku (kunci periode) - hanya Owner; pengeluaran/settlement/anggaran bertanggal terkunci ditolak."""

from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai
from tests.test_akses_outlet import _buat_pengguna


def _tgl(hari_lalu: int) -> str:
    return str((datetime.now(UTC) - timedelta(days=hari_lalu)).date())


async def test_tutup_menolak_pengeluaran_lama_tapi_menerima_yang_baru(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    lama = {"tanggal": _tgl(10), "kategori": "sewa", "jumlah": "1000"}
    ada = await client.post("/pengeluaran", headers=toko.headers, json=lama)
    assert ada.status_code == 201, ada.text

    r = await client.post("/tutup-buku", headers=toko.headers, json={"sampai": _tgl(5), "catatan": "Tutup bulan"})
    assert r.status_code == 201, r.text
    assert r.json()["ditutup_sampai"] == _tgl(5)

    assert (await client.post("/pengeluaran", headers=toko.headers, json=lama)).status_code == 409
    assert (await client.delete(f"/pengeluaran/{ada.json()['id']}", headers=toko.headers)).status_code == 409
    baru = {**lama, "tanggal": _tgl(4)}
    assert (await client.post("/pengeluaran", headers=toko.headers, json=baru)).status_code == 201, "setelah tanggal tutup"


async def test_settlement_dan_anggaran_ikut_terkunci(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    qris = await buat_metode_bayar(db_session, toko.toko.id, tipe="qris")
    await client.post("/tutup-buku", headers=toko.headers, json={"sampai": _tgl(3)})
    s = await client.post(
        "/settlement",
        headers=toko.headers,
        json={"metode_bayar_id": str(qris.id), "tanggal": _tgl(8), "jumlah_diterima": "1"},
    )
    assert s.status_code == 409
    bulan_lalu = (datetime.now(UTC).replace(day=1) - timedelta(days=40)).strftime("%Y-%m")
    a = await client.put("/anggaran", headers=toko.headers, json={"bulan": bulan_lalu, "kategori": "sewa", "jumlah": "1"})
    assert a.status_code == 409


async def test_aturan_tanggal_dan_buka_kembali(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    besok = str((datetime.now(UTC) + timedelta(days=1)).date())
    assert (await client.post("/tutup-buku", headers=toko.headers, json={"sampai": besok})).status_code == 422
    assert (await client.post("/tutup-buku", headers=toko.headers, json={"sampai": _tgl(5)})).status_code == 201
    assert (await client.post("/tutup-buku", headers=toko.headers, json={"sampai": _tgl(7)})).status_code == 409, "mundur"
    assert (await client.post("/tutup-buku", headers=toko.headers, json={"sampai": _tgl(2)})).status_code == 201

    buka = await client.delete("/tutup-buku/terakhir", headers=toko.headers)
    assert buka.status_code == 200 and buka.json()["ditutup_sampai"] == _tgl(5), "kembali ke penutupan sebelumnya"
    buka = await client.delete("/tutup-buku/terakhir", headers=toko.headers)
    assert buka.json()["ditutup_sampai"] is None
    assert (await client.delete("/tutup-buku/terakhir", headers=toko.headers)).status_code == 404
    lama = {"tanggal": _tgl(10), "kategori": "sewa", "jumlah": "1"}
    assert (await client.post("/pengeluaran", headers=toko.headers, json=lama)).status_code == 201, "sudah dibuka"


async def test_hanya_owner_menutup_dan_paket_gratis_terkunci(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    kasir = await _buat_pengguna(
        db_session, toko_id=toko.toko.id, nama_role="Kasir", outlet_ids=[toko.outlet.id], nama="Kasir"
    )
    r = await client.post("/tutup-buku", headers=kasir.headers, json={"sampai": _tgl(5)})
    assert r.status_code == 403
    assert (await client.delete("/tutup-buku/terakhir", headers=kasir.headers)).status_code == 403
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/tutup-buku", headers=gratis.headers)).status_code == 403
