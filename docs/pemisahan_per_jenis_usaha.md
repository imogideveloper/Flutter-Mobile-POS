# Pemisahan fitur per jenis usaha (Batch B, tahap 1)

Disusun 2026-11-16. Arahan: seluruh fitur F&B dibangun, lalu dipersempit per jenis usaha yang relevan.

## Cara kerja sekarang

1. Dokumen IMOGI mengklasifikasikan tiap fitur untuk tujuh jenis usaha F&B sebagai **inti**, **opsional**, atau **tidak relevan (na)**. Datanya ada di tabel `fitur_kebutuhan` (migrasi 0010).
2. Server mengirim klasifikasi untuk jenis usaha toko lewat `GET /sync/pull` (`kebutuhan_fitur`: kode fitur ke inti/opsional/na). Toko tanpa jenis usaha dianggap Kafe.
3. HP menyimpannya (tabel `kebutuhan_fitur`, diganti total tiap pull).
4. `FiturTerkunci` (pembungkus semua kontrol yang terkait fitur) **menyembunyikan** kontrol yang tidak relevan, bukan menguncinya. Fitur tanpa klasifikasi tetap tampil seperti biasa.
5. Dashboard Administrator memakai klasifikasi yang sama untuk filter jenis usaha.

## Kontrol yang hilang per jenis usaha

Hanya fitur yang punya kontrol di aplikasi dan ditandai tidak relevan dalam data IMOGI:

| Jenis usaha | Kontrol yang disembunyikan (kode fitur) |
|---|---|
| Kafe & Kedai Kopi (CAF) | DP untuk hutang (`dp_kasbon`), harga grosir (`harga_grosir`) |
| Restoran (RES) | DP untuk hutang, harga grosir, nomor antrean (`nomor_antrean`) |
| Katering (CAT) | diskon member, nomor antrean, poin loyalti, struk ringkas |
| Roti, Kue & Camilan (BRD) | order bayar nanti (`pay_later`), service per tipe pesanan |
| Bahan Segar & Makanan Beku (FRZ) | diskon member, DP hutang, nomor antrean, bayar nanti, service per tipe, status pesanan, tiket dapur |
| Minuman (BEV) | DP hutang, bayar nanti |
| Kios & Food Court (STL) | diskon member, DP hutang, harga grosir, bayar nanti |

## Yang belum

- Penanda untuk fitur **opsional** (mis. lencana "opsional") belum ada; saat ini opsional tampil sama dengan inti.
- Nilai bawaan pengaturan per jenis usaha: sudah service 5% Kafe/Restoran dan, sejak tahap 2, pajak PB1 10% serta pesan penutup struk (lihat Z5-Z7). Struk ringkas, nomor antrean, tiket dapur, dan modal awal shift belum.
- Menu Pengaturan versi IMOGI (11 tab, simpan otomatis, "Kembalikan ke rekomendasi") belum ada.
- Peran bawaan dan 18 hak akses IMOGI (Barista, Dapur) belum ada.
- Klasifikasi baru hanya diterima HP lewat sync; HP yang tidak sync tidak berubah.
- Perubahan jenis usaha toko setelah mendaftar belum bisa dilakukan dari aplikasi.
