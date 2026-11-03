from datetime import UTC, datetime, timedelta

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.produk import Produk
from tests.conftest import buat_perangkat, buat_produk


async def test_pull_dengan_limit_menandai_has_more(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    await buat_produk(db_session, toko_a.toko.id, nama="Produk 1")
    await buat_produk(db_session, toko_a.toko.id, nama="Produk 2")
    await buat_produk(db_session, toko_a.toko.id, nama="Produk 3")
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    epoch_awal = datetime(1970, 1, 1, tzinfo=UTC)
    resp = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={"since": epoch_awal.isoformat(), "perangkat_id": str(perangkat.id), "limit": 2},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["produk"]) == 2
    assert body["has_more"]["produk"] is True
    # Tabel lain yang kosong tidak boleh ikut ke-flag has_more.
    assert body["has_more"]["kategori"] is False


async def test_pull_paging_sampai_habis_mengambil_semua_baris_tanpa_duplikat(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    # updated_at diisi EKSPLISIT, beda tiap baris - SQLite CURRENT_TIMESTAMP
    # cuma resolusi 1 detik, jadi 5 insert beruntun dlm test bisa dapat
    # timestamp identik & bikin cursor `updated_at > since` strict
    # ke-skip baris yang timestamp-nya sama persis dgn `since` (lihat
    # catatan "Keterbatasan" di README - risiko nyata tapi kecil di
    # Postgres produksi krn resolusinya microsecond).
    dasar = datetime(2026, 1, 1, tzinfo=UTC)
    for i in range(5):
        produk = Produk(toko_id=toko_a.toko.id, nama=f"Produk {i}", updated_at=dasar + timedelta(seconds=i))
        db_session.add(produk)
    await db_session.commit()
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    since = datetime(1970, 1, 1, tzinfo=UTC)
    semua_nama: list[str] = []

    for _ in range(10):  # batas aman - jangan sampai loop tak berhenti kalau ada bug
        resp = await client.get(
            "/sync/pull",
            headers=toko_a.headers,
            params={"since": since.isoformat(), "perangkat_id": str(perangkat.id), "limit": 2},
        )
        body = resp.json()
        semua_nama.extend(p["nama"] for p in body["produk"])
        if not body["has_more"]["produk"] or not body["produk"]:
            break
        since = datetime.fromisoformat(body["produk"][-1]["updated_at"])

    assert len(semua_nama) == 5
    assert len(set(semua_nama)) == 5  # tidak ada yang kekirim dua kali


async def test_pull_tanpa_limit_default_cukup_besar_tidak_perlu_paging(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    await buat_produk(db_session, toko_a.toko.id)
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)

    resp = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={"since": datetime(1970, 1, 1, tzinfo=UTC).isoformat(), "perangkat_id": str(perangkat.id)},
    )
    assert resp.json()["has_more"]["produk"] is False
