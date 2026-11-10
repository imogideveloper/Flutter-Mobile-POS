"""Tahap 4 bagian B: pengaturan struk (header/footer/lebar kertas/dkk),
upload logo toko, dan PATCH metode bayar - termasuk gating fitur & izin."""

import io

from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from tests.conftest import buat_metode_bayar, buat_toko_siap_pakai


async def test_ambil_dan_ubah_pengaturan_outlet(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    resp_get = await client.get(f"/outlets/{toko_a.outlet.id}/pengaturan", headers=toko_a.headers)
    assert resp_get.status_code == 200
    body = resp_get.json()
    assert body["lebar_kertas_mm"] == 58
    assert body["struk_ringkas"] is False

    resp_patch = await client.patch(
        f"/outlets/{toko_a.outlet.id}/pengaturan",
        headers=toko_a.headers,
        json={"header_struk": "Toko Uji Coba", "footer_struk": "Terima kasih", "lebar_kertas_mm": 80},
    )
    assert resp_patch.status_code == 200
    body2 = resp_patch.json()
    assert body2["header_struk"] == "Toko Uji Coba"
    assert body2["footer_struk"] == "Terima kasih"
    assert body2["lebar_kertas_mm"] == 80


async def test_ubah_izinkan_stok_minus_tersimpan(client: AsyncClient, toko_a) -> None:
    """Dulu kolom ini CUMA bisa dibaca (ada di PengaturanOutletOut) tapi
    tidak pernah bisa diubah lewat PATCH (hilang dari PengaturanOutletIn) -
    Flutter jadi tidak punya cara mematikan "izinkan stok minus" sama
    sekali, jadi stok selalu bisa dijual sampai minus tak terbatas."""
    resp_get = await client.get(f"/outlets/{toko_a.outlet.id}/pengaturan", headers=toko_a.headers)
    assert resp_get.json()["izinkan_stok_minus"] is True

    resp = await client.patch(
        f"/outlets/{toko_a.outlet.id}/pengaturan",
        headers=toko_a.headers,
        json={"izinkan_stok_minus": False},
    )
    assert resp.status_code == 200
    assert resp.json()["izinkan_stok_minus"] is False

    resp_get2 = await client.get(f"/outlets/{toko_a.outlet.id}/pengaturan", headers=toko_a.headers)
    assert resp_get2.json()["izinkan_stok_minus"] is False


async def test_ubah_pengaturan_outlet_lebar_kertas_invalid_ditolak(
    client: AsyncClient, toko_a
) -> None:
    resp = await client.patch(
        f"/outlets/{toko_a.outlet.id}/pengaturan", headers=toko_a.headers, json={"lebar_kertas_mm": 70}
    )
    assert resp.status_code == 400


async def test_ubah_pengaturan_outlet_butuh_izin_pengaturan_kelola(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_kasir = await buat_toko_siap_pakai(db_session, nama_role="Kasir")
    resp = await client.patch(
        f"/outlets/{toko_kasir.outlet.id}/pengaturan",
        headers=toko_kasir.headers,
        json={"header_struk": "coba"},
    )
    assert resp.status_code == 403

    resp_get = await client.get(f"/outlets/{toko_kasir.outlet.id}/pengaturan", headers=toko_kasir.headers)
    assert resp_get.status_code == 403


async def test_ubah_pengaturan_struk_ringkas_digate_fitur(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    toko_gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    resp = await client.patch(
        f"/outlets/{toko_gratis.outlet.id}/pengaturan",
        headers=toko_gratis.headers,
        json={"struk_ringkas": True},
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"
    assert resp.json()["detail"]["fitur"] == "struk_ringkas"

    # Mematikannya (False) TIDAK digate - selalu boleh.
    resp_off = await client.patch(
        f"/outlets/{toko_gratis.outlet.id}/pengaturan",
        headers=toko_gratis.headers,
        json={"struk_ringkas": False},
    )
    assert resp_off.status_code == 200

    toko_bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resp2 = await client.patch(
        f"/outlets/{toko_bisnis.outlet.id}/pengaturan",
        headers=toko_bisnis.headers,
        json={"struk_ringkas": True, "pakai_nomor_antrean": True},
    )
    assert resp2.status_code == 200
    assert resp2.json()["struk_ringkas"] is True
    assert resp2.json()["pakai_nomor_antrean"] is True


_PNG_1X1 = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01"
    b"\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
)


async def test_upload_logo_sukses_dan_isi_logo_url(client: AsyncClient, db_session: AsyncSession) -> None:
    from app.models.outlet import Toko

    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resp = await client.post(
        "/toko/logo",
        headers=toko.headers,
        files={"file": ("logo.png", io.BytesIO(_PNG_1X1), "image/png")},
    )
    assert resp.status_code == 200
    url = resp.json()["logo_url"]
    assert url.startswith("/static/logo/")

    toko_row = await db_session.get(Toko, toko.toko.id)
    assert toko_row.logo_url == url


async def test_upload_logo_ditolak_tanpa_fitur_logo_struk(client: AsyncClient, toko_a) -> None:
    resp = await client.post(
        "/toko/logo",
        headers=toko_a.headers,
        files={"file": ("logo.png", io.BytesIO(_PNG_1X1), "image/png")},
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"
    assert resp.json()["detail"]["fitur"] == "logo_struk"


async def test_upload_logo_ditolak_file_bukan_gambar(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    resp = await client.post(
        "/toko/logo",
        headers=toko.headers,
        files={"file": ("logo.txt", io.BytesIO(b"bukan gambar sama sekali"), "image/png")},
    )
    assert resp.status_code == 400


async def test_upload_logo_ditolak_lebih_dari_1mb(client: AsyncClient, db_session: AsyncSession) -> None:
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    konten_besar = _PNG_1X1 + b"\x00" * (1024 * 1024 + 1)
    resp = await client.post(
        "/toko/logo",
        headers=toko.headers,
        files={"file": ("logo.png", io.BytesIO(konten_besar), "image/png")},
    )
    assert resp.status_code == 400


async def test_logo_url_terisolasi_antar_toko_di_sync_pull(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    from tests.conftest import buat_perangkat

    toko_a = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    toko_b = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")

    resp_logo = await client.post(
        "/toko/logo",
        headers=toko_a.headers,
        files={"file": ("logo.png", io.BytesIO(_PNG_1X1), "image/png")},
    )
    assert resp_logo.status_code == 200

    perangkat_a = await buat_perangkat(db_session, toko_a.toko.id, toko_a.outlet.id, device_uid="dev-a")
    perangkat_b = await buat_perangkat(db_session, toko_b.toko.id, toko_b.outlet.id, device_uid="dev-b")

    pull_a = await client.get(
        "/sync/pull",
        headers=toko_a.headers,
        params={"perangkat_id": str(perangkat_a.id), "since": "1970-01-01T00:00:00Z"},
    )
    assert pull_a.status_code == 200
    assert pull_a.json()["logo_url"] is not None

    pull_b = await client.get(
        "/sync/pull",
        headers=toko_b.headers,
        params={"perangkat_id": str(perangkat_b.id), "since": "1970-01-01T00:00:00Z"},
    )
    assert pull_b.status_code == 200
    assert pull_b.json()["logo_url"] is None


async def test_patch_metode_bayar_rename_digate_fitur(client: AsyncClient, db_session: AsyncSession) -> None:
    toko_gratis = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    metode = await buat_metode_bayar(db_session, toko_gratis.toko.id)

    resp = await client.patch(
        f"/metode-bayar/{metode.id}", headers=toko_gratis.headers, json={"nama": "Tunai Kasir 1"}
    )
    assert resp.status_code == 403
    assert resp.json()["detail"]["kode"] == "fitur_terkunci"
    assert resp.json()["detail"]["fitur"] == "label_pembayaran"

    # aktif/nonaktif TIDAK digate - selalu boleh, bahkan paket Gratis.
    resp_aktif = await client.patch(
        f"/metode-bayar/{metode.id}", headers=toko_gratis.headers, json={"aktif": False}
    )
    assert resp_aktif.status_code == 200
    assert resp_aktif.json()["aktif"] is False

    toko_bisnis = await buat_toko_siap_pakai(db_session, nama_paket="Bisnis")
    metode2 = await buat_metode_bayar(db_session, toko_bisnis.toko.id)
    resp2 = await client.patch(
        f"/metode-bayar/{metode2.id}", headers=toko_bisnis.headers, json={"nama": "Tunai Kasir 1", "urutan": 1}
    )
    assert resp2.status_code == 200
    assert resp2.json()["nama"] == "Tunai Kasir 1"
    assert resp2.json()["urutan"] == 1


async def test_pengaturan_antrean_awalan_dan_angka_awal(client: AsyncClient, toko_a) -> None:
    url = f"/outlets/{toko_a.outlet.id}/pengaturan"
    bawaan = (await client.get(url, headers=toko_a.headers)).json()
    assert bawaan["antrean_awalan"] == "A" and bawaan["antrean_mulai"] == 1

    resp = await client.patch(url, headers=toko_a.headers, json={"antrean_awalan": "B2", "antrean_mulai": 100})
    assert resp.status_code == 200
    assert resp.json()["antrean_awalan"] == "B2" and resp.json()["antrean_mulai"] == 100

    # awalan boleh kosong; angka awal minimal 1; awalan hanya huruf/angka maks 5
    assert (await client.patch(url, headers=toko_a.headers, json={"antrean_awalan": ""})).status_code == 200
    assert (await client.patch(url, headers=toko_a.headers, json={"antrean_mulai": 0})).status_code == 422
    assert (await client.patch(url, headers=toko_a.headers, json={"antrean_awalan": "ABCDEF"})).status_code == 422
    assert (await client.patch(url, headers=toko_a.headers, json={"antrean_awalan": "A-1"})).status_code == 422


async def test_bug012_simpan_pengaturan_lain_tidak_gagal_karena_logo_terkunci(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """BUG-012: klien mengirim ulang seluruh pengaturan (termasuk tampil_logo=true bawaan).
    Pada paket tanpa fitur logo, itu tidak boleh menggagalkan perubahan pengaturan lain."""
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    url = f"/outlets/{toko.outlet.id}/pengaturan"
    assert (await client.get(url, headers=toko.headers)).json()["tampil_logo"] is True

    resp = await client.patch(
        url,
        headers=toko.headers,
        json={"tampil_logo": True, "izinkan_stok_minus": False, "footer_struk": "Terima kasih"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["izinkan_stok_minus"] is False and resp.json()["footer_struk"] == "Terima kasih"


async def test_bug012_menyalakan_logo_dari_mati_tetap_diblok_paket(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """Aturan paket tidak berubah: logo yang sedang mati tidak bisa dinyalakan tanpa fitur logo_struk."""
    toko = await buat_toko_siap_pakai(db_session, nama_paket="Gratis")
    url = f"/outlets/{toko.outlet.id}/pengaturan"
    assert (await client.patch(url, headers=toko.headers, json={"tampil_logo": False})).status_code == 200

    resp = await client.patch(url, headers=toko.headers, json={"tampil_logo": True})
    assert resp.status_code == 403
    assert resp.json()["detail"]["fitur"] == "logo_struk"
