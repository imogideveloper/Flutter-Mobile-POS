"""Katalog varian/tambahan produk (dokumen IMOGI no. 42) ikut turun ke HP lewat /sync/pull."""

from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.produk import GrupModifier, Modifier, ProdukGrupModifier
from tests.conftest import buat_perangkat, buat_produk

EPOCH = datetime(1970, 1, 1, tzinfo=UTC).isoformat()


async def _buat_katalog(db: AsyncSession, toko, nama_grup: str = "Ukuran"):
    produk = await buat_produk(db, toko.toko.id, nama="Es Kopi")
    grup = GrupModifier(toko_id=toko.toko.id, nama=nama_grup, min_pilih=1, maks_pilih=1)
    db.add(grup)
    await db.flush()
    db.add_all(
        [
            Modifier(grup_modifier_id=grup.id, nama="Regular", harga_tambahan=0, urutan=0),
            Modifier(grup_modifier_id=grup.id, nama="Large", harga_tambahan=5000, urutan=1),
        ]
    )
    db.add(ProdukGrupModifier(produk_id=produk.id, grup_modifier_id=grup.id))
    await db.commit()
    return produk, grup


async def _pull(client: AsyncClient, toko, perangkat, since: str = EPOCH) -> dict:
    resp = await client.get(
        "/sync/pull", headers=toko.headers, params={"since": since, "perangkat_id": str(perangkat.id)}
    )
    assert resp.status_code == 200
    return resp.json()


async def test_pull_membawa_grup_opsi_dan_relasi_produk(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    produk, grup = await _buat_katalog(db_session, toko_a)

    body = await _pull(client, toko_a, perangkat)

    assert [g["nama"] for g in body["grup_modifier"]] == ["Ukuran"]
    assert (body["grup_modifier"][0]["min_pilih"], body["grup_modifier"][0]["maks_pilih"]) == (1, 1)
    opsi = {m["nama"]: m for m in body["modifier"]}
    assert set(opsi) == {"Regular", "Large"}
    assert opsi["Large"]["grup_modifier_id"] == str(grup.id)
    assert float(opsi["Large"]["harga_tambahan"]) == 5000
    assert body["produk_grup_modifier"] == [{"produk_id": str(produk.id), "grup_modifier_id": str(grup.id)}]


async def test_pull_berikutnya_hanya_perubahan_tetapi_relasi_selalu_snapshot_penuh(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    produk, grup = await _buat_katalog(db_session, toko_a)

    sesudah = await _pull(client, toko_a, perangkat, since=datetime.now(UTC).isoformat())
    assert sesudah["grup_modifier"] == []
    assert sesudah["modifier"] == []
    # Relasi tidak punya updated_at: tetap dikirim lengkap supaya HP bisa mengganti seluruhnya.
    assert len(sesudah["produk_grup_modifier"]) == 1


async def test_pull_tidak_membawa_katalog_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    perangkat_a = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    await _buat_katalog(db_session, toko_b, nama_grup="Rahasia B")

    body = await _pull(client, toko_a, perangkat_a)
    assert body["grup_modifier"] == []
    assert body["modifier"] == []
    assert body["produk_grup_modifier"] == []


async def test_pull_tanpa_katalog_tetap_valid(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    body = await _pull(client, toko_a, perangkat)
    assert body["grup_modifier"] == [] and body["modifier"] == [] and body["produk_grup_modifier"] == []


async def test_grup_dihapus_ikut_terkirim_sebagai_penanda_hapus(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    _, grup = await _buat_katalog(db_session, toko_a)
    grup.deleted_at = datetime.now(UTC)
    await db_session.commit()

    body = await _pull(client, toko_a, perangkat)
    assert body["grup_modifier"][0]["deleted_at"] is not None


async def test_set_produk_grup_ganti_seluruh_daftar_dan_tolak_produk_toko_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    perangkat = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id)
    produk1, grup = await _buat_katalog(db_session, toko_a)
    produk2 = await buat_produk(db_session, toko_a.toko.id, nama="Teh")
    asing = await buat_produk(db_session, toko_b.toko.id, nama="Asing")

    # ganti daftar: produk1 dilepas, produk2 dipasang
    resp = await client.put(
        f"/grup-modifier/{grup.id}/produk", headers=toko_a.headers, json={"ids": [str(produk2.id)]}
    )
    assert resp.status_code == 204
    body = await _pull(client, toko_a, perangkat)
    assert body["produk_grup_modifier"] == [{"produk_id": str(produk2.id), "grup_modifier_id": str(grup.id)}]

    # produk toko lain ditolak dan daftar lama tidak berubah
    resp = await client.put(
        f"/grup-modifier/{grup.id}/produk", headers=toko_a.headers, json={"ids": [str(asing.id)]}
    )
    assert resp.status_code == 404
    assert len((await _pull(client, toko_a, perangkat))["produk_grup_modifier"]) == 1

    # daftar kosong melepas semuanya
    resp = await client.put(f"/grup-modifier/{grup.id}/produk", headers=toko_a.headers, json={"ids": []})
    assert resp.status_code == 204
    assert (await _pull(client, toko_a, perangkat))["produk_grup_modifier"] == []
    assert produk1.id != produk2.id
