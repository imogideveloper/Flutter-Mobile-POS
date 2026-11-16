"""Batch B: klasifikasi fitur (inti/opsional/na) untuk jenis usaha toko ikut sync pull."""

from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fitur import Fitur, FiturKebutuhan
from tests.conftest import buat_perangkat, buat_toko_siap_pakai




async def _isi_kebutuhan(db: AsyncSession) -> dict[str, Fitur]:
    """Beri klasifikasi pada tiga fitur seed uji: pos (inti kafe, inti katering), kasbon (opsional kafe, na minuman)."""
    fitur = {
        f.kode: f
        for f in (await db.execute(select(Fitur).where(Fitur.kode.in_(["pos", "kasbon", "diskon"])))).scalars().all()
    }
    db.add_all(
        [
            FiturKebutuhan(fitur_id=fitur["pos"].id, jenis_usaha="CAF", kebutuhan="inti"),
            FiturKebutuhan(fitur_id=fitur["kasbon"].id, jenis_usaha="CAF", kebutuhan="opsional"),
            FiturKebutuhan(fitur_id=fitur["diskon"].id, jenis_usaha="CAF", kebutuhan="inti"),
            FiturKebutuhan(fitur_id=fitur["pos"].id, jenis_usaha="BEV", kebutuhan="inti"),
            FiturKebutuhan(fitur_id=fitur["kasbon"].id, jenis_usaha="BEV", kebutuhan="na"),
        ]
    )
    await db.commit()
    return fitur


async def _pull_map(client: AsyncClient, db: AsyncSession, toko) -> dict:
    perangkat = await buat_perangkat(db, toko.toko.id, toko.outlet.id)
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
    return resp.json()["kebutuhan_fitur"]


async def test_pull_membawa_klasifikasi_sesuai_jenis_usaha_toko(client: AsyncClient, db_session: AsyncSession) -> None:
    await _isi_kebutuhan(db_session)

    kafe = await buat_toko_siap_pakai(db_session)
    kafe.toko.jenis_usaha = "CAF"
    minuman = await buat_toko_siap_pakai(db_session)
    minuman.toko.jenis_usaha = "BEV"
    await db_session.commit()

    assert await _pull_map(client, db_session, kafe) == {"pos": "inti", "kasbon": "opsional", "diskon": "inti"}
    assert await _pull_map(client, db_session, minuman) == {"pos": "inti", "kasbon": "na"}


async def test_toko_tanpa_jenis_usaha_dianggap_kafe(client: AsyncClient, db_session: AsyncSession) -> None:
    await _isi_kebutuhan(db_session)
    toko = await buat_toko_siap_pakai(db_session)  # jenis_usaha None
    peta = await _pull_map(client, db_session, toko)
    assert peta["kasbon"] == "opsional" and peta["pos"] == "inti"


async def test_jenis_usaha_tanpa_data_menghasilkan_peta_kosong(client: AsyncClient, db_session: AsyncSession) -> None:
    await _isi_kebutuhan(db_session)
    toko = await buat_toko_siap_pakai(db_session)
    toko.toko.jenis_usaha = "STL"
    await db_session.commit()
    assert await _pull_map(client, db_session, toko) == {}
