"""Mesin hitung harga - SATU-SATUNYA sumber kebenaran kalkulasi harga
transaksi, dipakai checkout server (app/services/checkout_service.py) DAN
punya cermin 1:1 di Flutter (lib/core/harga/kalkulator.dart). Urutan
hitung & aturan pembulatan didokumentasikan di docs/aturan_harga.md -
UBAH DOKUMEN ITU DULU kalau mau ubah urutan, lalu samakan kedua modul ini.

Modul ini MURNI - tidak ada akses DB/network sama sekali, semua data
(tier harga grosir, pajak aktif, dsb) sudah diambil & disaring pemanggil
lebih dulu. Ini supaya logikanya bisa dites lewat fixture JSON bersama
(shared/fixtures/harga/) tanpa server/device sungguhan, dan supaya
checkout server & keranjang HP tidak bisa diam-diam melenceng.

Uang SELALU Decimal, pembulatan ROUND_HALF_UP ke rupiah di SETIAP
komponen (tiap baris, diskon, service, tiap pajak) - tidak pernah float."""

import dataclasses
from decimal import ROUND_HALF_UP, Decimal


def bulatkan(nilai: Decimal) -> Decimal:
    return nilai.quantize(Decimal("1"), rounding=ROUND_HALF_UP)


@dataclasses.dataclass(frozen=True)
class HargaGrosirTier:
    min_qty: Decimal
    harga: Decimal
    outlet_id: str | None = None  # None = tier umum (berlaku semua outlet)


@dataclasses.dataclass(frozen=True)
class ModifierInput:
    nama: str
    harga: Decimal


@dataclasses.dataclass(frozen=True)
class PajakInput:
    id: str
    nama: str
    persen: Decimal
    termasuk_harga: bool
    urutan: int = 0


@dataclasses.dataclass(frozen=True)
class PromoInput:
    id: str
    nama: str
    tipe: str  # persen|nominal
    cakupan: str  # produk|transaksi
    nilai: Decimal
    min_belanja: Decimal = Decimal("0")
    maks_diskon: Decimal | None = None
    # Relevan kalau cakupan='produk' - id produk yang ditautkan (promo_produk).
    produk_ids: frozenset = dataclasses.field(default_factory=frozenset)


@dataclasses.dataclass(frozen=True)
class TipeOrderInput:
    id: str
    markup_persen: Decimal = Decimal("0")
    # id pajak (tipe 'service') yang ditautkan lewat tipe_order_pajak.
    pajak_ids: frozenset = dataclasses.field(default_factory=frozenset)


@dataclasses.dataclass(frozen=True)
class ItemInput:
    produk_id: str
    varian_id: str | None
    nama_produk: str
    qty: Decimal
    harga_jual: Decimal
    harga_outlet: Decimal | None = None
    harga_grosir_tiers: tuple = ()
    modifiers: tuple = ()
    # None = pakai pajak_default toko; list (termasuk kosong) = override
    # produk_pajak produk ini (dipakai HANYA kalau fitur pajak_per_produk aktif).
    pajak_produk: tuple | None = None
    # Dipakai HANYA oleh checkout server: body request sudah berisi diskon
    # per-item yang dihitung HP sendiri (promo cakupan='produk' dkk, lewat
    # kalkulator.dart yang sama) - diisi di sini supaya mesin TIDAK
    # menghitung ulang dari `promo` (yang akan dobel). None = hitung dari
    # `promo` seperti biasa (jalur normal keranjang Flutter/fixture).
    diskon_override: Decimal | None = None


@dataclasses.dataclass(frozen=True)
class TransaksiInput:
    items: tuple
    fitur_aktif: frozenset = dataclasses.field(default_factory=frozenset)
    promo: PromoInput | None = None
    diskon_member_persen: Decimal | None = None
    tipe_order: TipeOrderInput | None = None
    pajak_default: tuple = ()  # tipe 'pajak', aktif, milik toko
    service_default: tuple = ()  # tipe 'service', aktif, milik toko
    pembulatan: int = 0  # 0|100|500|1000, dari pengaturan_outlet


@dataclasses.dataclass(frozen=True)
class RincianItemOutput:
    produk_id: str
    varian_id: str | None
    qty: Decimal
    harga_satuan: Decimal  # snapshot per-unit final (grosir+markup+modifier) - SEBELUM promo-produk
    diskon: Decimal  # hasil promo cakupan 'produk' utk baris ini
    subtotal: Decimal  # bulatkan(qty*harga_satuan) - diskon


@dataclasses.dataclass(frozen=True)
class RincianPajakOutput:
    nama: str
    persen: Decimal
    jumlah: Decimal
    termasuk_harga: bool


@dataclasses.dataclass(frozen=True)
class HasilKalkulasi:
    items: tuple
    subtotal: Decimal
    diskon_member: Decimal
    diskon_promo: Decimal
    total_diskon: Decimal
    service: Decimal
    rincian_service: tuple
    pajak: Decimal
    rincian_pajak: tuple
    total_sebelum_pembulatan: Decimal
    pembulatan: Decimal  # selisih akibat pembulatan akhir (bisa negatif)
    total: Decimal  # SUDAH dibulatkan - ini yang ditagih ke pelanggan


def _pilih_tier_grosir(qty: Decimal, tiers) -> HargaGrosirTier | None:
    terpenuhi = [t for t in tiers if qty >= t.min_qty]
    if not terpenuhi:
        return None
    min_qty_terbesar = max(t.min_qty for t in terpenuhi)
    kandidat = [t for t in terpenuhi if t.min_qty == min_qty_terbesar]
    khusus_outlet = [t for t in kandidat if t.outlet_id is not None]
    return khusus_outlet[0] if khusus_outlet else kandidat[0]


def harga_satuan_item(item: ItemInput, fitur_aktif: frozenset, tipe_order: TipeOrderInput | None) -> Decimal:
    """Publik (bukan cuma dipakai `hitung()`) - checkout_service.py server
    butuh ini terpisah utk memvalidasi batas diskon manual (tidak boleh
    melebihi garis kotor baris) SEBELUM diskon_override diterapkan."""
    basis = item.harga_outlet if item.harga_outlet is not None else item.harga_jual

    if "harga_grosir" in fitur_aktif:
        tier = _pilih_tier_grosir(item.qty, item.harga_grosir_tiers)
        if tier is not None:
            basis = tier.harga

    if "tipe_order" in fitur_aktif and tipe_order is not None and tipe_order.markup_persen:
        basis = bulatkan(basis * (Decimal("1") + tipe_order.markup_persen / Decimal("100")))

    tambahan_modifier = sum((m.harga for m in item.modifiers), Decimal("0"))
    return basis + tambahan_modifier


def _diskon_promo_nilai(basis: Decimal, promo: PromoInput) -> Decimal:
    if basis < promo.min_belanja:
        return Decimal("0")
    if promo.tipe == "persen":
        mentah = bulatkan(basis * promo.nilai / Decimal("100"))
    elif promo.tipe == "nominal":
        mentah = bulatkan(promo.nilai)
    else:
        raise ValueError(f"Tipe promo tidak dikenal: {promo.tipe}")
    diskon = max(Decimal("0"), min(mentah, basis))
    if promo.maks_diskon is not None and diskon > promo.maks_diskon:
        diskon = promo.maks_diskon
    return diskon


def _cascade_pajak(basis: Decimal, daftar) -> tuple[Decimal, tuple]:
    """Urutan cascading by `urutan` (mis. service lebih dulu dari PPN
    lewat urutan lebih kecil) - pajak termasuk_harga=True dilaporkan
    besarnya saja, TIDAK menambah base pajak berikutnya atau ke total
    ekstra yang harus dibayar (sudah include di harga)."""

    terurut = sorted(daftar, key=lambda p: p.urutan)
    base = basis
    total = Decimal("0")
    rincian = []
    for p in terurut:
        jumlah = bulatkan(base * p.persen / Decimal("100"))
        rincian.append(RincianPajakOutput(nama=p.nama, persen=p.persen, jumlah=jumlah, termasuk_harga=p.termasuk_harga))
        if not p.termasuk_harga:
            total += jumlah
            base += jumlah
    return total, tuple(rincian)


def _bulatkan_total(total: Decimal, pembulatan: int) -> tuple[Decimal, Decimal]:
    if pembulatan <= 0:
        return total, Decimal("0")
    kelipatan = Decimal(pembulatan)
    dibulatkan = (total / kelipatan).to_integral_value(rounding=ROUND_HALF_UP) * kelipatan
    return dibulatkan, dibulatkan - total


def hitung(data: TransaksiInput) -> HasilKalkulasi:
    fitur = data.fitur_aktif

    item_hasil: list[RincianItemOutput] = []
    for item in data.items:
        harga_satuan = harga_satuan_item(item, fitur, data.tipe_order)
        garis_kotor = bulatkan(item.qty * harga_satuan)

        if item.diskon_override is not None:
            diskon_item = item.diskon_override
        elif data.promo is not None and data.promo.cakupan == "produk" and item.produk_id in data.promo.produk_ids:
            diskon_item = _diskon_promo_nilai(garis_kotor, data.promo)
        else:
            diskon_item = Decimal("0")

        item_hasil.append(
            RincianItemOutput(
                produk_id=item.produk_id,
                varian_id=item.varian_id,
                qty=item.qty,
                harga_satuan=harga_satuan,
                diskon=diskon_item,
                subtotal=garis_kotor - diskon_item,
            )
        )

    subtotal = sum((i.subtotal for i in item_hasil), Decimal("0"))

    diskon_member = Decimal("0")
    if "diskon_member" in fitur and data.diskon_member_persen is not None and data.diskon_member_persen > 0:
        diskon_member = min(bulatkan(subtotal * data.diskon_member_persen / Decimal("100")), subtotal)

    basis_setelah_member = subtotal - diskon_member

    diskon_promo_transaksi = Decimal("0")
    if data.promo is not None and data.promo.cakupan == "transaksi":
        diskon_promo_transaksi = min(_diskon_promo_nilai(subtotal, data.promo), basis_setelah_member)

    basis_setelah_diskon = basis_setelah_member - diskon_promo_transaksi
    total_diskon = diskon_member + diskon_promo_transaksi

    service_list = data.service_default
    if "service_per_tipe_order" in fitur and data.tipe_order is not None:
        service_list = tuple(p for p in data.service_default if p.id in data.tipe_order.pajak_ids)

    service_total, rincian_service = _cascade_pajak(basis_setelah_diskon, service_list)
    basis_pajak = basis_setelah_diskon + service_total

    ada_override = "pajak_per_produk" in fitur and any(i.pajak_produk is not None for i in data.items)

    if not ada_override or subtotal == 0:
        pajak_total, rincian_pajak = _cascade_pajak(basis_pajak, data.pajak_default)
    else:
        pajak_total = Decimal("0")
        gabungan: dict[tuple, Decimal] = {}
        sisa_basis = basis_pajak
        n = len(data.items)
        for idx in range(n):
            item = data.items[idx]
            hasil_item = item_hasil[idx]
            if idx == n - 1:
                basis_item = sisa_basis
            else:
                proporsi = (hasil_item.subtotal / subtotal) if subtotal else Decimal("0")
                basis_item = bulatkan(basis_pajak * proporsi)
                sisa_basis -= basis_item
            daftar = item.pajak_produk if item.pajak_produk is not None else data.pajak_default
            jumlah_item, rincian_item = _cascade_pajak(basis_item, daftar)
            pajak_total += jumlah_item
            for r in rincian_item:
                key = (r.nama, r.persen, r.termasuk_harga)
                gabungan[key] = gabungan.get(key, Decimal("0")) + r.jumlah
        rincian_pajak = tuple(
            RincianPajakOutput(nama=k[0], persen=k[1], jumlah=v, termasuk_harga=k[2]) for k, v in gabungan.items()
        )

    total_sebelum_pembulatan = basis_pajak + pajak_total
    total_dibulatkan, selisih_pembulatan = _bulatkan_total(total_sebelum_pembulatan, data.pembulatan)

    return HasilKalkulasi(
        items=tuple(item_hasil),
        subtotal=subtotal,
        diskon_member=diskon_member,
        diskon_promo=diskon_promo_transaksi,
        total_diskon=total_diskon,
        service=service_total,
        rincian_service=rincian_service,
        pajak=pajak_total,
        rincian_pajak=rincian_pajak,
        total_sebelum_pembulatan=total_sebelum_pembulatan,
        pembulatan=selisih_pembulatan,
        total=total_dibulatkan,
    )
