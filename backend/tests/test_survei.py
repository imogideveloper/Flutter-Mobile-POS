"""IMOGI no. 59: survei pelanggan (buat, isi jawaban, hasil; digate paket; terisolasi per toko)."""

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_toko_siap_pakai

_BODY = {
    "judul": "Kepuasan",
    "tampil_di": "struk",
    "pertanyaan": [
        {"teks": "Seberapa puas?", "tipe": "rating", "wajib": True},
        {"teks": "Datang bersama siapa?", "tipe": "pilihan", "opsi": ["Sendiri", "Keluarga"]},
        {"teks": "Saran?", "tipe": "teks"},
    ],
}


async def _buat(client: AsyncClient, toko) -> dict:
    resp = await client.post("/survei", headers=toko.headers, json=_BODY)
    assert resp.status_code == 201, resp.text
    return resp.json()


def _jawab(s: dict, rating: int | None, pilihan: str | None = None, saran: str | None = None) -> dict:
    p = {q["tipe"]: q["id"] for q in s["pertanyaan"]}
    j = []
    if rating is not None:
        j.append({"pertanyaan_id": p["rating"], "nilai_angka": rating})
    if pilihan is not None:
        j.append({"pertanyaan_id": p["pilihan"], "nilai_teks": pilihan})
    if saran is not None:
        j.append({"pertanyaan_id": p["teks"], "nilai_teks": saran})
    return {"jawaban": j}


async def test_buat_isi_dan_hasil(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    s = await _buat(client, toko)
    assert [q["tipe"] for q in s["pertanyaan"]] == ["rating", "pilihan", "teks"]

    for rating, pilihan, saran in [(5, "Sendiri", "Enak"), (3, "Keluarga", None), (4, None, "Kurang AC")]:
        r = await client.post(f"/survei/{s['id']}/jawaban", headers=toko.headers, json=_jawab(s, rating, pilihan, saran))
        assert r.status_code == 201, r.text

    hasil = (await client.get(f"/survei/{s['id']}/hasil", headers=toko.headers)).json()
    assert hasil["jumlah_responden"] == 3
    rating = hasil["pertanyaan"][0]
    assert rating["rata_rata"] == 4.0 and rating["sebaran"]["5"] == 1 and rating["sebaran"]["3"] == 1
    assert hasil["pertanyaan"][1]["sebaran"] == {"Sendiri": 1, "Keluarga": 1}
    assert sorted(hasil["pertanyaan"][2]["komentar"]) == ["Enak", "Kurang AC"]


async def test_validasi_jawaban(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    s = await _buat(client, toko)
    url = f"/survei/{s['id']}/jawaban"
    assert (await client.post(url, headers=toko.headers, json=_jawab(s, 9))).status_code == 422, "rating di luar 1-5"
    assert (await client.post(url, headers=toko.headers, json=_jawab(s, None, "Sendiri"))).status_code == 422, (
        "pertanyaan wajib belum dijawab"
    )
    assert (await client.post(url, headers=toko.headers, json=_jawab(s, 4, "Ngawur"))).status_code == 422
    bad = {"title": "x"}
    assert (await client.post("/survei", headers=toko.headers, json={**_BODY, "pertanyaan": []})).status_code == 422
    assert bad  # sekadar menjaga body contoh tidak dipakai ulang


async def test_pilihan_butuh_dua_opsi_dan_survei_nonaktif_ditolak(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    r = await client.post(
        "/survei",
        headers=toko.headers,
        json={"judul": "X", "pertanyaan": [{"teks": "Pilih", "tipe": "pilihan", "opsi": ["Satu"]}]},
    )
    assert r.status_code == 422
    s = await _buat(client, toko)
    await client.patch(f"/survei/{s['id']}", headers=toko.headers, json={"aktif": False})
    r = await client.post(f"/survei/{s['id']}/jawaban", headers=toko.headers, json=_jawab(s, 5))
    assert r.status_code == 409


async def test_toko_lain_tidak_bisa_mengakses_dan_paket_gratis_terkunci(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    s = await _buat(client, a)
    assert (await client.get(f"/survei/{s['id']}/hasil", headers=b.headers)).status_code == 404
    assert (await client.get("/survei", headers=b.headers)).json() == []

    gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    assert (await client.get("/survei", headers=gratis.headers)).status_code == 403
