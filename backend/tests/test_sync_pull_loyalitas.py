"""Pull membawa level member, aturan poin, dan level_member_id pelanggan (klien baru login tidak lagi kosong)."""

from decimal import Decimal

from httpx import AsyncClient

from app.models.pelanggan import AturanPoin, LevelMember, Pelanggan
from tests.conftest import buat_perangkat


async def test_pull_membawa_level_member_aturan_poin_dan_level_pelanggan(
    client: AsyncClient, db_session, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    level = LevelMember(
        toko_id=toko_a.toko.id, nama="Gold", min_total_belanja=Decimal("500000"),
        diskon_persen=Decimal("10"), pengali_poin=Decimal("2"), urutan=1,
    )
    db_session.add(level)
    await db_session.flush()
    db_session.add(
        AturanPoin(toko_id=toko_a.toko.id, nominal_per_poin=Decimal("1000"), nilai_tukar_poin=Decimal("100"), min_tukar_poin=5, aktif=True)
    )
    db_session.add(Pelanggan(toko_id=toko_a.toko.id, nama="Budi", level_member_id=level.id))
    await db_session.commit()

    resp = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={"since": "1970-01-01T00:00:00+00:00", "perangkat_id": str(perangkat.id)},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert [x["nama"] for x in body["level_member"]] == ["Gold"]
    assert Decimal(body["level_member"][0]["diskon_persen"]) == Decimal("10")
    assert len(body["aturan_poin"]) == 1
    assert body["aturan_poin"][0]["min_tukar_poin"] == 5
    assert body["pelanggan"][0]["level_member_id"] == str(level.id)
