# Uji manual printer struk (tahap 4)

`flutter test` HANYA memverifikasi `penyusun_struk.dart` (teks yang
dihasilkan) dan `esc_pos_converter.dart` (byte ESC/POS non-kosong) secara
murni - sandbox pengembangan **tidak punya printer Bluetooth maupun
perangkat Android/iOS sungguhan**, jadi seluruh jalur `print_bluetooth_
thermal` (izin, scan, sambung, kirim byte sungguhan ke kertas) belum
pernah benar-benar dicoba. Checklist di bawah WAJIB dijalankan di HP asli
+ printer thermal sungguhan sebelum rilis - jangan anggap "sudah jalan"
hanya karena `flutter test` hijau.

Siapkan dua printer kalau memungkinkan: satu 58 mm, satu 80 mm (kalau
cuma punya satu, ulangi seluruh checklist dengan printer yang sama tapi
ganti setting lebar kertas di app ke ukuran yang BUKAN ukuran fisik
printer itu sekali, untuk memastikan app tidak crash walau hasilnya
otomatis salah potong/wrap).

## 0. Persiapan

- [ ] HP Android dengan Bluetooth menyala, sudah **dipasangkan** (paired)
  lewat Pengaturan Bluetooth OS ke printer thermal (bukan dari dalam app
  - app ini cuma memilih dari yang SUDAH terpasang, tidak melakukan
  pairing sendiri).
- [ ] Printer menyala, ada kertas, baterai printer terisi cukup.
- [ ] App terpasang lewat `flutter run` (mode debug cukup) atau APK rilis
  di HP yang sama.
- [ ] Toko sudah login/pairing ke backend minimal sekali (supaya ada data
  outlet/produk utk transaksi uji).

## 1. Izin & pairing printer (Lainnya > Printer struk)

- [ ] Buka **Lainnya > Printer struk** pertama kali - app meminta izin
  Bluetooth (Android 12+: `BLUETOOTH_SCAN`+`BLUETOOTH_CONNECT`). Tolak
  izin sekali: pastikan app menampilkan pesan jelas ("Izin Bluetooth
  ditolak"), BUKAN crash atau diam saja.
- [ ] Buka ulang, izinkan permission - daftar printer yang sudah
  dipasangkan (paired) muncul dengan nama+MAC address yang benar.
- [ ] Matikan Bluetooth HP, tekan tombol refresh (ikon di AppBar) - app
  menampilkan pesan "Bluetooth mati", bukan crash/daftar kosong tanpa
  penjelasan.
- [ ] Nyalakan Bluetooth lagi, refresh - daftar printer muncul kembali.
- [ ] Pilih printer dari daftar, pilih lebar kertas yang SESUAI fisik
  printer (58 atau 80 mm), tekan **Simpan** - tidak ada error.
- [ ] Tutup app sepenuhnya (bukan cuma minimize) dan buka lagi - buka
  Lainnya > Printer struk lagi: printer yang dipilih & lebar kertas
  **masih tersimpan** (persist lewat restart, bukan di memori saja).

## 2. Cetak tes (dari halaman Pengaturan Printer)

- [ ] Tekan **Cetak tes** - printer benar2 mencetak baris "TES CETAK" +
  lebar kertas yang dipilih.
- [ ] Baris yang dicetak TIDAK terpotong di pinggir kertas (cek lebar 32
  karakter utk 58 mm, 48 utk 80 mm benar2 pas, tidak mepet/kepotong).
- [ ] Teks RATA dan terbaca jelas (bukan karakter acak/mojibake) - kalau
  printer pakai code page selain yang didukung default
  `esc_pos_utils_plus`, catat nama/model printernya di sini utk
  ditindaklanjuti.

## 3. Cetak transaksi sungguhan (alur checkout normal)

- [ ] Nyalakan **"Cetak otomatis setelah bayar"** di Pengaturan Printer.
- [ ] Buka shift, tambah produk ke keranjang, bayar Tunai (jumlah pas,
  lalu ulangi dengan jumlah lebih sbg kembalian) - struk otomatis
  tercetak TANPA kasir menekan tombol apa pun, HP langsung pindah ke
  layar "Pembayaran berhasil" tanpa menunggu proses cetak selesai (cetak
  tidak boleh memblokir UI).
- [ ] Bandingkan struk hasil cetak vs layar "Pembayaran berhasil" di HP:
  nomor struk, item, qty, subtotal, pajak (kalau toko pakai pajak), total,
  dibayar, kembalian **sama persis** antara kertas dan layar.
- [ ] Ulangi dgn produk yang dikenakan **pajak termasuk harga** (kalau
  toko ada) - baris pajak tercetak dengan tanda "(incl)".
- [ ] Ulangi checkout dgn **Kasbon** (DP sebagian) - struk cetak
  menunjukkan "Dibayar", "Sisa tagihan", "Jatuh tempo" (BUKAN
  "Kembali").
- [ ] Matikan "Cetak otomatis setelah bayar", ulangi satu transaksi - TIDAK
  ada percobaan cetak otomatis; tombol **Cetak struk** di halaman struk
  masih bisa dipakai manual dan berhasil.

## 4. Struk ringkas vs lengkap

- [ ] Di `pengaturan_outlet` (lewat endpoint backend `PATCH /outlets/{id}/
  pengaturan`, atau tool API langsung kalau belum ada UI toko-sisi-Flutter
  utk ini) set `struk_ringkas=true` utk outlet yang dipakai uji, lalu
  sync pull di HP. Cetak transaksi dgn promo+pajak aktif - struk cetak
  **cuma** item, TOTAL, metode bayar, kembalian (tanpa rincian
  pajak/promo/modifier/poin/catatan).
- [ ] Set balik `struk_ringkas=false`, sync pull, cetak lagi - rincian
  lengkap kembali muncul.

## 5. Nomor antrean

- [ ] Set `pakai_nomor_antrean=true` di pengaturan outlet (sync pull ke
  HP), lakukan checkout yang mengisi nomor antrean - baris
  "NO. ANTREAN: ..." tercetak HURUF BESAR dan mencolok (lebih tebal/besar
  dari baris lain).

## 6. Logo toko

- [ ] Upload logo toko lewat `POST /toko/logo` (butuh paket dengan fitur
  `logo_struk` aktif) dengan file PNG/JPG < 1 MB.
- [ ] Sync di HP (logo otomatis diunduh+dicache - lihat `LogoCache` di
  kode, tidak ada tombol manual "unduh logo").
- [ ] Set `tampil_logo=true` di pengaturan outlet, sync lagi, cetak
  transaksi - logo tercetak di PALING ATAS struk, **lebarnya pas** kertas
  (tidak kepotong kiri/kanan, tidak terlalu kecil di tengah kertas
  kosong).
- [ ] **Offline**: matikan data seluler + Bluetooth data (WiFi off,
  data off - bukan Bluetooth printer), buat transaksi baru, cetak -
  logo **tetap tercetak** dari cache lokal walau device benar2 offline
  sejak unduhan terakhir.
- [ ] Hapus app data / reinstall app (hapus cache lokal), JANGAN sync
  dulu, coba cetak - logo TIDAK tercetak (cache kosong) tapi struk tetap
  cetak lengkap TANPA logo, tidak error/crash.

## 7. Printer mati/putus di tengah proses (aturan #D.3 - WAJIB)

- [ ] Matikan printer SEBELUM menekan bayar (atau sebelum tekan "Cetak
  struk" manual) - transaksi tetap tersimpan (cek halaman Riwayat,
  transaksi ada), hanya muncul pesan gagal cetak + transaksi lanjut ke
  struk seperti biasa, BUKAN macet/crash/transaksi hilang.
- [ ] Nyalakan printer lagi, buka transaksi itu di Riwayat > detail,
  tekan **Cetak ulang** - berhasil cetak, struk bertanda **"** SALINAN
  **"**.
- [ ] Ulangi tapi kali ini printer dimatikan **DI TENGAH proses cetak**
  (nyalakan dulu supaya sambung, lalu matikan tepat setelah menekan
  tombol cetak) - pastikan app tidak hang menunggu respons printer
  selamanya (ada batas waktu yang masuk akal), transaksi tetap aman.
- [ ] Matikan Bluetooth HP (bukan printernya) di tengah mencoba cetak -
  sama, transaksi tetap aman, pesan error jelas.

## 8. Cetak ulang dari Riwayat

- [ ] Riwayat > pilih transaksi LAMA (bukan yang baru dibuat sesi ini,
  idealnya dari hari sebelumnya/sebelum app di-restart) > tekan
  **Cetak ulang** - berhasil, bertanda "** SALINAN **".
- [ ] Cetak ulang transaksi yang **sudah di-void** - tombol tetap
  tersedia (beda dari Void/Refund yang hilang setelah void) dan berhasil
  cetak.
- [ ] Catat known gap: struk cetak-ulang dari Riwayat TIDAK menampilkan
  rincian pajak per-baris, nama kasir, nomor antrean, tipe order/meja,
  poin, atau catatan transaksi (`DetailTransaksi` belum menyimpan field
  itu) - kalau ini ternyata dibutuhkan toko, perlu pekerjaan tambahan di
  `lib/features/transaksi/domain/detail_transaksi.dart` dulu, BUKAN bug
  printer.

## 9. Kirim WhatsApp

- [ ] Dari halaman struk, tekan **Kirim WhatsApp** - karena transaksi
  saat ini tidak membawa nomor HP pelanggan (lihat known gap di README),
  yang muncul adalah **share sheet biasa** (Android share sheet), bukan
  langsung ke WhatsApp. Pilih WhatsApp dari share sheet - teks struk utuh
  masuk ke chat WhatsApp pilihan, format rata & terbaca (bukan satu
  baris panjang).
- [ ] Pastikan TIDAK ada emoji/karakter aneh di teks yang dibagikan (test
  ini hanya relevan kalau toko sempat isi header/footer/nama custom dgn
  emoji - lihat bagian "karakter non-ASCII" di `penyusun_struk_test.dart`
  utk kasus yang sudah ditest otomatis).

## 10. Rekap tutup shift

- [ ] Tutup shift dengan beberapa transaksi tunai + (kalau ada) QRIS
  statis di dalamnya - cetak rekap (lewat jalur yang disediakan UI tutup
  shift, kalau sudah disambungkan) menampilkan modal awal, penjualan per
  metode, kas seharusnya, kas aktual, selisih - semua angka SAMA dengan
  yang ditampilkan di layar Tutup Shift.

## 11. Bluetooth Classic vs BLE / printer model berbeda

`print_bluetooth_thermal` mengandalkan Bluetooth Classic (SPP), BUKAN
BLE - catat di sini kalau menguji printer yang ternyata cuma BLE (tidak
akan muncul di daftar "Perangkat terpasangkan" sama sekali, bukan bug
app). Catat juga merk/model setiap printer yang sudah diuji sukses di
sini supaya tim lain tidak mengulang dari nol:

| Merk/model | Lebar | Hasil | Catatan |
|---|---|---|---|
| _(isi setelah uji)_ | | | |
