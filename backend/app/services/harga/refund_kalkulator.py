"""Mesin hitung nominal refund proporsional - MURNI (tidak ada akses DB),
sama prinsip dgn kalkulator.py: satu sumber kebenaran, dites lewat fixture
JSON bersama (shared/fixtures/refund/) yang dibaca pytest DAN flutter test,
cermin 1:1 di lib/core/harga/refund_kalkulator.dart. Aturan lengkap ada di
docs/aturan_harga.md bagian "Refund proporsional (F3.D)" - UBAH DOKUMEN
ITU DULU kalau mau ubah aturan, lalu samakan kedua modul ini.

Dipanggil oleh app/services/refund_service.py setelah ia mengambil data
item_transaksi/transaksi_promo/transaksi_pajak dari DB dan mengubahnya
jadi input murni di sini - modul ini sendiri tidak pernah query apa pun."""

import dataclasses
from decimal import ROUND_FLOOR, ROUND_HALF_UP, Decimal


def bulatkan(nilai: Decimal) -> Decimal:
    return nilai.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


def split_largest_remainder(total: Decimal, weights: list[Decimal]) -> list[Decimal]:
    """Bagi `total` (WAJIB rupiah bulat) proporsional ke `weights` - metode
    largest remainder (Hare-Niemeyer): tiap bagian di-floor dulu, sisa
    rupiah yang belum terbagi diberikan satu-satu ke bagian dengan sisa
    desimal terbesar (dasi dipecah by urutan index, deterministik). Hasil
    SELALU sum persis = total, tidak pernah ada selisih pembulatan yang
    hilang/lebih. Weight bernilai 0 di semua baris -> semua bagian 0."""
    n = len(weights)
    if n == 0 or total == 0:
        return [Decimal("0")] * n
    total_weight = sum(weights)
    if total_weight == 0:
        return [Decimal("0")] * n

    mentah = [total * w / total_weight for w in weights]
    lantai = [m.to_integral_value(rounding=ROUND_FLOOR) for m in mentah]
    sisa_rupiah = int(total - sum(lantai))

    urutan_sisa = sorted(range(n), key=lambda i: (-(mentah[i] - lantai[i]), i))
    hasil = list(lantai)
    for i in urutan_sisa[:sisa_rupiah]:
        hasil[i] += 1
    return hasil


@dataclasses.dataclass(frozen=True)
class ItemRefundInput:
    item_transaksi_id: str
    qty: Decimal
    harga_satuan: Decimal
    diskon: Decimal  # diskon per-produk baris ini (promo cakupan='produk')
    subtotal: Decimal  # dasar pembagian proporsional (SAMA basis dgn kalkulator.py)


@dataclasses.dataclass(frozen=True)
class RefundLineInput:
    item_transaksi_id: str
    qty_refund: Decimal


@dataclasses.dataclass(frozen=True)
class HasilRefundLine:
    item_transaksi_id: str
    jumlah: Decimal


def hitung_refund_proporsional(
    items: tuple[ItemRefundInput, ...],
    diskon_transaksi_total: Decimal,
    pajak_service_total: Decimal,
    refund_lines: tuple[RefundLineInput, ...],
) -> tuple[HasilRefundLine, ...]:
    """`items` = SEMUA baris item_transaksi dari transaksi asal (dipakai
    sbg basis alokasi, bukan cuma yang direfund) - `refund_lines` = baris
    yang BENAR-BENAR direfund sekarang (bisa subset, qty_refund <= qty)."""
    weights = [i.subtotal for i in items]
    alokasi_diskon = split_largest_remainder(diskon_transaksi_total, weights)
    alokasi_pajak = split_largest_remainder(pajak_service_total, weights)

    peta_diskon = {items[i].item_transaksi_id: alokasi_diskon[i] for i in range(len(items))}
    peta_pajak = {items[i].item_transaksi_id: alokasi_pajak[i] for i in range(len(items))}
    item_by_id = {i.item_transaksi_id: i for i in items}

    hasil: list[HasilRefundLine] = []
    for line in refund_lines:
        item = item_by_id[line.item_transaksi_id]
        fraksi = line.qty_refund / item.qty if item.qty else Decimal("0")
        jumlah = bulatkan(
            line.qty_refund * item.harga_satuan
            - item.diskon * fraksi
            - peta_diskon.get(line.item_transaksi_id, Decimal("0")) * fraksi
            + peta_pajak.get(line.item_transaksi_id, Decimal("0")) * fraksi
        )
        hasil.append(HasilRefundLine(item_transaksi_id=line.item_transaksi_id, jumlah=max(Decimal("0"), jumlah)))
    return tuple(hasil)
