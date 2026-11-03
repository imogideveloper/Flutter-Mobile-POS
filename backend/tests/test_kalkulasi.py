"""Unit test logika hitung uang (aturan dokumen #10: subtotal, diskon,
pajak, pembulatan, kembalian wajib dites). Semua pure function, tidak
butuh fixture DB/client."""

from decimal import Decimal

from app.services.kalkulasi import (
    ItemHitung,
    PajakAktif,
    PromoAktif,
    hitung_diskon_promo,
    hitung_kembalian,
    hitung_pajak,
    hitung_subtotal,
)


def test_hitung_subtotal_beberapa_item() -> None:
    items = [
        ItemHitung(qty=Decimal("2"), harga_satuan=Decimal("15000")),
        ItemHitung(qty=Decimal("1"), harga_satuan=Decimal("5000")),
    ]
    assert hitung_subtotal(items) == Decimal("35000")


def test_hitung_subtotal_dengan_diskon_per_item() -> None:
    items = [ItemHitung(qty=Decimal("3"), harga_satuan=Decimal("10000"), diskon=Decimal("5000"))]
    assert hitung_subtotal(items) == Decimal("25000")


def test_hitung_pajak_satu_pajak_sederhana() -> None:
    # PPN 11% dari 30.000 = 3.300
    hasil = hitung_pajak(
        Decimal("30000"),
        [PajakAktif(nama="PPN", persen=Decimal("11"), termasuk_harga=False, urutan=0)],
    )
    assert hasil.total_pajak == Decimal("3300")
    assert hasil.rincian[0].jumlah == Decimal("3300")


def test_hitung_pajak_cascading_service_dulu_baru_ppn() -> None:
    # Service 5% dari 100.000 = 5.000 -> base jadi 105.000
    # PPN 10% dari 105.000 = 10.500
    hasil = hitung_pajak(
        Decimal("100000"),
        [
            PajakAktif(nama="PPN", persen=Decimal("10"), termasuk_harga=False, urutan=1),
            PajakAktif(nama="Service", persen=Decimal("5"), termasuk_harga=False, urutan=0),
        ],
    )
    service = next(r for r in hasil.rincian if r.nama == "Service")
    ppn = next(r for r in hasil.rincian if r.nama == "PPN")
    assert service.jumlah == Decimal("5000")
    assert ppn.jumlah == Decimal("10500")
    assert hasil.total_pajak == Decimal("15500")


def test_hitung_pajak_termasuk_harga_tidak_menambah_total() -> None:
    # Pajak termasuk_harga=True hanya dilaporkan, tidak menambah total_pajak
    # maupun base pajak berikutnya.
    hasil = hitung_pajak(
        Decimal("100000"),
        [
            PajakAktif(nama="PB1 (sudah termasuk)", persen=Decimal("10"), termasuk_harga=True, urutan=0),
            PajakAktif(nama="Service", persen=Decimal("5"), termasuk_harga=False, urutan=1),
        ],
    )
    pb1 = next(r for r in hasil.rincian if "PB1" in r.nama)
    service = next(r for r in hasil.rincian if r.nama == "Service")
    assert pb1.jumlah == Decimal("10000")  # tetap dilaporkan besarnya
    assert service.jumlah == Decimal("5000")  # base TIDAK naik jadi 110.000
    assert hasil.total_pajak == Decimal("5000")  # PB1 tidak ikut dihitung


def test_hitung_pajak_pembulatan_setengah_ke_atas() -> None:
    # 10.005 * 10% = 1000.5 -> harus bulat ke 1001 (ROUND_HALF_UP)
    hasil = hitung_pajak(
        Decimal("10005"),
        [PajakAktif(nama="PPN", persen=Decimal("10"), termasuk_harga=False, urutan=0)],
    )
    assert hasil.total_pajak == Decimal("1001")


def test_hitung_diskon_promo_persen() -> None:
    promo = PromoAktif(nama="Diskon 10%", tipe="persen", nilai=Decimal("10"), min_belanja=Decimal("0"), maks_diskon=None)
    assert hitung_diskon_promo(Decimal("50000"), promo) == Decimal("5000")


def test_hitung_diskon_promo_nominal() -> None:
    promo = PromoAktif(nama="Potongan 10rb", tipe="nominal", nilai=Decimal("10000"), min_belanja=Decimal("0"), maks_diskon=None)
    assert hitung_diskon_promo(Decimal("50000"), promo) == Decimal("10000")


def test_hitung_diskon_promo_belum_capai_min_belanja() -> None:
    promo = PromoAktif(nama="Diskon", tipe="persen", nilai=Decimal("10"), min_belanja=Decimal("100000"), maks_diskon=None)
    assert hitung_diskon_promo(Decimal("50000"), promo) == Decimal("0")


def test_hitung_diskon_promo_dibatasi_maks_diskon() -> None:
    promo = PromoAktif(nama="Diskon 50%", tipe="persen", nilai=Decimal("50"), min_belanja=Decimal("0"), maks_diskon=Decimal("10000"))
    assert hitung_diskon_promo(Decimal("100000"), promo) == Decimal("10000")


def test_hitung_diskon_promo_tidak_pernah_melebihi_basis() -> None:
    promo = PromoAktif(nama="Potongan besar", tipe="nominal", nilai=Decimal("999999"), min_belanja=Decimal("0"), maks_diskon=None)
    assert hitung_diskon_promo(Decimal("20000"), promo) == Decimal("20000")


def test_hitung_kembalian() -> None:
    assert hitung_kembalian(total=Decimal("33300"), total_bayar=Decimal("50000")) == Decimal("16700")


def test_hitung_kembalian_uang_pas() -> None:
    assert hitung_kembalian(total=Decimal("33300"), total_bayar=Decimal("33300")) == Decimal("0")
