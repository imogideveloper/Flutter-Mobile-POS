"""Logika hitung uang murni (subtotal, diskon, pajak, kembalian) - tidak
sentuh DB sama sekali, supaya mudah dites terpisah (aturan dokumen #10).
Port 1:1 dari logika yang sudah teruji di app Flutter
(lib/features/promo/domain/kalkulasi_pajak.dart dan kalkulasi_promo.dart)
supaya hasil hitungan server & HP selalu konsisten.

Uang SELALU Decimal (aturan dokumen #4) - tidak pernah float."""

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal


def _bulatkan(nilai: Decimal) -> Decimal:
    return nilai.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


@dataclass
class ItemHitung:
    qty: Decimal
    harga_satuan: Decimal
    diskon: Decimal = Decimal("0")

    @property
    def subtotal(self) -> Decimal:
        return _bulatkan(self.qty * self.harga_satuan) - self.diskon


@dataclass
class PajakAktif:
    nama: str
    persen: Decimal
    termasuk_harga: bool
    urutan: int


@dataclass
class RincianPajak:
    nama: str
    persen: Decimal
    jumlah: Decimal
    termasuk_harga: bool


@dataclass
class HasilPajak:
    rincian: list[RincianPajak]
    total_pajak: Decimal


def hitung_subtotal(items: list[ItemHitung]) -> Decimal:
    return sum((item.subtotal for item in items), Decimal("0"))


def hitung_pajak(basis: Decimal, pajak_aktif: list[PajakAktif]) -> HasilPajak:
    """Urutan cascading: pajak diurutkan `urutan` (mis. service dihitung
    sebelum PPN). Pajak termasuk_harga=True hanya dilaporkan besarnya
    (sudah include di harga jual) - tidak menambah base pajak berikutnya
    maupun ke total yang harus dibayar ekstra."""

    terurut = sorted(pajak_aktif, key=lambda p: p.urutan)
    base = basis
    total_pajak = Decimal("0")
    rincian: list[RincianPajak] = []

    for pajak in terurut:
        jumlah = _bulatkan(base * pajak.persen / Decimal("100"))
        rincian.append(
            RincianPajak(nama=pajak.nama, persen=pajak.persen, jumlah=jumlah, termasuk_harga=pajak.termasuk_harga)
        )
        if not pajak.termasuk_harga:
            total_pajak += jumlah
            base += jumlah

    return HasilPajak(rincian=rincian, total_pajak=total_pajak)


@dataclass
class PromoAktif:
    nama: str
    tipe: str  # persen|nominal
    nilai: Decimal
    min_belanja: Decimal
    maks_diskon: Decimal | None


def hitung_diskon_promo(basis: Decimal, promo: PromoAktif) -> Decimal:
    """Promo tidak berlaku (diskon 0) kalau `basis` belum capai
    `min_belanja`. Hasil dibatasi `maks_diskon` kalau diisi, dan tidak
    pernah melebihi `basis` itu sendiri (diskon tidak membuat total
    negatif)."""

    if basis < promo.min_belanja:
        return Decimal("0")

    if promo.tipe == "persen":
        mentah = _bulatkan(basis * promo.nilai / Decimal("100"))
    elif promo.tipe == "nominal":
        mentah = _bulatkan(promo.nilai)
    else:
        raise ValueError(f"Tipe promo tidak dikenal: {promo.tipe}")

    diskon = max(Decimal("0"), min(mentah, basis))
    if promo.maks_diskon is not None and diskon > promo.maks_diskon:
        diskon = promo.maks_diskon
    return diskon


def hitung_kembalian(total: Decimal, total_bayar: Decimal) -> Decimal:
    return total_bayar - total
