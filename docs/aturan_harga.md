# Aturan hitung harga (mesin kalkulator)

Dokumen ini adalah sumber kebenaran urutan & aturan kalkulasi harga
transaksi. Kalau mau mengubah urutan/aturan, **ubah dokumen ini dulu**,
lalu samakan kedua implementasi:

- Backend: `backend/app/services/harga/kalkulator.py`
- Flutter: `lib/core/harga/kalkulator.dart`

Keduanya murni (tidak ada akses DB/network), dites bersama lewat fixture
JSON di `shared/fixtures/harga/` (dibaca oleh `pytest` dan `flutter test`
agar hasilnya wajib identik).

## Aturan angka

- Uang **selalu** `Decimal` (Python) / integer rupiah (Dart) - tidak
  pernah `float`/`double`.
- Pembulatan **ROUND_HALF_UP** ke rupiah bulat, diterapkan di **setiap**
  komponen: tiap baris item, tiap diskon, service, tiap pajak - bukan
  hanya di total akhir.

## Urutan hitung — per item

1. **Harga dasar**: pakai `harga_outlet` kalau ada (override khusus
   outlet), kalau tidak pakai `harga_jual` produk/varian.
2. **Tingkatan harga grosir** (fitur `harga_grosir`): kalau qty memenuhi
   `min_qty` sebuah tier, pakai tier dengan `min_qty` terbesar yang
   terpenuhi. Kalau ada tier outlet-spesifik dan tier umum dengan
   `min_qty` sama-sama terpenuhi pada nilai terbesar itu, **tier
   outlet-spesifik menang**.
3. **Markup tipe order** (fitur `tipe_order`): harga × (1 + markup_persen
   / 100), dibulatkan ke rupiah.
4. **Modifier**: tambahkan harga tiap modifier yang dipilih.
5. **Promo per-produk** (`cakupan='produk'`): diskon dihitung dari harga
   baris kotor (qty × harga satuan setelah langkah 1-4) untuk produk yang
   ditautkan ke promo itu. `min_belanja` promo ini dicek terhadap **baris
   itu sendiri**, bukan total keranjang.

## Urutan hitung — per transaksi

6. **Subtotal** = jumlah semua baris (setelah diskon per-produk).
7. **Diskon member** (fitur `diskon_member`): kalau pelanggan punya
   level member, subtotal × diskon_persen level itu.
8. **Promo transaksi** (`cakupan='transaksi'`): `min_belanja` dicek
   terhadap subtotal **sebelum** diskon member; `maks_diskon` membatasi
   nilainya. Diskon member dan promo transaksi **boleh menumpuk** -
   member dihitung lebih dulu, promo transaksi memotong sisa setelah
   member.
9. **Service charge**: pajak bertipe `service` dari daftar default toko.
   Kalau fitur `service_per_tipe_order` aktif dan transaksi punya
   tipe_order, hanya service yang ditautkan ke tipe_order itu (lewat
   `tipe_order_pajak`) yang dipakai - **bukan** dipecah per-produk,
   service selalu dihitung utuh atas basis transaksi.
10. **Pajak**: pajak bertipe `pajak` dari daftar default toko, dihitung
    dari basis (subtotal setelah diskon + service). Kalau fitur
    `pajak_per_produk` aktif dan ada produk dengan override pajaknya
    sendiri, basis pajak transaksi dibagi proporsional ke tiap item
    (berdasar porsi subtotal pre-diskon tiap item), item terakhir
    menyerap sisa pembulatan supaya totalnya pas; tiap item memakai
    daftar pajaknya sendiri (atau daftar default kalau tidak di-override)
    pada porsi itu. Pajak dengan `termasuk_harga=true` dilaporkan
    besarnya tapi tidak menambah total yang ditagih (sudah termasuk di
    harga).
11. **Pembulatan akhir**: total dibulatkan ke kelipatan terdekat sesuai
    `pengaturan_outlet.pembulatan` (0/100/500/1000). Selisihnya dicatat
    di kolom `pembulatan` (bisa negatif).

## Fitur nonaktif

Kalau sebuah fitur berbayar (grosir/tipe_order/diskon_member/promo/
service_per_tipe_order/pajak_per_produk) **tidak aktif** di paket toko,
langkah terkait itu dilewati sepenuhnya - hasilnya harus identik dengan
seolah-olah field terkait tidak diisi sama sekali.

## Catatan implementasi (server)

`ItemInput.diskon_override` (hanya di kalkulator.py/.dart, bukan bagian
dari aturan hitung di atas) dipakai HANYA oleh `checkout_service.py`:
body checkout dari HP sudah berisi `harga_satuan`+`diskon` final per item
(dihitung HP sendiri lewat mesin yang sama) - diisi ke field ini supaya
mesin tidak menghitung ulang diskon per-produk dari `promo` (yang akan
dobel). Keranjang Flutter sendiri TIDAK PERNAH mengisi field ini -
selalu menghitung penuh dari awal. Lihat komentar di `_ambil_konteks_harga`
pada `checkout_service.py`.

## Refund proporsional (F3.D)

Refund SEBAGIAN (refund sebagian qty dari satu/beberapa baris item) tidak
boleh cuma `qty_refund × harga_satuan` - itu mengabaikan diskon/service/
pajak yang sebenarnya "melekat" ke baris itu, dan kalau dijumlahkan semua
baris akan menyimpang dari total yang benar-benar dibayar pelanggan.
Diimplementasikan di `backend/app/services/refund_service.py`
(`split_largest_remainder` + `_hitung_alokasi_proporsional`) - **belum
ada cermin Flutter murni** (lihat "Keterbatasan" di bawah), tapi aturan
di bawah ini wajib diikuti kalau nanti dibuat.

### Alokasi per-baris (sekali per transaksi, bukan per-refund)

Dari data yang TERSIMPAN saat checkout (bukan dihitung ulang dari
`kalkulator.hitung()` - angka pajak/promo historis harus tetap dipakai
apa adanya walau pengaturan pajak toko berubah belakangan):

1. `diskon_member_total` = jumlah baris `transaksi_promo` dengan
   `nama = 'Diskon member'`.
2. `diskon_promo_total` = jumlah baris `transaksi_promo` lainnya (promo
   bernama).
3. `pajak_service_total` = jumlah SEMUA baris `transaksi_pajak` (service
   DAN pajak digabung jadi satu pool - simplifikasi yang disengaja, lihat
   "Keterbatasan").
4. Tiap total itu dibagi ke semua `item_transaksi` transaksi ini
   **proporsional terhadap `item_transaksi.subtotal`** (subtotal per
   baris SETELAH diskon per-produk, SAMA basis dengan `subtotal` di
   kalkulator), pakai **metode largest remainder** (`split_largest_remainder`):
   - Tiap baris dapat `floor(total × subtotal_baris / subtotal_transaksi)`.
   - Sisa rupiah yang belum terbagi (akibat floor) diberikan satu-satu ke
     baris dengan sisa desimal terbesar, urutan index sebagai tie-breaker.
   - Hasil akhir **selalu** sum persis = total aslinya - tidak pernah ada
     rupiah yang hilang/lebih akibat pembulatan per baris independen.
5. Alokasi ini **deterministik** (fungsi murni dari data checkout yang
   immutable) - refund sebagian berulang kali pada transaksi yang sama
   selalu memakai alokasi dasar yang sama persis, tidak dihitung ulang
   tiap kali ada refund baru.

### Nominal refund satu baris

Untuk qty yang direfund dari satu `item_transaksi` (bisa kurang dari
qty aslinya):

```
fraksi = qty_refund / item.qty
jumlah_refund = bulatkan(
    qty_refund × item.harga_satuan
    − item.diskon × fraksi                    (diskon per-produk baris ini)
    − alokasi_diskon_member_dan_promo × fraksi (porsi diskon transaksi)
    + alokasi_pajak_dan_service × fraksi       (porsi pajak+service)
)
```

Diskon **mengurangi** (pelanggan tidak bayar sebesar itu), pajak+service
**menambah** (pelanggan betul-betul membayar itu di atas harga barang).
Hasil dibulatkan ROUND_HALF_UP ke rupiah, floor di 0 (tidak pernah
negatif).

**Sifat penting**: kalau SEMUA item dari sebuah transaksi di-refund
sekaligus (refund penuh), jumlah SEMUA baris refund selalu PERSIS sama
dengan `transaksi.total` - ini properti yang dites langsung
(`test_refund_proporsional_penuh_sama_persis_dgn_total_transaksi`).

### Keterbatasan yang disengaja (dicatat, bukan ditutupi)

- **Service dan pajak digabung jadi satu pool alokasi** - refund tidak
  membedakan proporsi service vs PPN per baris (cukup utk kebutuhan
  "nominal refund per baris", tidak untuk pelaporan pajak terpisah).
- **Transaksi hasil push OFFLINE *lama* (dibuat sebelum perbaikan
  "rapikan temuan#1") atau dari client yang belum kirim rincian tidak
  punya baris `transaksi_pajak`/`transaksi_promo` sama sekali** - refund
  untuk transaksi semacam itu otomatis turun ke `qty_refund ×
  harga_satuan − item.diskon × fraksi` saja (alokasi diskon/pajak = 0),
  sama seperti perilaku sebelum F3.D. Transaksi offline BARU (client
  terbaru, lihat bagian "Rincian pajak/promo utk transaksi offline" di
  atas kalau ada, atau `CheckoutIn.rincian_pajak_klien`/
  `rincian_promo_klien` di `checkout_service.py`) SEKARANG mengirim
  rincian yang sama lengkapnya dgn online, jadi refund-nya ikut proporsional
  penuh - keterbatasan ini sekarang HANYA berlaku utk data lama/client lama,
  bukan arsitektur offline-first secara umum lagi.
- **Refund TETAP online-only, SENGAJA tidak dibuat offline-first**
  (keputusan diambil ulang & dikonfirmasi saat merapikan temuan#1-#4) -
  `lib/core/harga/refund_kalkulator.dart` memang ada (mirror
  `refund_kalkulator.py` persis, dites dari fixture JSON yang sama di
  `shared/fixtures/refund/`), TAPI itu HANYA utk memenuhi syarat "satu
  mesin hitung, fixture bersama pytest+flutter test" - modul itu TIDAK
  dipanggil dari UI produksi mana pun. Alasannya tetap sama: refund butuh
  `item_transaksi_id` SUNGGUHAN dari server (push offline checkout tidak
  pernah mengembalikan id per-item ke device), jadi refund SELALU online.
  Saat device offline, `RefundPage` (Flutter) menampilkan pesan netral
  **"Refund butuh koneksi internet"** (BUKAN pesan error teknis) begitu
  pemuatan item refundable ATAU submit refund gagal krn tidak ada koneksi
  (`BackendException.tidakAdaKoneksi`) - lihat
  `lib/features/transaksi/presentation/pages/refund_page.dart`.

## Bundling

Harga bundle = `harga_jual`/`harga_outlet` milik produk bundle itu
sendiri - **tidak ada logika khusus di mesin kalkulator untuk bundling**.
Bundling hanya memengaruhi pemotongan stok saat checkout (komponen lewat
`bundling_item`, dan kalau komponen itu sendiri punya resep, bahan baku
resepnya ikut terpotong proporsional). Bundle yang berisi bundle lain
ditolak saat disimpan.
