"""IMOGI no. 10: gambar QRIS statis milik usaha - unggah, hapus, gerbang paket/izin, dan ikut sync pull."""

import io
from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_perangkat, buat_toko_siap_pakai

_PNG_1X1 = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\rIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfe\xa7\x93\x8f\xb5\x00\x00\x00\x00IEND\xaeB`\x82"
)


def _berkas(nama: str = "qris.png", isi: bytes = _PNG_1X1) -> dict:
    return {"file": (nama, io.BytesIO(isi), "image/png")}


async def test_unggah_qris_tersimpan_dan_ikut_sync_pull(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id)

    resp = await client.post("/toko/qris", headers=toko.headers, files=_berkas())
    assert resp.status_code == 200, resp.text
    url = resp.json()["qris_url"]
    assert url.startswith("/static/qris/")

    pull = await client.get(
        "/sync/pull",
        headers=toko.headers,
        params={
            "since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(),
            "perangkat_id": str(perangkat.id),
            "outlet_id": str(toko.outlet.id),
        },
    )
    assert pull.status_code == 200
    assert pull.json()["qris_url"] == url


async def test_unggah_qris_ditolak_di_paket_gratis(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    resp = await client.post("/toko/qris", headers=toko.headers, files=_berkas())
    assert resp.status_code == 403
    assert resp.json()["detail"]["fitur"] == "qris"


async def test_unggah_qris_ditolak_untuk_kasir(client: AsyncClient, db_session: AsyncSession) -> None:
    kasir = await buat_toko_siap_pakai(db_session, nama_role="Kasir", nama_paket="Bisnis")
    resp = await client.post("/toko/qris", headers=kasir.headers, files=_berkas())
    assert resp.status_code == 403


async def test_unggah_qris_ditolak_bukan_gambar_atau_terlalu_besar(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    bukan = await client.post("/toko/qris", headers=toko.headers, files=_berkas("x.png", b"bukan gambar"))
    assert bukan.status_code == 400
    besar = await client.post(
        "/toko/qris", headers=toko.headers, files=_berkas(isi=_PNG_1X1 + b"\x00" * (1024 * 1024 + 1))
    )
    assert besar.status_code == 400


async def test_hapus_qris_boleh_walau_paket_turun(client: AsyncClient, db_session: AsyncSession) -> None:
    from app.models.outlet import Toko

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    await client.post("/toko/qris", headers=toko.headers, files=_berkas())

    hapus = await client.delete("/toko/qris", headers=toko.headers)
    assert hapus.status_code == 200 and hapus.json()["qris_url"] is None
    baris = await db_session.get(Toko, toko.toko.id)
    await db_session.refresh(baris)
    assert baris.qris_url is None


async def test_qris_antar_toko_terisolasi(client: AsyncClient, db_session: AsyncSession) -> None:
    a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    perangkat_b = await buat_perangkat(db_session, b.toko.id, b.outlet.id)
    await client.post("/toko/qris", headers=a.headers, files=_berkas())

    pull_b = await client.get(
        "/sync/pull",
        headers=b.headers,
        params={
            "since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(),
            "perangkat_id": str(perangkat_b.id),
            "outlet_id": str(b.outlet.id),
        },
    )
    assert pull_b.json()["qris_url"] is None
