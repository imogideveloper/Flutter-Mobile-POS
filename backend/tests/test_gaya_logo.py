"""IMOGI no. 24: gaya logo struk siap pakai (lingkaran, cincin, inisial) selain logo unggahan."""

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_toko_siap_pakai


async def test_gaya_bawaan_unggah_dan_bisa_disimpan_ulang_di_paket_gratis(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    url = f"/outlets/{toko.outlet.id}/pengaturan"
    assert (await client.get(url, headers=toko.headers)).json()["gaya_logo"] == "unggah"

    # Klien mengirim ulang seluruh pengaturan tiap simpan: nilai bawaan 'unggah' tidak boleh ditolak (cf. BUG-012).
    ulang = await client.patch(url, headers=toko.headers, json={"gaya_logo": "unggah", "header_struk": "Halo"})
    assert ulang.status_code == 200 and ulang.json()["gaya_logo"] == "unggah"


async def test_gaya_siap_pakai_digate_fitur_logo_struk(client: AsyncClient, db_session: AsyncSession) -> None:
    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    ditolak = await client.patch(
        f"/outlets/{gratis.outlet.id}/pengaturan", headers=gratis.headers, json={"gaya_logo": "cincin"}
    )
    assert ditolak.status_code == 403
    assert ditolak.json()["detail"]["fitur"] == "logo_struk"

    bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    url = f"/outlets/{bisnis.outlet.id}/pengaturan"
    for gaya in ("lingkaran", "cincin", "inisial", "unggah"):
        resp = await client.patch(url, headers=bisnis.headers, json={"gaya_logo": gaya})
        assert resp.status_code == 200, resp.text
        assert resp.json()["gaya_logo"] == gaya


async def test_gaya_tidak_dikenal_ditolak(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resp = await client.patch(
        f"/outlets/{toko.outlet.id}/pengaturan", headers=toko.headers, json={"gaya_logo": "bintang"}
    )
    assert resp.status_code == 400


async def test_gaya_logo_ikut_sync_pull(client: AsyncClient, db_session: AsyncSession) -> None:
    from datetime import UTC, datetime

    from tests.conftest import buat_perangkat

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id)
    await client.patch(
        f"/outlets/{toko.outlet.id}/pengaturan", headers=toko.headers, json={"gaya_logo": "lingkaran"}
    )
    resp = await client.get(
        "/sync/pull",
        headers=toko.headers,
        params={
            "since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(),
            "perangkat_id": str(perangkat.id),
            "outlet_id": str(toko.outlet.id),
        },
    )
    assert resp.status_code == 200, resp.text
    assert [p["gaya_logo"] for p in resp.json()["pengaturan_outlet"]] == ["lingkaran"]
