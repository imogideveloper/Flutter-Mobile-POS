from decimal import Decimal

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_produk, buat_toko_siap_pakai


async def test_varian_crud(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, nama="Kopi")

    resp = await client.post(
        f"/produk/{produk.id}/varian", headers=toko_a.headers, json={"nama": "Large", "harga_jual": "20000"}
    )
    assert resp.status_code == 201

    daftar = await client.get(f"/produk/{produk.id}/varian", headers=toko_a.headers)
    assert len(daftar.json()) == 1
    assert daftar.json()[0]["nama"] == "Large"


async def test_varian_produk_toko_lain_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk_b = await buat_produk(db_session, toko_b.toko.id)

    resp = await client.get(f"/produk/{produk_b.id}/varian", headers=toko_a.headers)
    assert resp.status_code == 404


async def test_grup_modifier_dan_modifier_lalu_ditautkan_ke_produk(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, nama="Kopi Susu")

    resp_grup = await client.post(
        "/grup-modifier", headers=toko_a.headers, json={"nama": "Level Gula", "min_pilih": 1, "maks_pilih": 1}
    )
    assert resp_grup.status_code == 201
    grup_id = resp_grup.json()["id"]

    resp_modifier = await client.post(
        f"/grup-modifier/{grup_id}/modifier", headers=toko_a.headers, json={"nama": "Less Sugar"}
    )
    assert resp_modifier.status_code == 201

    daftar_modifier = await client.get(f"/grup-modifier/{grup_id}/modifier", headers=toko_a.headers)
    assert len(daftar_modifier.json()) == 1

    resp_taut = await client.put(f"/produk/{produk.id}/grup-modifier/{grup_id}", headers=toko_a.headers)
    assert resp_taut.status_code == 204

    daftar_grup_produk = await client.get(f"/produk/{produk.id}/grup-modifier", headers=toko_a.headers)
    assert len(daftar_grup_produk.json()) == 1
    assert daftar_grup_produk.json()[0]["nama"] == "Level Gula"


async def test_resep_menghubungkan_produk_jadi_ke_bahan_baku(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # resep = fitur tingkat 1 (Pro) - toko_a default Gratis, pakai toko
    # Bisnis lokal (tes gating-nya sendiri ada di test_gating_fitur.py).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    kopi_susu = await buat_produk(db_session, toko_a.toko.id, nama="Kopi Susu Gula Aren")
    gula_aren = await buat_produk(db_session, toko_a.toko.id, nama="Gula Aren (bahan)")

    resp = await client.post(
        f"/produk/{kopi_susu.id}/resep",
        headers=toko_a.headers,
        json={"bahan_id": str(gula_aren.id), "qty": "0.05"},
    )
    assert resp.status_code == 201
    assert resp.json()["nama_bahan"] == "Gula Aren (bahan)"

    daftar = await client.get(f"/produk/{kopi_susu.id}/resep", headers=toko_a.headers)
    assert len(daftar.json()) == 1
    assert Decimal(daftar.json()[0]["qty"]) == Decimal("0.0500")


async def test_bundling_tidak_boleh_berisi_dirinya_sendiri(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # bundling = fitur tingkat 2 (Bisnis).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    paket = await buat_produk(db_session, toko_a.toko.id, nama="Paket Hemat")

    resp = await client.post(
        f"/produk/{paket.id}/bundling", headers=toko_a.headers, json={"produk_id": str(paket.id), "qty": "1"}
    )
    assert resp.status_code == 400


async def test_bundling_tidak_boleh_berisi_bundling_lain(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    # Aturan docs/aturan_harga.md bagian Bundling - mesin hitung cuma
    # expand satu level, bundle-dalam-bundle harus ditolak saat disimpan.
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    paket_a = await buat_produk(db_session, toko_a.toko.id, nama="Paket A")
    paket_b = await buat_produk(db_session, toko_a.toko.id, nama="Paket B")
    paket_b.tipe = "bundling"
    await db_session.commit()

    resp = await client.post(
        f"/produk/{paket_a.id}/bundling", headers=toko_a.headers, json={"produk_id": str(paket_b.id), "qty": "1"}
    )
    assert resp.status_code == 400


async def test_bundling_isi_dua_produk(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    paket = await buat_produk(db_session, toko_a.toko.id, nama="Paket Hemat")
    nasi = await buat_produk(db_session, toko_a.toko.id, nama="Nasi Putih")
    ayam = await buat_produk(db_session, toko_a.toko.id, nama="Ayam Goreng")

    for isi in (nasi, ayam):
        resp = await client.post(
            f"/produk/{paket.id}/bundling", headers=toko_a.headers, json={"produk_id": str(isi.id), "qty": "1"}
        )
        assert resp.status_code == 201

    daftar = await client.get(f"/produk/{paket.id}/bundling", headers=toko_a.headers)
    assert {b["nama_produk"] for b in daftar.json()} == {"Nasi Putih", "Ayam Goreng"}


async def test_harga_grosir_bertingkat(client: AsyncClient, db_session: AsyncSession) -> None:
    # harga_grosir = fitur tingkat 2 (Bisnis).
    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    beras = await buat_produk(db_session, toko_a.toko.id, nama="Beras 5kg", harga_jual=Decimal("65000"))

    resp = await client.post(
        f"/produk/{beras.id}/harga-grosir", headers=toko_a.headers, json={"min_qty": "5", "harga": "60000"}
    )
    assert resp.status_code == 201

    daftar = await client.get(f"/produk/{beras.id}/harga-grosir", headers=toko_a.headers)
    assert len(daftar.json()) == 1
    assert daftar.json()[0]["harga"] == "60000.00"


async def test_harga_outlet_override_harga_jual(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id, nama="Es Teh", harga_jual=Decimal("5000"))

    resp = await client.post(
        f"/produk/{produk.id}/harga-outlet",
        headers=toko_a.headers,
        json={"outlet_id": str(toko_a.outlet.id), "harga_jual": "6000"},
    )
    assert resp.status_code == 201

    daftar = await client.get(f"/produk/{produk.id}/harga-outlet", headers=toko_a.headers)
    assert len(daftar.json()) == 1
    assert daftar.json()[0]["harga_jual"] == "6000.00"


async def test_harga_outlet_milik_toko_lain_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a, toko_b
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)

    resp = await client.post(
        f"/produk/{produk.id}/harga-outlet",
        headers=toko_a.headers,
        json={"outlet_id": str(toko_b.outlet.id), "harga_jual": "1000"},
    )
    assert resp.status_code == 404
