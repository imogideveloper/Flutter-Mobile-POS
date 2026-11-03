"""Aturan dokumen #6: setiap query backend wajib difilter toko_id dari
token login, tidak ada endpoint yang menerima toko_id dari body/path untuk
menentukan akses. Test ini memverifikasi toko A TIDAK BISA membaca atau
mengubah data toko B sama sekali, termasuk dengan menebak UUID-nya."""

from httpx import AsyncClient


async def test_daftar_produk_toko_a_tidak_melihat_produk_toko_b(
    client: AsyncClient, toko_a, toko_b
) -> None:
    resp_buat = await client.post(
        "/produk",
        json={"nama": "Produk milik toko B", "harga_jual": "10000"},
        headers=toko_b.headers,
    )
    assert resp_buat.status_code == 201
    produk_b_id = resp_buat.json()["id"]

    resp_list_a = await client.get("/produk", headers=toko_a.headers)
    assert resp_list_a.status_code == 200
    assert resp_list_a.json() == []

    # Toko A menebak UUID produk milik toko B langsung - harus 404, bukan 200.
    resp_detail = await client.get(f"/produk/{produk_b_id}", headers=toko_a.headers)
    assert resp_detail.status_code == 404

    resp_ubah = await client.patch(
        f"/produk/{produk_b_id}", json={"nama": "Dicuri toko A"}, headers=toko_a.headers
    )
    assert resp_ubah.status_code == 404

    resp_hapus = await client.delete(f"/produk/{produk_b_id}", headers=toko_a.headers)
    assert resp_hapus.status_code == 404

    # Pemilik asli (toko B) tetap bisa lihat & produk tidak berubah.
    resp_detail_b = await client.get(f"/produk/{produk_b_id}", headers=toko_b.headers)
    assert resp_detail_b.status_code == 200
    assert resp_detail_b.json()["nama"] == "Produk milik toko B"


async def test_outlet_toko_a_tidak_bisa_diakses_toko_b(client: AsyncClient, toko_a, toko_b) -> None:
    resp_list_a = await client.get("/outlets", headers=toko_a.headers)
    assert resp_list_a.status_code == 200
    outlet_a_id = resp_list_a.json()[0]["id"]

    resp_detail_dari_b = await client.get(f"/outlets/{outlet_a_id}", headers=toko_b.headers)
    assert resp_detail_dari_b.status_code == 404

    resp_ubah_dari_b = await client.patch(
        f"/outlets/{outlet_a_id}", json={"nama": "Diubah toko B"}, headers=toko_b.headers
    )
    assert resp_ubah_dari_b.status_code == 404


async def test_endpoint_tanpa_token_ditolak(client: AsyncClient) -> None:
    resp = await client.get("/produk")
    assert resp.status_code == 401


async def test_token_toko_a_tidak_bisa_dipakai_buat_produk_atas_nama_toko_b(
    client: AsyncClient, toko_a, toko_b
) -> None:
    # toko_id SELALU dari token (get_toko_id), endpoint /produk tidak punya
    # field toko_id di body sama sekali - pastikan produk yang dibuat toko A
    # memang tercatat milik toko A, bukan toko B, walau body JSON-nya identik.
    resp = await client.post(
        "/produk", json={"nama": "Produk netral", "harga_jual": "5000"}, headers=toko_a.headers
    )
    assert resp.status_code == 201
    assert resp.json()["toko_id"] == str(toko_a.toko.id)

    resp_list_b = await client.get("/produk", headers=toko_b.headers)
    assert resp_list_b.json() == []
