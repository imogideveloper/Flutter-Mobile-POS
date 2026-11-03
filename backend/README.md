# Apps POS - Backend

FastAPI + SQLAlchemy 2 + Alembic + Pydantic, PostgreSQL 16, sesuai
`PROMPT_Senior_Mobile_Dev_POS (1).md` (sumber kebenaran skema & tech stack).

## Status

### Sudah dikerjakan
- **Skema lengkap 69 tabel** (`app/models/*.py`, 11 file per modul) +
  migrasi Alembic `0001_initial_schema` berisi DDL mentah resmi dari
  dokumen (termasuk trigger `updated_at`, index, seed `paket`/`fitur`/
  `role`/`izin`). Diverifikasi: `Base.metadata.create_all()` berhasil
  membuat semua 69 tabel di SQLite.
- **Auth**: `/auth/otp/request`, `/auth/otp/verify` (pairing device/akun -
  sekali saat pasang HP, bukan login harian), `/auth/refresh`. OTP
  tersimpan di Redis produksi / in-memory dev-test
  (`app/core/otp_store.py`), provider OTP masih mock
  (`app/services/otp_service.py` - WhatsApp/SMS asli belum, cek dulu
  dokumentasi provider resmi sebelum implementasi).
- **Multi-tenant enforcement**: `toko_id` SELALU dari JWT
  (`app/core/deps.py::get_toko_id`), tidak pernah dari body/path. Diuji
  eksplisit di `tests/test_multitenant_isolation.py`.
- **CRUD**: outlet, produk/kategori/satuan, pelanggan, pajak/promo/
  metode_bayar, pengguna/role.
- **Shift**: buka/tutup + rekonsiliasi kas (`kas_seharusnya` dihitung dari
  tunai masuk penjualan + kas manual, lihat `app/services/shift_service.py`).
- **Transaksi**: checkout dengan kalkulasi uang server-side (subtotal,
  diskon promo, pajak cascading/termasuk-harga, kembalian - semua
  `Decimal`, tidak pernah float), idempotent berdasarkan UUID transaksi
  (push ulang tidak dobel-catat), debit stok otomatis lewat
  `mutasi_stok` (boleh minus, sesuai aturan #4.3). Void dengan cek izin
  role + `audit_log`.
- **Unit test logika hitung** (`tests/test_kalkulasi.py`) terpisah dari
  DB - port 1:1 dari logika yang sudah teruji di app Flutter supaya hasil
  HP & server selalu konsisten.
- **Sync push/pull** (`/sync/push`, `/sync/pull`) - inti arsitektur
  offline-first. Push: transaksi (reuse checkout, idempotent by UUID),
  shift (insert baru ATAU update idempotent kalau device push ulang shift
  yang sama setelah ditutup), kas_shift, pelanggan baru - semua per
  batch, baris yang id-nya sudah ada tidak diproses ulang (bukan error).
  Pull: produk/kategori/satuan/pajak/promo/metode_bayar/pelanggan/
  pengguna/role (toko-scoped) + stok (outlet-scoped, kalau `outlet_id`
  dikirim), difilter `updated_at > since`, TERMASUK baris `deleted_at`
  supaya HP tahu harus menghapus lokal. Setiap push/pull tercatat di
  `sync_log` (`app/services/sync_service.py`).
- **Refund** (`POST /transaksi/{id}/refund`, `GET /transaksi/{id}/refund`)
  - mendukung refund SEBAGIAN (per item, qty berapa pun) DAN berulang
    (transaksi `refund_sebagian` bisa di-refund lagi sampai habis, baru
    status jadi `refund`). Validasi qty tidak boleh melebihi
    (qty asli - qty yang sudah pernah di-refund) per item. Opsional
    `kembalikan_stok` (default true, lewat `mutasi_stok` jenis `refund`).
    Cek izin `transaksi.refund` + `audit_log`, sama pola dgn void.
    (`app/services/refund_service.py`)
- **Laporan** (`GET /laporan/penjualan`, `GET /laporan/produk-terlaris`,
  `GET /laporan/shift/{id}`) - agregasi murni dari transaksi/
  item_transaksi/pembayaran yang sudah ada (tidak ada tabel baru), pola
  hitungnya sengaja sama dengan `LaporanRepository` di app Flutter
  (penjualan bersih, laba kotor, rata-rata, jam ramai, breakdown metode
  bayar, produk terlaris). `/laporan/shift/{id}` bisa dipanggil SAAT
  shift masih `buka` (proyeksi kas seharusnya real-time, lihat
  `hitung_kas_seharusnya` yang direuse dari `shift_service.py`), bukan
  cuma setelah ditutup. (`app/services/laporan_service.py`)
- **Fitur/paket_fitur gating** (`GET /fitur`, `GET /fitur/toko`,
  dependency `require_fitur(kode)` - `app/services/fitur_service.py`):
  toko baru otomatis didaftarkan ke paket Gratis saat registrasi
  (`Langganan` dibuat di `auth.py`), sumber kebenaran "paket X dapat
  fitur Y" adalah baris `paket_fitur` (bukan cuma `tingkat <= urutan`,
  sesuai dokumen #4.2 - walau baris paket_fitur-nya sendiri diisi
  otomatis dari perbandingan itu saat seed). `require_fitur` dipasang
  sbg contoh nyata di `POST /promo` (butuh fitur `diskon`, tingkat Pro)
  - kembalikan 402 (bukan 403) kalau paket toko belum cukup, supaya FE
  bisa beda-in "butuh upgrade" vs "tidak punya hak akses role". Kode
  fitur yang terbuka juga ikut dikirim di setiap `/sync/pull` (field
  `paket`+`kode_fitur`) supaya HP bisa `featureGate.has(kode)` dari data
  lokal tanpa round-trip tambahan.
- **Order/dapur** (`/tipe-order`, `/outlets/{id}/meja`,
  `/outlets/{id}/stasiun-dapur`, `/dapur/pesanan`, `/antrean/nomor` -
  `app/services/order_service.py`): checkout otomatis bikin satu tiket
  dapur (`pesanan_dapur`) PER STASIUN DAPUR (dikelompokkan lewat
  produk->kategori->stasiun_dapur_id), bukan satu tiket per item - tapi
  HANYA kalau toko punya fitur `tiket_dapur` (paket Bisnis, reuse
  `require_fitur`/`has_fitur` dari modul fitur gating). Toko retail tanpa
  fitur ini checkout seperti biasa, nol baris pesanan_dapur. Antrean
  harian (`ambil_nomor_antrean_berikutnya`) baca-lalu-tulis tanpa row
  lock eksplisit - lihat "Keterbatasan" di bawah.
- **Varian/modifier/resep/bundling/harga_grosir/harga_outlet**
  (`/produk/{id}/varian`, `/grup-modifier` (+`/modifier`, ditautkan ke
  produk lewat `PUT /produk/{id}/grup-modifier/{grup_id}`),
  `/produk/{id}/resep`, `/produk/{id}/bundling`,
  `/produk/{id}/harga-grosir`, `/produk/{id}/harga-outlet` -
  `app/routers/produk_lanjutan.py`). Checkout (`CheckoutIn.items[].modifiers`)
  sekarang menyimpan snapshot `item_transaksi_modifier` per item TANPA
  menambah subtotal lagi (harga modifier dianggap sudah termasuk di
  `harga_satuan` yang dikirim, konsisten dgn makna kolom itu di DDL
  resmi: "snapshot harga + modifier"). Produk dengan `pakai_resep=true`
  TIDAK memotong stoknya sendiri saat checkout - yang dipotong adalah
  stok bahan baku lewat baris `resep`, proporsional qty terjual
  (`app/services/checkout_service.py`).
- **Pembelian/stok_opname/transfer_stok** (modul "hanya di server" per
  dokumen 4.1 - TIDAK ikut `/sync/pull` sama sekali, sesuai dokumen):
  - `/supplier`, `/pembelian` + `POST /pembelian/{id}/terima` - draft
    tidak sentuh stok sama sekali, stok MASUK baru terjadi saat
    `terima` (`app/services/pembelian_service.py`); turut update
    `produk.hpp` ke harga pembelian terakhir (penyederhanaan dari HPP
    rata-rata tertimbang sungguhan).
  - `/stok-opname` + `POST /stok-opname/{id}/selesai` - `qty_sistem`
    diambil sbg SNAPSHOT saldo stok saat draft dibuat (bukan dihitung
    ulang saat selesai - itu memang maksud opname), `selisih` baru jadi
    `mutasi_stok` jenis `opname` saat status pindah ke `selesai`; item
    dengan selisih 0 tidak bikin mutasi sama sekali
    (`app/services/stok_opname_service.py`).
  - `/transfer-stok` + `POST /transfer-stok/{id}/kirim` +
    `POST /transfer-stok/{id}/terima` - DUA tahap (`kirim` = stok KELUAR
    di outlet asal, `terima` = stok MASUK di outlet tujuan) supaya ada
    jeda "barang di jalan" yang tidak dobel-hitung di stok manapun
    (`app/services/transfer_stok_service.py`).
- **ARQ worker** (`app/jobs/arq_worker.py`, logika di
  `app/services/jobs_service.py`): dua cron job -
  `tandai_langganan_kedaluwarsa` (langganan aktif yang `berakhir`-nya
  sudah lewat ditandai `kedaluwarsa` + kirim `notifikasi`, langganan
  tanpa `berakhir`/NULL seperti paket Gratis tidak pernah disentuh) dan
  `cek_stok_menipis_dan_notifikasi` (stok <= `batas_minimum`, `batas_minimum`
  0 diabaikan supaya produk yg belum diatur batasnya tidak berisik,
  TIDAK kirim notifikasi dobel selama yang lama belum dibaca). Logika
  dipisah dari wrapper ARQ supaya bisa dites tanpa Redis - **wrapper
  `WorkerSettings`-nya sendiri belum pernah dicoba jalan sungguhan**
  (tidak ada Redis di sandbox), lihat "Keterbatasan".
- **Audit log read-only** (`GET /audit-log`, filter `tabel`/`record_id`/`sejak`
  - `app/routers/audit.py`): digating izin `laporan.lihat` (dokumen
  tidak punya kode izin khusus audit) supaya Kasir tidak bisa intip
  jejak aksi sensitif orang lain, tapi Owner/Manajer bisa.
- **Sync pull paging** (`limit` query param, default 500 max 2000,
  response `has_more` per tabel - `app/services/sync_service.py`):
  tiap tabel diurutkan `updated_at ASC` dan dibatasi `limit`; kalau
  masih ada sisa, `has_more["<tabel>"]` jadi `true` dan client WAJIB
  pull lagi dengan `since` = `updated_at` baris TERAKHIR yang diterima
  utk tabel itu. **Keterbatasan nyata yang ditemukan sambil nulis test**:
  kalau 2+ baris punya `updated_at` IDENTIK (SQLite `CURRENT_TIMESTAMP`
  cuma resolusi 1 detik - gampang kejadian di test, jauh lebih jarang
  di Postgres produksi yg microsecond), cursor `updated_at > since`
  yang strict bisa skip baris yang timestamp-nya sama persis dgn
  `since`. Belum diperbaiki dgn cursor majemuk (`updated_at`, `id`) -
  risikonya kecil di Postgres tapi nyata, dicatat di "Keterbatasan".
- **Poin loyalitas pelanggan** (`app/services/loyalty_service.py`,
  terhubung di checkout/void/refund - modul 10): checkout memberi poin
  kalau `pelanggan_id` diisi DAN toko punya `aturan_poin` aktif
  (`poin = floor(total / nominal_per_poin) x pengali_poin level_member`,
  dibulatkan HALF_UP), sekaligus menambah `pelanggan.total_belanja` dan
  mencatat `riwayat_poin`. Void membatalkan SELURUH poin+total_belanja
  dari transaksi itu; refund menguranginya PROPORSIONAL ke nilai yang
  di-refund (refund 2 dari 4 item = separuh nilai = separuh poin
  dikurangi). Toko tanpa member/aturan_poin tetap checkout normal, nol
  efek sama sekali (bukan error).
- **Antrean harian pakai row lock sungguhan** - `ambil_nomor_antrean_berikutnya`
  sekarang baca baris existing lewat `SELECT ... FOR UPDATE`
  (`with_for_update()`), jadi dua request bersamaan ke outlet+device yang
  sama di Postgres produksi akan diserialkan (request kedua menunggu
  yang pertama commit), bukan dua-duanya baca nilai basi lalu nulis
  `nomor_terakhir` yang sama. SQLite (test) memperlakukan `FOR UPDATE`
  sbg no-op - diverifikasi tidak error, tapi tidak benar2 membuktikan
  locking-nya (itu baru teruji di Postgres sungguhan).
- **Metode bayar Kartu/Transfer (manual) + split payment** (F3.A):
  toko baru sekarang otomatis diseeding 4 `MetodeBayar`
  (Tunai/QRIS/Kartu/Transfer, `auth.py::_daftarkan_toko_baru` - gap
  nyata yang sebelumnya tidak diseed sama sekali). `CheckoutIn` terima
  `split_pembayaran` opsional (list metode+jumlah) - divalidasi
  `sum(jumlah) == total_bayar` persis (400 kalau tidak sama), satu baris
  `Pembayaran` per metode (`app/services/checkout_service.py`). Kartu/
  Transfer konsisten pakai `masuk_laci=false` dari seed-nya, jadi
  `hitung_kas_seharusnya` (shift) otomatis TIDAK menghitungnya sbg kas
  tunai.
- **Filter tanggal Riwayat transaksi** (F3.B): `GET /transaksi` sekarang
  terima `dari_tanggal`/`sampai_tanggal`/`limit`/`offset`, balas
  `TransaksiListOut{items, has_more}` (limit+1 trick, sama pola dgn sync
  paging) - dipakai app Flutter sbg fallback kalau data lokal (drift)
  tidak mencakup rentang yang diminta.
- **Refund proporsional per item** (F3.D, extend modul refund yang sudah
  ada): perhitungan alokasi diskon-transaksi + pajak/service ke tiap
  baris refund dipindah ke modul murni baru
  `app/services/harga/refund_kalkulator.py` (largest-remainder/
  Hare-Niemeyer, mirror 1:1 dgn `lib/core/harga/refund_kalkulator.dart`
  di sisi Flutter, dites dari fixture JSON bersama di
  `shared/fixtures/refund/*.json` - lihat `docs/aturan_harga.md`).
  `RefundIn.id` opsional utk idempotensi push-offline (pola sama dgn
  `CheckoutIn.id`); push-offline yang mau refund lebih dari sisa qty
  TIDAK ditolak - dipotong ke sisa yang valid (baris yang habis
  dijatuhkan, request ditolak 409 HANYA kalau SEMUA baris habis), dicatat
  `audit_log` (`aksi="refund_offline_melebihi_qty"`) + `Notifikasi` ke
  owner (mirror pola `kasbon_lewati_batas` yang sudah ada). Baris
  `item_transaksi` dikunci (`with_for_update()`) saat refund utk
  mencegah race dua device offline refund qty yang sama bersamaan.
  Endpoint baru `GET /transaksi/{id}/item-refundable` (izin
  `transaksi.refund`) utk app menampilkan sisa qty per item sebelum
  submit.
- **Simpan pesanan / open bill, backend-only backup** (F3.E):
  `POST /transaksi/pesanan-tersimpan` + `DELETE .../{id}`
  (`app/services/pesanan_tersimpan_service.py`, router didaftarkan
  SEBELUM `transaksi.router` di `main.py` - urutan penting, lihat
  komentar di situ soal route-swallowing Starlette) - SENGAJA minimal:
  percaya subtotal yang dikirim client (tidak dihitung ulang server),
  TIDAK memotong stok, TIDAK membuat baris `Pembayaran`. Tujuannya cuma
  cadangan data draft kalau device hilang/rusak - bukan sumber kebenaran
  yang bisa diresume dari device lain (device lain yang resume draft
  toko yang sama akan dapat draft kosong, batasan ini didokumentasikan,
  bukan bug).
- **Halaman paket langganan (safe, tanpa pembayaran in-app)** (F3.F):
  `GET /paket` (join `Fitur` lewat `PaketFitur`, bukan hardcode),
  `GET /langganan/saya` (paket aktif + pemakaian outlet/pengguna/produk),
  `POST /langganan/permintaan-upgrade` (tabel baru `PermintaanUpgrade` -
  cuma mencatat minat, TIDAK ada link pembayaran eksternal sama sekali,
  sesuai permintaan). Aktivasi SELALU manual oleh admin platform lewat
  `POST /admin/langganan/aktivasi`, digating `X-Admin-Api-Key` header
  (`app/core/admin_auth.py` - fail-safe: `ADMIN_API_KEY` kosong =
  SELALU ditolak), setiap aktivasi tercatat `audit_log`. **Bug nyata
  ditemukan+diperbaiki**: toko bisa punya 2 baris `Langganan` "aktif"
  sekaligus (baris Gratis awal tidak pernah dinonaktifkan saat upgrade),
  dan `ORDER BY created_at DESC LIMIT 1` tidak reliable kalau timestamp-nya
  identik (resolusi 1 detik SQLite) - diperbaiki dgn eksplisit
  men-nonaktifkan (`status='batal'`) semua baris aktif/trial lama SEBELUM
  insert baris baru, menegakkan invarian "cuma satu langganan efektif per
  toko".
- 288 test, semua hijau, jalan di SQLite in-memory (`pytest`, tanpa
  Postgres sungguhan - lihat bagian "Keterbatasan" di bawah).
- **`AuthOut` (`/auth/otp/verify`) sekarang ikut mengembalikan
  `perangkat_id`** - sebelumnya `_upsert_perangkat` membuat/memperbarui
  baris `Perangkat` tapi id-nya tidak pernah dikirim balik ke client,
  padahal `/sync/push` WAJIB `perangkat_id` di body. Tanpa field ini app
  Flutter yang baru pairing tidak punya cara tahu id device-nya sendiri
  utk sync - ditemukan & diperbaiki sambil menyambungkan app Flutter ke
  backend ini (lihat juga `lib/features/auth/presentation/pages/
  otp_login_page.dart` di sisi app).
- **Rapikan 4 temuan laporan F3.A-F**:
  1. *Rincian pajak/promo utk transaksi offline* - `CheckoutIn` terima
     `rincian_pajak_klien`/`rincian_promo_klien` opsional (HP sudah
     hitung lewat `lib/core/harga/kalkulator.dart`), disimpan APA ADANYA
     ke `transaksi_pajak`/`transaksi_promo` sesuai aturan "simpan angka
     HP" push-offline; `pajak_id`/`promo_id` yang tidak dikenal/bukan
     milik toko disimpan NULL + `audit_log` (`checkout_service.py`).
     Refund proporsional (F3.D) otomatis ikut bekerja penuh utk
     transaksi offline BARU yang sudah kirim rincian ini (tidak lagi
     cuma turun ke formula sederhana).
  2. *Jejak pembatalan pesanan tersimpan* - endpoint baru
     `POST /transaksi/pesanan-tersimpan/{id}/batalkan` (online) + kategori
     `pesanan_batal` di `/sync/push` (offline) memanggil service yang
     SAMA (`batalkan_pesanan_tersimpan` - `pesanan_tersimpan_service.py`):
     alasan wajib, `audit_log` (siapa/kapan/isi pesanan/total/alasan),
     approval PIN owner/manajer (izin baru `transaksi.batal_pesanan`,
     migrasi `0005`) wajib kalau yang membatalkan tidak berizin sendiri
     DAN total > `batas_approval_batal_pesanan` (default Rp0 - config
     baru di `app/core/config.py`). Laporan "dibatalkan per kasir" lewat
     filter `aksi` baru di `GET /audit-log` (bukan endpoint baru).
  3. *Verifikasi kuota paket* - audit ditemukan: `maks_outlet` SUDAH
     ditegakkan (`outlet_service.py`) tapi punya bug nyata (lihat poin
     di bawah), `maks_pengguna` SUDAH ditegakkan (`routers/pengguna.py`),
     `maks_produk` TIDAK PERNAH ditegakkan sama sekali (`routers/produk.py`
     - gap nyata). **Bug ditemukan+diperbaiki**: `pastikan_kuota_outlet`
     query `Langganan` langsung by `status='aktif'` SAJA (tidak cek
     `berakhir`), beda dgn `paket_efektif` - langganan yang SUDAH
     kedaluwarsa tapi belum di-cron-update statusnya tetap dipakai
     `jumlah_outlet` lamanya. Diperbaiki dgn `langganan_aktif_toko`
     (fitur_service.py, definisi "aktif" SAMA dgn paket_efektif) dipakai
     konsisten. `maks_produk` sekarang ditegakkan (soft-delete TIDAK
     dihitung). Format error disatukan jadi
     `{"kode":"kuota_habis","jenis":"outlet|pengguna|produk","batas":N}`
     (sebelumnya outlet pakai kode terpisah `kuota_outlet_habis`).
  4. *Refund saat offline* - TETAP online-only (keputusan dikonfirmasi
     ulang, bukan diubah) - Flutter `RefundPage` menampilkan pesan netral
     "Refund butuh koneksi internet" (bukan error teknis) saat
     `BackendException.tidakAdaKoneksi`, dicatat di
     `docs/aturan_harga.md`.

  Lihat `backend/tests/test_offline_rincian_pajak_promo.py`,
  `test_pesanan_batal.py`, dan bagian kuota baru di `test_gating_fitur.py`.

### Belum dikerjakan (lanjutan yang disarankan, urut prioritas)
1. **Bundling belum di-expand saat checkout** - `bundling_item` sekarang
   cuma CRUD definisi isi paket (produk X berisi produk Y qty Z), tapi
   checkout TIDAK otomatis memotong stok komponen saat produk bundling
   terjual (beda dgn resep, yang sudah terhubung penuh). Perlu logika
   serupa resep (expand saat checkout) kalau mau benar2 jalan.
2. **`harga_grosir`/`harga_outlet` belum dipakai otomatis saat checkout** -
   endpoint-nya CRUD lengkap, tapi harga akhir di `ItemTransaksiIn.harga_satuan`
   masih sepenuhnya tanggung jawab device (device yang query harga mana
   yang berlaku, bukan server yang mencocokkan qty/outlet otomatis).
   Konsisten dgn filosofi "harga_satuan = snapshot dari HP", tapi dicatat
   di sini biar jelas bukan oversight.
3. **`tipe_order`/`meja` belum dipakai validasi di checkout** - `CheckoutIn.tipe_order_id`/`meja_id`
   diterima dan disimpan apa adanya, tapi server TIDAK mengecek
   `tipe_order.pakai_meja` atau menghitung `markup_persen` otomatis -
   device yang masih bertanggung jawab atas logika itu sebelum kirim.
4. **`require_fitur` baru dipasang di satu endpoint contoh** (`POST
   /promo`) - endpoint lain yang sebetulnya juga berbayar per dokumen
   (`qris` di pembayaran, `kelola_karyawan` di `/pengguna`, dst.) belum
   digating. `app/core/seed.py::_FITUR` juga baru subset representatif
   (10 dari 31 fitur resmi) - cukup utk test, tapi perlu dilengkapi kalau
   endpoint baru mau digating fitur spesifik yang belum ada di situ.
5. **`pembelian.hpp` disederhanakan jadi "harga pembelian terakhir"** -
   bukan HPP rata-rata tertimbang sungguhan (butuh saldo qty sebelum+
   sesudah yang presisi per baris mutasi, di luar scope minimal modul
   ini). Cukup akurat utk toko kecil dgn pembelian jarang, tapi akan
   melenceng kalau harga beli sering naik-turun drastis antar pembelian.
6. **Poin loyalitas belum punya kedaluwarsa** - `aturan_poin.kedaluwarsa_hari`
   ada kolomnya tapi belum ada job/logika yang benar2 menghanguskan poin
   lama (`job_tandai_langganan_kedaluwarsa`/`job_cek_stok_menipis` yang
   ada sekarang tidak menyentuh poin sama sekali). Juga belum ada
   endpoint utk MENUKAR poin (`nilai_tukar_poin`/`min_tukar_poin` di
   `aturan_poin` juga baru kolom, belum ada logikanya).
7. **Refund proporsional: service+pajak dipool jadi satu alokasi, tidak
   dipisah per jenis** (F3.D) - lihat "Keterbatasan yang disengaja" di
   `docs/aturan_harga.md`. Transaksi push-offline yang client-nya BELUM
   kirim rincian (atau transaksi lama dari sebelum perbaikan "rapikan
   temuan#1") tidak punya baris `transaksi_promo`/`transaksi_pajak` -
   otomatis terdegradasi ke formula refund sederhana lama (qty x
   harga_satuan tanpa proporsi diskon/pajak) - bukan bug, konsekuensi
   wajar dari tidak adanya data alokasi utk transaksi semacam itu.
8. **Kuota pengguna/outlet/produk ditegakkan via `paket_efektif` saat ini
   saja** - cek dilakukan tepat saat endpoint dipanggil (`POST /pengguna`,
   `POST /outlets`, `POST /produk`); tidak ada job terjadwal yang
   menyisir ulang toko yang SUDAH kelebihan kuota sejak langganannya
   kedaluwarsa (mis. toko dgn 5 outlet yang paketnya expired - 5 outlet
   lama itu TETAP aktif/tidak dihapus, cuma tidak bisa tambah outlet
   baru). Ini konsisten dgn kalimat "data lama tetap ada, tidak dihapus"
   di semua gating lain di proyek ini, bukan oversight.

## Menjalankan test

```bash
cd backend
.venv/Scripts/python.exe -m pytest        # Windows
# atau: source .venv/bin/activate && pytest   # Linux/Mac
```

Semua test pakai SQLite in-memory (`aiosqlite`) lewat
`Base.metadata.create_all()` - BUKAN lewat Alembic (lebih cepat, cukup
untuk menguji logika). Seed role/izin dasar dibuat ulang per-test lewat
`app/core/seed.py` (subset kecil dari seed produksi di migrasi 0001 -
lihat komentar di file itu kenapa dua jalur ini sengaja terpisah).

## Menjalankan lewat Docker Compose

**BELUM dicoba di sandbox ini** (tidak ada Docker tersedia) - wajib
dites ulang di mesin yang punya Docker sebelum dipakai produksi.

```bash
cp .env.example .env    # lalu isi JWT_SECRET dengan nilai acak
docker compose up --build
docker compose exec api alembic upgrade head   # kalau belum otomatis
```

## Keterbatasan yang diketahui (jujur, bukan disembunyikan)

- **Migrasi 0001 belum pernah benar-benar dijalankan ke Postgres
  sungguhan** di sandbox ini (tidak ada Postgres tersedia) - hanya
  `alembic history` (baca graf revisi, tidak butuh koneksi DB) dan
  `Base.metadata.create_all()` di SQLite yang sudah diverifikasi. Wajib
  dites `alembic upgrade head` ke Postgres 16 asli sebelum dipakai.
- **bcrypt dipakai langsung, bukan lewat `passlib.CryptContext`** - lihat
  komentar di `app/core/security.py`: passlib 1.7.4 punya self-test
  internal yang crash di bcrypt>=4 (environment ini tidak punya akses
  internet utk downgrade bcrypt, jadi beralih ke bcrypt langsung adalah
  solusi yang lebih tahan lama, bukan sekadar workaround sementara).
- **FK constraint tidak dites tegas di SQLite** (SQLite butuh
  `PRAGMA foreign_keys=ON` yang belum diaktifkan) - constraint yang sama
  tetap berlaku penuh di Postgres produksi lewat migrasi 0001.
- **Role custom per-toko** belum bisa dibuat lewat API (`POST /roles`
  belum ada) - saat ini pengguna baru hanya bisa dapat salah satu dari 3
  role bawaan sistem (Owner/Manajer/Kasir).
- **`app/jobs/arq_worker.py` belum pernah benar2 dijalankan** - tidak ada
  Redis di sandbox ini. Logika job (`app/services/jobs_service.py`)
  sudah dites langsung lewat pytest (tanpa Redis), tapi wrapper
  `WorkerSettings`/cron ARQ-nya sendiri cuma diverifikasi bisa
  di-import+construct (`RedisSettings.from_dsn(...)` jalan tanpa
  connect), BUKAN benar2 jalan memproses job. Wajib dites
  `arq app.jobs.arq_worker.WorkerSettings` ke Redis sungguhan sebelum
  diandalkan produksi.
- **Cursor sync pull rentan timestamp kembar** - `/sync/pull` yang baru
  (paging per tabel) pakai `updated_at > since` strict sbg cursor. Kalau
  2+ baris share `updated_at` yang IDENTIK (gampang kejadian di SQLite
  test krn `CURRENT_TIMESTAMP` cuma resolusi 1 detik, jauh lebih jarang
  di Postgres produksi yg microsecond), baris yang timestamp-nya sama
  persis dgn `since` bisa ikut terlewat. Perbaikan yang benar adalah
  cursor majemuk `(updated_at, id)`, belum diimplementasikan - dicatat
  sbg utang teknis, bukan ditutup-tutupi (lihat `tests/test_sync_paging.py`
  yang sengaja mengisi `updated_at` eksplisit berbeda per baris persis
  krn alasan ini).
