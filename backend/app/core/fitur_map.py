"""Peta kode fitur berbayar (tingkat >= 1) -> endpoint yang menegakkannya.

Ini BUKAN mekanisme auto-wiring (tidak ada kode yang otomatis memasang
`Depends(require_fitur(...))` dari sini) - ini daftar REFERENSI yang
harus tetap sinkron dengan apa yang BENAR-BENAR dipasang manual di
masing-masing router/service (lihat kolom `endpoint`). Dipakai juga oleh
`tests/test_gating_fitur.py` supaya setiap baris di sini otomatis dites:
toko paket Gratis ditolak 403, toko paket Bisnis diterima.

Beberapa fitur TIDAK punya endpoint sama sekali (dikonfirmasi lewat audit
tahap sebelumnya - lihat kolom `catatan`) - sesuai instruksi "jangan
membangun fitur baru", baris itu ditandai `endpoint=None` dan TIDAK
dites, bukan dipaksa dibuatkan endpoint baru hanya supaya ada sesuatu
utk digate."""

from dataclasses import dataclass


@dataclass(frozen=True)
class PemetaanFitur:
    kode: str
    tingkat: int  # 1 Pro, 2 Bisnis
    # (method, path) endpoint yang DIGATE require_fitur(kode) - None kalau
    # tidak ada endpoint/field sama sekali utk fitur ini (lihat catatan).
    endpoint: tuple[str, str] | None
    catatan: str


FITUR_MAP: list[PemetaanFitur] = [
    PemetaanFitur("qris", 1, None, "Belum ada endpoint gateway QRIS sama sekali (audit tahap 1) - tidak dibangun di tahap ini."),
    PemetaanFitur("kasbon", 1, None, "Tahap 3b-1: checkout_service menolak 403 fitur_terkunci kalau total_bayar < total (kasbon) tapi fitur ini belum terbuka (lihat _siapkan_pembayaran_awal) - inline di /transaksi (bukan endpoint terpisah), sama pola dgn catatan_struk. Dites manual di tests/test_kasbon.py, bukan lewat endpoint_tergate() generik."),
    PemetaanFitur("tren_penjualan", 1, None, "Tidak ada endpoint tren terpisah dari laporan_dasar (audit tahap 1)."),
    PemetaanFitur("multi_outlet", 1, ("POST", "/outlets"), "Digate utk outlet KE-2 dan seterusnya (outlet pertama toko selalu boleh) - lihat routers/outlet.py. Kuota jumlah outlet dicek terpisah lewat langganan.jumlah_outlet (lihat B.5)."),
    PemetaanFitur("resep", 1, ("POST", "/produk/{produk_id}/resep"), "GET juga digate (lihat routers/produk_lanjutan.py)."),
    PemetaanFitur("ekspor_impor", 1, None, "Tidak ada endpoint ekspor/impor sama sekali (audit tahap 1)."),
    PemetaanFitur("diskon", 1, ("POST", "/promo"), "Sudah digate sejak sesi sebelumnya; GET /promo ditambah gate di tahap ini."),
    PemetaanFitur("pajak_per_produk", 1, None, "Tidak ada endpoint CRUD produk_pajak, dan tidak dipakai di checkout sama sekali (audit tahap 1)."),
    PemetaanFitur("tipe_order", 1, ("POST", "/tipe-order"), "GET juga digate; checkout_service JUGA menolak body.tipe_order_id kalau fitur ini belum terbuka (lihat B.3). Tahap 3a: markup_persen tipe_order dipakai mesin hitung harga (lihat docs/aturan_harga.md) - tapi dibakukan ke harga_satuan oleh HP, bukan dihitung ulang server."),
    PemetaanFitur("kelola_karyawan", 1, None, "Tahap 3a: CRUD pengguna dasar DILEPAS dari gate ini (toko Gratis tetap boleh tambah kasir, dibatasi paket.maks_pengguna - lihat _pastikan_kuota_pengguna di routers/pengguna.py). kelola_karyawan kini cuma utk role custom/izin, belum ada endpointnya."),
    PemetaanFitur("poin_loyalitas", 1, None, "Tahap 3a A.1: checkout_service HANYA memanggil tambah_poin_dari_transaksi kalau has_fitur - inline (has_fitur), bukan endpoint terpisah utk digate require_fitur di sini."),
    PemetaanFitur("diskon_member", 1, None, "Tahap 3a: dipakai di harga/kalkulator.py (level_member.diskon_persen pelanggan) - gating-nya inline lewat fitur_aktif yang dikirim ke mesin hitung (has_fitur), bukan endpoint terpisah."),
    PemetaanFitur("survei", 1, None, "Tidak ada endpoint survei sama sekali (audit tahap 1)."),
    PemetaanFitur("absensi", 1, None, "Tidak ada endpoint absensi sama sekali (audit tahap 1)."),
    PemetaanFitur("struk_ringkas", 2, None, "Tahap 4: PATCH /outlets/{id}/pengaturan menolak 403 fitur_terkunci kalau diisi True tanpa fitur ini (lihat routers/outlet.py) - inline per-field, bukan endpoint terpisah (endpoint-nya sendiri, GET/PATCH pengaturan, TIDAK digate - semua paket boleh ubah field lain). Dites manual di tests/test_pengaturan_struk.py."),
    PemetaanFitur("tiket_dapur", 2, None, "Sudah digate INLINE di checkout_service.py (has_fitur, bukan require_fitur) sejak sesi sebelumnya - bukan endpoint terpisah, tidak perlu baris baru di sini."),
    PemetaanFitur("catatan_struk", 2, None, "Tahap 3a A.1: checkout_service menolak 403 fitur_terkunci kalau body.catatan diisi tapi fitur ini belum terbuka (lihat _validasi_kepemilikan) - inline, bukan endpoint terpisah."),
    PemetaanFitur("service_per_tipe_order", 2, None, "Tahap 3a: tipe_order_pajak dipakai mesin hitung harga (filter service per tipe_order) - gating inline lewat fitur_aktif, bukan endpoint terpisah."),
    PemetaanFitur("status_pesanan", 2, None, "transaksi.status_pesanan tidak pernah di-set/dibaca endpoint manapun (audit tahap 1)."),
    PemetaanFitur("dp_kasbon", 2, None, "Tahap 3b-1: checkout_service menolak 403 fitur_terkunci kalau 0 < total_bayar < total (DP) tapi fitur ini belum terbuka - toko dgn 'kasbon' saja (tanpa ini) cuma boleh bayar 0 di awal (lihat _siapkan_pembayaran_awal). Inline di /transaksi, dites manual di tests/test_kasbon.py."),
    PemetaanFitur("nomor_antrean", 2, ("POST", "/antrean/nomor"), "Endpoint ambil nomor antrean digate langsung - CheckoutIn sendiri tidak punya field nomor_antrean (audit tahap 1, dead-end arsitektur lama)."),
    PemetaanFitur("label_pembayaran", 2, None, "Tahap 4: PATCH /metode-bayar/{id} menolak 403 fitur_terkunci kalau body mengisi nama/urutan tanpa fitur ini (aktif/nonaktif TIDAK digate) - inline per-field di routers/penjualan_setup.py, dites manual di tests/test_pengaturan_struk.py."),
    PemetaanFitur("logo_struk", 2, None, "Tahap 4: POST /toko/logo (routers/toko.py) digate require_fitur langsung - endpoint=None di sini BUKAN krn belum ada endpoint (sekarang ADA), tapi krn endpoint ini butuh multipart file upload yang harness test_gating_fitur.py (client.request json=/params= saja) tidak dukung. Dites manual di tests/test_pengaturan_struk.py."),
    PemetaanFitur("bundling", 2, ("POST", "/produk/{produk_id}/bundling"), "GET juga digate; endpoint ini JUGA menolak 400 kalau isinya produk bundling lain (lihat docs/aturan_harga.md). Tahap 3a: checkout_service SEKARANG expand bundling_item utk potong stok komponen (+ resep komponen itu kalau ada) - lihat _potong_stok_item."),
    PemetaanFitur("pengingat_kedaluwarsa", 2, None, "batch_stok 100% tidak terpakai di backend (audit tahap 1)."),
    PemetaanFitur("harga_grosir", 2, ("POST", "/produk/{produk_id}/harga-grosir"), "GET juga digate. Tahap 3a: tier harga_grosir dipakai mesin hitung harga (harga/kalkulator.py) - tapi di checkout server harga_satuan sudah dibakukan HP, jadi gating aktual terjadi di sisi HP (keranjang) + fixture, bukan di endpoint checkout ini."),
]


def endpoint_tergate() -> list[PemetaanFitur]:
    return [f for f in FITUR_MAP if f.endpoint is not None]
