# Gap Fitur: Aplikasi vs Daftar IMOGI (acuan utama)

Tanggal: 2026-11-08. Menggantikan `docs/gap_fnb.md` sebagai acuan utama. Daftar Qasir Pro tidak dipakai lagi.

**Sumber acuan (moment of truth):**
- `IMOGI POS Menu & Fitur.html` (diperbarui 5 Nov 2026): 4 paket, 11 modul, 87 fitur, 43 jenis usaha, dan kebutuhan fitur (inti/opsional/tidak relevan) per jenis usaha.
- `Panduan-Menu-Pengaturan-IMOGI-POS.pdf` (versi November 2026, 41 halaman): isi menu Pengaturan, nilai bawaan per jenis usaha, dan paket minimum tiap bagian.

**Metode dan batas.** Status aplikasi berasal dari pembacaan kode dan data uji manual 2026-11-08, bukan uji menyeluruh di HP. Beberapa baris ditandai "belum diperiksa" pada kolom temuan. Fokus aplikasi: modul **Makanan & Minuman** (7 jenis usaha, lihat bagian 3).

---

## 1. Ringkasan

| | Jumlah |
|---|---|
| Fitur di daftar IMOGI | 87 |
| Relevan untuk Makanan & Minuman (inti atau opsional untuk minimal 1 dari 7 jenis usaha) | 64 |
| Tidak relevan untuk Makanan & Minuman (disembunyikan) | 23 |
| ✅ Lengkap | 15 (tidak berubah: belum ada fitur yang diuji di HP, jadi tidak ada yang dinaikkan) |
| 🟡 Sebagian | 42 (awal audit 24; +18 sejak 2026-11-12/17) |

| ❌ Belum ada | 7 (awal audit 25) |

| Fitur inti untuk Kafe & Kedai Kopi | 46 (✅ 11, 🟡 26, ❌ 9); awal audit ✅ 11, 🟡 18, ❌ 17 |

**Temuan utama:**
1. **Katalog paket sudah diselaraskan (fondasi selesai, migrasi 0010).** Backend kini memakai 4 paket IMOGI (Free, Starter, Professional, Enterprise) dan 87 fitur; sebelumnya 3 paket dan 32 fitur hasil salinan Qasir. Harga dan kuota paket masih **harga contoh** karena dokumen IMOGI tidak memuatnya. Fitur baru belum menggerbang apa pun sampai diimplementasikan.
2. **Sebelumnya hampir separuh fitur relevan F&B belum ada** (kini 17 dari 64 setelah 8 fitur mendapat versi awal pada 2026-11-12/13). Yang masih belum ada: jurnal, buku besar, neraca, anggaran, payroll, ekspor ke software akuntansi, dan sebagian keuangan lain.
3. **Alur pesanan kafe sudah terbangun sebagian (2026-11-08):** varian dan tambahan produk (ukuran, level gula, topping), tiket dapur, status pesanan, dan nomor antrian sudah ada di kode dan lulus tes otomatis, tetapi **belum diuji di HP dan printer**. Yang tersisa: estimasi selesai, pesan WhatsApp saat siap, tahap Diantar, pengaturan awalan nomor antrian.
4. **Menu Pengaturan versi IMOGI belum ada.** IMOGI punya 11 tab pengaturan dengan bawaan otomatis per jenis usaha, simpan otomatis, dan tombol "Kembalikan ke rekomendasi". Aplikasi hanya punya pengaturan terpisah-pisah (lihat bagian 6).
5. **Beberapa gap dari analisis lama tidak ada di daftar IMOGI**: pilih meja saat transaksi, catatan per item, pisah/gabung bill, layar dapur (KDS), menu habis (sold out), dan tip. Kata "meja" tidak muncul di kedua dokumen. Perlu konfirmasi lead apakah tetap dikerjakan.
6. **Mode bisnis sudah diganti (fondasi selesai)** dari pilihan umum (retail, fnb, jasa, laundry, fashion) menjadi 7 jenis usaha Makanan & Minuman dengan kode IMOGI. Bawaan pengaturan per jenis usaha belum dibuat.

---

## 2. Paket IMOGI

| Paket IMOGI | Fitur relevan F&B yang pertama terbuka di paket ini |
|---|---|
| Free | 11 |
| Starter | 15 |
| Professional | 16 |
| Enterprise | 22 |

Paket lebih tinggi mencakup semua fitur paket di bawahnya. Multi-Outlet adalah add-on berbayar di paket Professional ke atas (di katalog backend dihitung sebagai bagian Professional, jadi Professional berisi 64 fitur; dokumen IMOGI menyebut 63 tanpa add-on). Akun demo mendapat semua fitur. Cara upgrade menurut panduan: pilih paket, tekan "Ajukan upgrade", tim IMOGI menghubungi untuk pembayaran, paket aktif setelah dibayar.

---

## 3. Jenis usaha Makanan & Minuman (mode bisnis)

Tujuh jenis usaha di kelompok ini: **Kafe & Kedai Kopi, Restoran, Katering, Roti/Kue & Camilan, Bahan Segar & Makanan Beku, Minuman, Kios & Food Court.**

**Status fondasi:** pilihan saat daftar toko, penyimpanan di backend (`toko.jenis_usaha`), dan validasi sudah memakai 7 kode IMOGI (CAF, RES, CAT, BRD, FRZ, BEV, STL). Nilai lama `fnb` dipetakan ke Kafe & Kedai Kopi. Tabel `fitur_kebutuhan` di database menyimpan kebutuhan fitur (inti/opsional/na) per jenis usaha. Yang belum: nilai bawaan dan visibilitas pengaturan per jenis usaha. Menurut panduan IMOGI, jenis usaha menentukan:
- nilai bawaan pengaturan (pajak, biaya layanan, struk, antrian, tiket dapur, stok, dll.),
- bagian pengaturan yang tampil (utama, opsional, atau disembunyikan),
- nama tab (mis. "Stok & Resep" untuk makanan dan minuman),
- peran bawaan kru (mis. "Barista & Dapur").

---

## 4. Gap fitur relevan F&B

Diurutkan: inti untuk Kafe & Kedai Kopi lebih dulu. ❌ = belum ada, 🟡 = sebagian.

| No | Modul | Fitur IMOGI | Paket IMOGI | Kebutuhan F&B (7 jenis) | Status | Temuan |
|---|---|---|---|---|---|---|
| 3 | Kasir | Kelola diskon | Free | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-15): diskon manual per item di keranjang (tombol Diskon: 5/10/15/20%, persen atau nominal sendiri, hapus diskon). Butuh izin transaksi.diskon atau PIN approver; penyetuju tersimpan di transaksi dan dikirim ke server (UUID saja). Total, struk, dan item ikut berubah. Belum: batas diskon kasir tanpa PIN, tombol cepat yang bisa diatur, diskon level transaksi (nominal), dan diskon manual belum ikut saat pesanan tersimpan dibuka kembali. Lulus tes otomatis, belum diuji di HP. |
| 10 | Pembayaran | Pembayaran QRIS | Starter | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-16): layar bayar QRIS menampilkan gambar QRIS statis milik usaha (sebelumnya QR tiruan yang tidak bisa dibayar). Pemilik mengunggah gambar (PNG/JPG maks. 1 MB) di Pengaturan metode bayar pada metode QRIS (digerbang fitur qris, migrasi 0027, ikut sync dan di-cache untuk offline), bisa diganti atau dihapus; tanpa gambar layar memberi petunjuk. Kasir tetap wajib mengecek dana masuk manual. QRIS dinamis Xendit tetap terblokir (kunci kosong). Lulus tes otomatis, belum diuji di HP. |
| 36 | Produk | Kelola produk, kategori & harga | Free | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-14): CRUD produk, kategori, dan harga ada; kini kasir punya tab kategori (Semua + kategori yang berisi produk, urut menurut pengaturan kategori) yang digabung dengan pencarian. Belum: urutan tab khusus kasir terpisah dari urutan kategori. Lulus tes otomatis, belum diuji di HP. |
| 37 | Produk | Harga beli & margin produk | Free | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-13): penanda margin rendah di form dan daftar produk (lencana, filter "Margin rendah", peringatan di form) dengan batas per outlet di Pengaturan struk (bawaan 50% untuk F&B, migrasi 0016); HPP kosong ditandai tersendiri. Hak akses lihat harga beli mengikuti izin produk.kelola (belum ada izin khusus). Lulus tes otomatis, belum diuji di HP. |
| 38 | Produk | Upload produk via template | Starter | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-12): Lainnya > Impor & ekspor produk: template CSV, pratinjau, simulasi dan impor (maks 500 baris) lewat `POST /produk/impor`. Belum: .xlsx, memperbarui produk lama, varian, stok awal, gambar. Plugin `file_picker` baru, belum diuji di HP. |
| 65 | Laporan | Tren penjualan | Starter | 7 inti, 0 opsional, Kafe: Inti | 🟡 | Tanpa grafik tren. |
| 67 | Akuntansi | Catat pengeluaran & biaya operasional | Starter | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-12): menu Lainnya > Pengeluaran (Owner/Manajer), 9 kategori F&B, rentang hari/7 hari/bulan, total dan rincian per kategori, catat dan hapus; server `/pengeluaran` (migrasi 0015, digerbang fitur `expenses`). Belum: offline (butuh internet), edit, foto nota, berulang. Lulus tes otomatis, belum diuji di HP. |
| 69 | Akuntansi | Laporan laba rugi | Professional | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-12): Lainnya > Laba rugi: penjualan kotor, diskon, HPP, laba kotor, biaya operasional, laba bersih; server `/laporan/laba-rugi`. Rumus adalah keputusan sementara (belanja bahan tidak dikurangkan lagi, refund belum dihitung); perlu validasi akuntan. Butuh internet, belum diuji di HP. |
| 70 | Akuntansi | Rekap pajak PPh Final UMKM (0,5%) | Professional | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-12): tab PPh Final di Lainnya > Rekap pajak: estimasi tarif 0,5% x peredaran bruto per bulan; server `/laporan/pph-final`. Ambang bebas pajak dan status wajib pajak belum dihitung, hanya estimasi. Belum diuji di HP. |
| 72 | Akuntansi | HPP & margin per produk/layanan | Professional | 7 inti, 0 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-14): kartu HPP & margin per produk di tab Laporan (qty, HPP, laba, margin %, penanda di bawah batas margin outlet, HPP kosong ditandai), dihitung offline dari data lokal, terkunci paket Professional. DIPERBAIKI: HPP sebelumnya tidak pernah disimpan saat checkout (selalu 0); kini disimpan sebagai snapshot HPP produk saat transaksi. Transaksi lama tetap HPP 0. Belum: ekspor dan laporan per kategori. Belum diuji di HP. |
| 61 | Karyawan | Kelola karyawan | Starter | 6 inti, 1 opsional, Kafe: Inti | 🟡 | CRUD pengguna dan peran ada. Daftar hak akses Imogi (jualan, bon/DP, status pesanan, lihat margin, pengeluaran, dst.) dan peran bawaan Barista & Dapur belum dicocokkan. |
| 74 | Akuntansi | Settlement & rekonsiliasi QRIS/e-wallet | Professional | 6 inti, 1 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-17): Lainnya > Settlement QRIS & e-wallet (digerbang `settlement`, izin `laporan.lihat`): catat dana masuk per tanggal penjualan dan metode (jumlah bersih + biaya), rekonsiliasi dengan penjualan non-tunai POS (cocok/selisih/belum dicatat). Server: `/settlement` (catat, daftar, hapus, `/rekonsiliasi`), tabel `settlement` (migrasi 0030). Butuh internet. Belum: impor otomatis dari penyedia, jurnal, belum diuji di HP. |
| 13 | Pembayaran | Pembayaran kartu debit/kredit (EDC) | Free | 5 inti, 2 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-15): metode kartu/transfer/e-wallet punya pengaturan Wajib no. referensi (migrasi 0023); layar bayar menolak bila no. referensi kosong dan, khusus kartu, 4 digit akhir tidak tepat 4 angka. No. referensi tersimpan per pembayaran dan ikut sync. Belum: jenis kartu (debit/kredit) dan daftar mesin EDC. Lulus tes otomatis, belum diuji di HP. |
| 15 | Pembayaran | Split payment (bayar campur) | Starter | 4 inti, 3 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-14): tombol bayar campur kini digerbang fitur split_payment di layar kasir (tes ikut diperbarui). Belum diuji di HP. |
| 35 | Dapur | Cetak tiket pesanan dapur | Enterprise | 4 inti, 2 opsional, Kafe: Inti | 🟡 | SELESAI sebagian (2026-11-08): tiket dapur tanpa harga (nomor antrian, waktu, menu dan jumlah) dicetak otomatis setelah pembayaran dan bisa dicetak ulang dari halaman sukses; lulus tes susunan tiket. KEMAJUAN 2026-11-10: kategori bisa dikeluarkan dari tiket (saklar "Masuk tiket dapur" di form kategori, migrasi 0013) dan tiket bisa dicetak ulang dari detail riwayat. KEMAJUAN 2026-11-16: stasiun dapur (Bar, Dapur) bisa dibuat di menu Lainnya, tiap kategori ditautkan ke satu stasiun di form kategori (digerbang paket), dan satu pesanan mencetak satu tiket per stasiun (judul "TIKET BAR"); kategori tanpa stasiun tetap di tiket umum. Belum: printer terpisah per stasiun (kini semua lewat satu printer berurutan), tombol auto-print terpisah, dan uji di printer (belum ada perangkat). |
| 42 | Produk | Varian & tambahan produk (ukuran, level, topping) | Starter | 4 inti, 2 opsional, Kafe: Inti | 🟡 | SELESAI sebagian (2026-11-08): halaman Varian & tambahan (menu Lainnya) untuk membuat grup (ukuran, level gula, topping) beserta opsi berharga dan aturan wajib/maksimal pilih, memasangnya ke banyak produk; katalog turun ke HP lewat sync. Kasir membuka pemilih saat produk punya tambahan (juga lewat scan), harga ikut dihitung, baris keranjang terpisah per pilihan, tersimpan di pesanan tersimpan dan riwayat, tampil di struk dan tiket dapur, terkirim saat sync. Lulus 22 tes Flutter dan tes backend. Belum diuji di HP. Belum ada: urutan opsi yang bisa digeser, tambahan khusus per produk (hanya grup bersama), izin kelola terpisah di sisi aplikasi. |
| 18 | Pembayaran | Label jenis pembayaran | Enterprise | 3 inti, 4 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-15): metode bayar non-tunai punya daftar label tujuan (mis. GoPay, OVO, ShopeePay, BCA) yang diatur di Pengaturan metode bayar (digerbang fitur label_pembayaran, migrasi 0025); kasir wajib memilih satu label saat menerima kartu/transfer/e-wallet, tersimpan di pembayaran, dan laporan (HP dan server) memisahkan baris per label untuk rekonsiliasi. Ubah nama/urutan metode bayar sudah ada sebelumnya. Belum: label pada QRIS statis dan bayar campur, serta rekonsiliasi terhadap mutasi/settlement (IMOGI no. 74). Lulus tes otomatis, belum diuji di HP. |
| 26 | Dapur | Status pesanan | Enterprise | 3 inti, 3 opsional, Kafe: Inti | 🟡 | SELESAI sebagian (2026-11-08): status awal Baru dibuat saat checkout, halaman Status Pesanan (menu Lainnya) memajukan tahap Baru, Diproses, Siap, Selesai (katering: Dipesan, Dimasak, Siap kirim, Dikirim, Selesai), tersimpan offline dan dikirim lewat sync (migrasi 0011). KEMAJUAN 2026-11-10: pesanan bertipe antar otomatis memuat tahap Diantar. Belum ada estimasi selesai, pesan WhatsApp saat siap, dan uji di HP. |
| 34 | Dapur | Nomor antrian | Enterprise | 3 inti, 1 opsional, Kafe: Inti | 🟡 | SELESAI sebagian (2026-11-08): HP membuat nomor A-001 sendiri saat offline (per hari, outlet, perangkat), tersimpan di transaksi, tampil di struk dan halaman sukses, dikirim lewat sync. KEMAJUAN 2026-11-10: awalan dan angka awal bisa diatur per outlet di Pengaturan struk (migrasi 0012). Belum ada panggilan suara, layar antrian, dan nama di layar antrian. Belum diuji di HP. |
| 62 | Karyawan | Absensi karyawan | Professional | 3 inti, 4 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-12): Lainnya > Absensi: absen masuk/keluar, rekap jam kerja, endpoint `/absensi` (waktu server, batas hari mengikuti zona perangkat). Belum: foto, lokasi, jadwal, terlambat, koreksi, offline. Belum diuji di HP. |
| 63 | Karyawan | Jadwal shift mingguan & cuti | Professional | 3 inti, 4 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-14): Lainnya > Jadwal & cuti: pengelola mengatur shift mingguan tiap karyawan (libur/pagi/siang), karyawan melihat jadwal dan mengajukan cuti/sakit/izin, pengelola menyetujui atau menolak (tidak bisa memutuskan milik sendiri); absen masuk menjadi Terlambat bila lewat jam mulai + 10 menit (migrasi 0018, /jadwal dan /cuti, fitur staff_schedule). Belum: tukar jadwal, jam shift kustom di layar, shift lintas tengah malam, pemberitahuan. Belum diuji di HP. |

| 76 | Akuntansi | Penggajian (payroll) & kasbon karyawan | Enterprise | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada penggajian dan kasbon karyawan. |
| 80 | Akuntansi | Chart of Accounts & jurnal umum | Enterprise | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada chart of accounts dan jurnal umum. |
| 81 | Akuntansi | Buku besar, neraca & arus kas | Enterprise | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada buku besar, neraca, dan arus kas. |
| 82 | Akuntansi | Anggaran & proyeksi arus kas | Enterprise | 3 inti, 3 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-17): Lainnya > Anggaran & proyeksi (digerbang `budget`, izin `laporan.lihat`): anggaran biaya per kategori per bulan, realisasi dari pengeluaran, status (aman/waspada >=80%/lewat), proyeksi akhir bulan linear untuk biaya dan penjualan, selisih kasar. Server: `/anggaran` (migrasi 0032). Butuh internet. Belum: arus kas akuntansi, anggaran per outlet, salin antarbulan, belum diuji di HP. |
| 85 | Akuntansi | Ekspor ke software akuntansi (Jurnal, Accurate, Zahir) | Enterprise | 3 inti, 4 opsional, Kafe: Inti | ❌ | Tidak ada ekspor ke software akuntansi. |
| 4 | Kasir | Pajak per produk | Starter | 2 inti, 5 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-15): daftar Pajak dan Service kini punya saklar Usaha kena pajak (mematikan/menyalakan semua pajak sekaligus, service charge tidak ikut) dan menampilkan pajak nonaktif; form tambah punya pilihan cepat PB1 10%, PPN 11%, dan Service 5% (nilai bisa diubah). Cara hitung termasuk/ditambahkan dan pajak per produk sudah ada sebelumnya. Belum: nilai bawaan per jenis usaha (menunggu Batch B). Lulus tes otomatis, belum diuji di HP. |
| 6 | Kasir | Biaya layanan per tipe pesanan | Enterprise | 2 inti, 3 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-15): toko Kafe dan Restoran yang baru mendaftar otomatis mendapat Service Charge 5% yang hanya ditautkan ke tipe Makan di tempat (jenis usaha lain mendapat tipe pesanan tanpa service). Tipe pesanan kini dibuat di server dan ikut sync pull; HP menggantikan bawaan lokalnya dengan data server pada pull pertama. Aturan service per tipe pesanan di kalkulator sudah ada sebelumnya. Belum: usaha yang sudah terdaftar tidak otomatis dapat bawaan, pengaturan bawaan lain per jenis usaha (Batch B). Lulus tes otomatis, belum diuji di HP. |
| 24 | Struk | Logo usaha di struk | Enterprise | 2 inti, 5 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-15): Pengaturan struk punya pilihan Gaya logo: logo unggahan, atau logo otomatis dari inisial nama usaha (lingkaran, cincin, inisial), dengan pratinjau; struk cetak memakai gaya terpilih; tanpa logo = saklar Tampilkan logo dimatikan. Gaya otomatis digerbang fitur logo_struk di server (migrasi 0026) dan ikut sync. BUG-012 (simpan pengaturan paket Gratis) sudah diperbaiki sebelumnya. Belum: logo otomatis tidak tampil di pratinjau struk teks dan belum ada pilihan warna atau font. Lulus tes otomatis (termasuk render gambar), belum diuji di printer dan HP. |
| 59 | Pelanggan | Survei pelanggan | Professional | 2 inti, 5 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-17): Lainnya > Survei pelanggan (digerbang `survei`, izin `pelanggan.kelola`): buat survei (rating 1-5, pilihan, teks), isi jawaban pelanggan, lihat hasil (rata-rata, sebaran, komentar). Server: `/survei` (CRUD, `/jawaban`, `/hasil`). Butuh internet. Belum: tampil di struk/layar pelanggan/WhatsApp, tautan otomatis ke transaksi, belum diuji di HP. |
| 73 | Akuntansi | Rekap pajak PPN & PB1 | Professional | 2 inti, 5 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-12): tab PPN/PB1 di Lainnya > Rekap pajak: pajak dan service dipungut per nama dan tarif; server `/laporan/rekap-pajak`. Belum: ekspor, PPN masukan/keluaran, pelaporan SPT. Belum diuji di HP. |
| 83 | Akuntansi | Aset tetap & penyusutan | Enterprise | 2 inti, 4 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-17): Lainnya > Aset tetap & penyusutan (digerbang `fixed_assets`, izin `laporan.lihat`): catat aset (harga, residu, umur bulan), penyusutan garis lurus per bulan (mulai bulan perolehan) dihitung server, akumulasi dan nilai buku. Server: `/aset-tetap` (migrasi 0031). Butuh internet. Belum: jurnal, saldo menurun, pelepasan aset, ubah angka aset, belum diuji di HP. |
| 84 | Akuntansi | Laporan keuangan konsolidasi multi-outlet | Enterprise | 2 inti, 5 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-17): Lainnya > Laba rugi konsolidasi (Owner/Manajer, digerbang fitur consolidation): laba rugi tiap outlet aktif dan total toko dalam satu layar, rentang hari/7 hari/bulan; server GET /laporan/laba-rugi-konsolidasi memakai rumus laba rugi no. 69 yang sama (keputusan sementara, perlu validasi akuntan). Total memuat biaya tanpa outlet. Belum: neraca, arus kas, ekspor, eliminasi transaksi antar outlet, mata uang. Butuh internet, lulus tes otomatis, belum diuji di HP. |
| 87 | Outlet | Multi-Outlet | Professional | 2 inti, 5 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-17): Lainnya > Ganti outlet (digerbang fitur multi_outlet) menampilkan outlet yang boleh dipakai pengguna (Owner/Manajer semua, peran lain sesuai akses outlet; server GET /outlets/saya) dan memindahkan outlet aktif di HP; data outlet tujuan ditarik ulang lewat sync. Pindah ditolak bila shift masih terbuka. Belum: tampilan nama outlet aktif di header, uji di HP dengan 2 outlet. |
| 56 | Pelanggan | Promo ulang tahun pelanggan | Professional | 1 inti, 5 opsional, Kafe: Inti | 🟡 | SEBAGIAN (2026-11-13): promo bisa ditandai Khusus ulang tahun (gerbang paket birthday_promo, migrasi 0017); tanggal lahir pelanggan bisa diisi di form, ikut impor CSV, dan kini ikut sync ke HP; di keranjang promo itu hanya bisa dipilih bila pelanggan berulang tahun hari ini dan dicabut bila pelanggan diganti; daftar pelanggan menandai yang berulang tahun hari ini. Penerapan otomatis sudah ada (2026-11-17): memilih pelanggan yang berulang tahun hari ini di keranjang otomatis memasang promo ulang tahun bila kasir belum memilih promo (bisa diganti atau dilepas). Belum: pemberitahuan ke pelanggan, validasi server saat checkout. Belum diuji di HP. |
| 71 | Akuntansi | Piutang & hutang usaha (AR/AP) | Professional | 5 inti, 2 opsional, Kafe: Opsional | 🟡 | Piutang pelanggan (kasbon) ada. Hutang usaha ke supplier belum dicocokkan (backend punya modul pembelian). |
| 16 | Pembayaran | Pembayaran hutang (bon) | Starter | 3 inti, 4 opsional, Kafe: Opsional | 🟡 | Kasbon, jatuh tempo, dan pelunasan ada. SEBAGIAN (2026-11-14): limit bon kini juga dicek di HP sebelum bon disimpan (batas_kasbon dikurangi utang berjalan; ditolak dengan sisa kuota), selain di server (lihat batas_kasbon.dart, 4 tes). Belum diuji di HP. |
| 49 | Stok | Kelola stok produk | Free | 3 inti, 4 opsional, Kafe: Opsional | 🟡 | SEBAGIAN (2026-11-14): kini ada riwayat mutasi lengkap per produk (ketuk baris stok): jenis, tanggal dan jam, jumlah, saldo setelah, catatan, total masuk/keluar, filter Masuk/Keluar, sampai 300 mutasi terbaru. Filter rentang tanggal sudah ada (2026-11-16, chip "Semua tanggal", totalnya ikut rentang). Belum: ekspor riwayat, riwayat per varian. Pengaturan saat stok habis sempat terblokir BUG-012 (diperbaiki di kode, menunggu uji HP). Lulus tes otomatis, belum diuji di HP. |
| 50 | Stok | Pengingat kedaluwarsa produk | Enterprise | 2 inti, 5 opsional, Kafe: Opsional | 🟡 | SEBAGIAN (2026-11-16): catat batch (produk, nomor batch, jumlah, tanggal kedaluwarsa, ingatkan N hari) lewat menu ikon di halaman Stok, digerbang fitur pengingat_kedaluwarsa dan izin stok.kelola; daftar menandai Sudah lewat / Segera dan ikut sync ke HP (bisa dilihat offline). Pencatatan dan penghapusan butuh koneksi. Belum: pemberitahuan terjadwal, batch dikurangi otomatis saat penjualan (FIFO), batch dari pembelian. Lulus tes otomatis, belum diuji di HP. |
| 14 | Pembayaran | Pembayaran transfer bank | Free | 1 inti, 6 opsional, Kafe: Opsional | 🟡 | Metode transfer ada. SEBAGIAN (2026-11-14): Pengaturan metode bayar kini punya rekening tujuan (bank, nomor, atas nama) untuk metode transfer/e-wallet; ikut sync ke HP (migrasi 0019, schema lokal 15) dan tampil di layar bayar saat metode dipilih. Belum diuji di HP. |
| 39 | Produk | Ekspor produk | Starter | 1 inti, 6 opsional, Kafe: Opsional | 🟡 | SEBAGIAN (2026-11-12): ekspor seluruh produk HP ke CSV lewat menu bagikan (Lainnya > Impor & ekspor produk). Belum diuji di HP. |
| 43 | Produk | Jual per kemasan (pcs, dus, pak) | Starter | 1 inti, 1 opsional | 🟡 | SEBAGIAN (2026-11-17): produk bisa punya kemasan jual (nama, isi, harga) di form produk (digerbang pack_units, perlu internet untuk mengubah); kasir memilih satuan dasar atau kemasan, baris kemasan terpisah dengan harga kemasan; stok tetap di satuan dasar dan berkurang qty x isi (checkout, void, refund); HPP per kemasan; ikut sync (migrasi 0029, schema lokal 22). Belum: harga grosir/harga outlet per kemasan, laporan stok per kemasan, kemasan per varian, checkout online server (menolak kemasan). Lulus tes otomatis, belum diuji di HP. |
| 79 | Akuntansi | Pendapatan diterima di muka (deposit/membership) | Enterprise | 1 inti, 3 opsional, Kafe: Opsional | ❌ | Tidak ada pendapatan diterima di muka. |
| 25 | Struk | Catatan tambahan di struk | Enterprise | 0 inti, 7 opsional, Kafe: Opsional | 🟡 | Catatan pesanan tercetak. Footer struk toko sudah ada dan kini dibatasi maks. 300 karakter di Pengaturan struk. Belum diuji di HP. |
| 27 | Dapur | Terima order, bayar belakangan (nota order) | Free | 0 inti, 3 opsional, Kafe: Opsional | 🟡 | SEBAGIAN (2026-11-15): tombol Terima Order (bayar nanti) di keranjang mencatat pesanan sebagai transaksi belum dibayar tanpa pelanggan (nomor antrean, status pesanan, tiket dapur ikut berjalan; bukan kasbon, paket Gratis boleh); layar Order belum dibayar (Lainnya) mencatat pelunasan penuh atau sebagian per metode bayar; server menerima lewat bayar_belakangan (migrasi 0024). Belum: pilihan jatuh tempo/kapan membayar, cetak nota order khusus, penukaran poin dan metode QRIS saat pelunasan. Lulus tes otomatis, belum diuji di HP. |
| 53 | Pelanggan | Upload pelanggan via template | Professional | 0 inti, 6 opsional, Kafe: Opsional | 🟡 | SEBAGIAN (2026-11-13): Lainnya > Impor pelanggan: template CSV, pratinjau, simulasi dan impor lewat `POST /pelanggan/impor`; nomor HP dinormalkan. Belum: memperbarui pelanggan lama, poin/level. Belum diuji di HP. |
| 57 | Pelanggan | Kirim WA ke banyak pelanggan | Professional | 0 inti, 5 opsional, Kafe: Opsional | 🟡 | SEBAGIAN (2026-11-17): Lainnya > Kirim WA ke pelanggan (digerbang customer_broadcast): tulis satu pesan dengan {nama} dan {toko}, pilih penerima (hanya yang punya nomor WhatsApp sah, saring level dan cari), lalu pesan dibuka di WhatsApp satu per satu dan dikirim kasir sendiri. Belum: kirim otomatis lewat gateway WhatsApp Business, riwayat kiriman, penjadwalan, opt-out pelanggan. Lulus tes otomatis, belum diuji di HP. |
| 77 | Akuntansi | BPJS & PPh 21 di penggajian | Enterprise | 0 inti, 7 opsional, Kafe: Opsional | ❌ | Tidak ada BPJS dan PPh 21. |
| 78 | Akuntansi | Tutup buku akhir tahun | Enterprise | 0 inti, 7 opsional, Kafe: Opsional | ❌ | Tidak ada tutup buku akhir tahun. |

---

## 5. Fitur yang sudah lengkap (relevan F&B)

| No | Fitur IMOGI | Paket IMOGI | Kode fitur di aplikasi | Catatan |
|---|---|---|---|---|
| 1 | Kasir (POS) | Free | `pos` | Kasir, keranjang, bayar, riwayat. Printer belum teruji. |
| 2 | Scan barcode produk | Starter | `scan_barcode` | Scan kamera (mobile_scanner). |
| 5 | Tipe pesanan (dine-in/takeaway/delivery) | Starter | `tipe_order` | Tipe pesanan dan meja (pengaturan) ada. |
| 7 | Simpan pesanan (hold / open bill) | Free | `hold` | Simpan pesanan (open bill) ada. Belum terhubung ke meja. |
| 17 | DP untuk hutang | Enterprise | `dp_kasbon` | DP untuk kasbon ada (DP minimal persen belum diperiksa). |
| 22 | Cetak struk | Free | `cetak_struk` | Cetak ESC/POS Bluetooth. Belum teruji (tidak ada printer). Pengaturan cetak otomatis setelah bayar belum ditemukan. |
| 23 | Struk ringkas | Enterprise | `struk_ringkas` | Struk ringkas ada. |
| 40 | Kelola paket (bundle) | Enterprise | `bundling` | Bundling produk ada. |
| 41 | Kelola harga grosir | Enterprise | `harga_grosir` | Harga grosir ada. |
| 51 | Bahan baku & resep produk | Professional | `resep` | Resep per produk; stok bahan terpotong saat jual. Perilaku offline belum diverifikasi. |
| 52 | Kelola pelanggan | Starter | `kelola_pelanggan` | CRUD pelanggan dan piutang. |
| 54 | Poin loyalti pelanggan | Professional | `poin_loyalitas` | Poin dan aturan poin ada. Poin hangus per bulan belum diperiksa. |
| 55 | Diskon member | Professional | `diskon_member` | Level member dan diskon member ada. |
| 64 | Laporan Penjualan (sesuai periode langganan) | Free | `laporan_dasar` | Laporan penjualan dengan batas hari per paket. |
| 68 | Buka/tutup shift & rekonsiliasi kas | Starter | `cash_shift` | Buka/tutup shift dan kas ada. Modal awal disarankan (Rp 300.000 untuk F&B) belum diperiksa. |

---

## 6. Gap menu Pengaturan (dari panduan PDF)

Panduan menggambarkan menu Pengaturan dengan 11 tab. Yang belum ada di aplikasi:

| Aspek | Menurut panduan IMOGI | Di aplikasi sekarang |
|---|---|---|
| Struktur | Tab: Kasir, Pembayaran, Struk, Pesanan, Katalog, Stok, Pelanggan, Karyawan, Keuangan, Pribadi, Paket langganan | Pengaturan tersebar di beberapa halaman (menu Lainnya) |
| Simpan | Tersimpan otomatis, tanpa tombol Simpan | Ada tombol Simpan |
| Cakupan | Per cabang (outlet) | Sebagian per outlet |
| Bawaan | Nilai awal otomatis menurut jenis usaha | Tidak ada |
| Reset | Tautan "Kembalikan ke rekomendasi" di tiap tab | Tidak ada |
| Visibilitas | Bagian utama terkunci dengan tombol Upgrade; opsional disembunyikan; tidak relevan tidak tampil | Ada lembar "fitur terkunci"; belum ada aturan inti/opsional per jenis usaha |
| Nama tab | Mengikuti jenis usaha (mis. "Stok & Resep") | Tetap |
| Hak akses | 18 hak akses per peran; peran bawaan Manajer, Kasir, kru (mis. Barista & Dapur), Gudang | Peran dan izin ada; daftar hak belum dicocokkan |
| PIN | PIN owner untuk persetujuan; batas PIN salah 3/5/10x lalu dikunci bertahap | Hitung percobaan gagal dan kunci sementara ada; kunci layar otomatis belum ada |
| Bahasa | Indonesia atau English, struk mengikuti | Belum ada pilihan bahasa |
| Upgrade paket | "Ajukan upgrade", tim IMOGI menghubungi, bayar manual | Ada permintaan upgrade dan checkout Xendit di aplikasi |

**Bawaan untuk jenis usaha F&B menurut panduan** (bahan untuk fitur bawaan nanti):
- Pajak: ditambahkan di atas harga untuk kafe, restoran, katering, roti, minuman, food court; nama pajak PB1.
- Biaya layanan: 5% untuk makan di tempat (kafe dan restoran).
- Struk: format Ringkas untuk kafe, roti, minuman, food court; pesan penutup "Terima kasih, selamat menikmati!".
- Nomor antrian: menyala untuk kafe, minuman, food court, roti; tampilan layar "Siap & disiapkan" untuk kafe dan food court.
- Tiket dapur: cetak otomatis setelah pembayaran, semua kategori kecuali kategori jasa (ongkos kirim, kemasan).
- Alur status pesanan: Baru, Diproses, Siap, (Diantar), Selesai (katering: Dipesan, Dimasak, Siap kirim, Dikirim, Selesai).
- Stok: kafe dan restoran memilih sendiri; saat stok habis "tetap bisa dijual" untuk jenis yang stoknya bukan fitur utama; batas margin 50%.
- Kategori pengeluaran tambahan: Belanja bahan (tanpa stok) [HPP], Gas LPG, Kemasan & plastik.
- Shift: modal awal disarankan Rp 300.000.

---

## 7. Fitur tidak relevan untuk Makanan & Minuman (23)

Fitur ini disembunyikan di aplikasi F&B: 8. Data pembeli & nama STNK/BPKB; 9. Tukar tambah (trade-in) kendaraan; 11. Pembayaran via leasing (DP + pencairan leasing); 12. Invoice tagihan pelanggan (A4, jatuh tempo); 19. Iuran rutin & status bayar anggota; 20. Pengingat iuran via WhatsApp; 21. Kelompok arisan & kocokan oleh admin; 28. Order towing (multi rute & kendaraan, dokumen per kendaraan); 29. Subkon towing ke vendor (1 dokumen per order); 30. Proses dokumen STNK/BPKB & balik nama; 31. Antrian multi loket / ruang; 32. Pilih petugas saat ambil antrian; 33. Cek kendaraan masuk & riwayat servis per plat; 44. Golongan obat & peringatan resep; 45. Durasi layanan; 46. Estimasi selesai per layanan; 47. Data unit kendaraan (no. rangka, no. mesin, spesifikasi); 48. Inspeksi & kondisi unit bekas; 58. Pengingat servis / kontrol berkala; 60. Data anggota (kelas / kelompok); 66. Uang jalan driver otomatis per rute; 75. Komisi & bagi hasil karyawan; 86. Kegiatan, kas & LPJ.

---

## 8. Urutan pembangunan yang diusulkan

Usulan saya berdasarkan jumlah jenis usaha F&B yang menganggapnya inti dan ketergantungan antar fitur. Perlu persetujuan lead.

1. **Fondasi (SELESAI di kode, belum diuji di HP):** katalog 4 paket + 87 fitur dan mode bisnis 7 jenis usaha F&B (migrasi 0009 dan 0010).
2. **Alur pesanan kafe:** varian dan tambahan produk (no. 42), tiket dapur (35), status pesanan (26), nomor antrian beserta layar (34).
3. **Pengaturan terpadu dengan bawaan per jenis usaha:** pajak (4), biaya layanan (6), diskon (3), struk (22 sampai 25), pembayaran (13, 14, 18), stok.
4. **Katalog dan stok:** kategori di kasir (36), margin (37), riwayat mutasi (49), unggah dan ekspor template (38, 39), pengingat kedaluwarsa (50).
5. **Pelanggan dan karyawan:** promo ulang tahun (56), kirim WA (57), survei (59), absensi (62), jadwal dan cuti (63), hak akses (61).
6. **Keuangan:** pengeluaran (67), laba rugi (69), HPP dan margin (72), PPN/PB1 (73), PPh Final (70), settlement QRIS (74).
7. **Akuntansi lanjutan (Enterprise):** jurnal, buku besar, payroll, aset tetap, ekspor akuntansi (76 sampai 85). Pekerjaan besar; sebaiknya pasca Release 1.

---

## 9. Yang perlu dikonfirmasi ke lead

1. Pilih meja, catatan per item, pisah bill, layar dapur, menu habis, dan tip tidak ada di daftar IMOGI. Tetap dikerjakan atau dibuang?
2. Apakah modul Akuntansi (laba rugi sampai ekspor software akuntansi) masuk Release 1 atau sesudahnya?
3. Alur upgrade: manual lewat tim IMOGI (menurut panduan) atau pembayaran Xendit di aplikasi (yang sudah dibangun)?
4. Cetak struk dan tiket dapur: perangkat printer apa yang dijadikan acuan uji?


**KEMAJUAN 2026-11-12 (no. 26 Status pesanan):** estimasi selesai pesanan. Lama pengerjaan bawaan per outlet (menit, 0 = mati) diatur di Pengaturan struk (migrasi 0014, kolom `pengaturan_outlet.estimasi_menit`, ikut sync pull). Halaman Status Pesanan menampilkan "Estimasi selesai HH:mm" (waktu dibuat + menit) selama pesanan Baru/Diproses, dan "Terlambat N mnt" bila lewat. Pengisian > 0 digerbang fitur `status_pesanan`. Belum ada: estimasi per produk (hanya satu angka per outlet), pesan WhatsApp saat siap, dan uji di HP.

**KEMAJUAN 2026-11-12 (no. 26 Status pesanan, lanjutan):** tombol "Kabari pelanggan (WhatsApp)" di kartu Status Pesanan saat pesanan Siap, hanya bila pesanan punya pelanggan bernomor HP. Membuka WhatsApp dengan pesan siap (nama pelanggan, nomor antrian, nama toko; kalimat berbeda untuk pesanan antar); kasir mengirim sendiri, bukan pengiriman otomatis. Belum ada: pengiriman otomatis lewat WhatsApp API, pengaturan templat pesan, dan uji di HP (WhatsApp harus terpasang; bila gagal dibuka, jatuh ke menu bagikan).

**KEMAJUAN 2026-11-12 (no. 67 Catat pengeluaran & biaya operasional, Starter, kode `expenses`):** tersedia sebagian. Backend: tabel `pengeluaran` (migrasi 0015), endpoint `GET/POST/DELETE /pengeluaran` (digerbang fitur `expenses`, izin `laporan.lihat`, pencatatan idempoten per id, hapus lunak, jejak audit). Aplikasi: menu Lainnya > Pengeluaran (Owner/Manajer): rentang Hari ini / 7 hari / Bulan ini, total, rincian per kategori, catat dan hapus. Kategori F&B: belanja bahan (HPP), gas LPG, kemasan, gaji, sewa, listrik & air, pemasaran, perawatan, lainnya. **Batas:** pencatatan langsung ke server (butuh internet), belum offline; belum ada edit, lampiran foto nota, pengeluaran berulang, dan belum terhubung ke laporan laba rugi (no. 69) maupun kas shift. Belum diuji di HP.

**KEMAJUAN 2026-11-12 (no. 69 Laporan laba rugi, Professional, kode `profit_loss`):** tersedia sebagian. Server: `GET /laporan/laba-rugi` (digerbang fitur `profit_loss`, izin `laporan.lihat`, rentang dibatasi seperti laporan lain, per outlet opsional). Aplikasi: Lainnya > Laba rugi (Owner/Manajer): penjualan kotor, diskon, penjualan bersih, HPP, laba kotor, biaya operasional per kategori, laba/rugi bersih; rentang Hari ini / 7 hari / Bulan ini. **Batas dan keputusan:** pajak/service tidak dihitung sebagai pendapatan; belanja bahan tidak dikurangkan lagi karena sudah di HPP (HPP berasal dari HPP produk yang dikirim HP per item, jadi toko yang tidak mengisi HPP produk akan melihat laba terlalu besar); refund belum diperhitungkan; belum ada ekspor, perbandingan periode, dan pajak penghasilan. Butuh internet. Belum diuji di HP.

**KEMAJUAN 2026-11-12 (no. 73 Rekap pajak PPN & PB1, kode `tax_recap`; no. 70 PPh Final UMKM, kode `tax_pph`; keduanya Professional):** tersedia sebagian. Server: `GET /laporan/rekap-pajak` (pajak dan service dipungut per nama dan tarif, dipisah antara pajak dan service) dan `GET /laporan/pph-final` (tarif 0,5% x peredaran bruto, rincian per bulan lokal), masing-masing digerbang fitur, izin `laporan.lihat`, batas rentang laporan. Aplikasi: Lainnya > Rekap pajak dengan tab PPN/PB1 dan PPh Final, rentang Hari ini / 7 hari / Bulan ini. **Batas:** hanya rekap untuk pencatatan; belum ada ekspor, pemisahan PPN masukan/keluaran, ambang peredaran bebas pajak Rp 500 juta, status wajib pajak, dan pelaporan SPT. PPh Final hanyalah estimasi. Butuh internet. Belum diuji di HP.

**KEMAJUAN 2026-11-12 (no. 38 Upload produk via template, kode `ekspor_impor`, Starter; no. 39 Ekspor produk, kode `catalog_export`, Starter):** tersedia. Aplikasi: Lainnya > Impor & ekspor produk (izin `produk.kelola`): bagikan template CSV, pilih berkas CSV (koma atau titik koma, kolom nama/kategori/harga_jual/hpp/sku/barcode/deskripsi, harga format Indonesia), pratinjau baris siap dan bermasalah, "Periksa dulu" (simulasi di server) dan "Impor", lalu ekspor seluruh produk HP ke CSV. Server: `POST /produk/impor` (maks 500 baris, per baris berdiri sendiri, kategori dibuat otomatis bila belum ada, SKU/barcode ganda ditolak, kuota produk paket ditegakkan). **Batas:** impor butuh internet; hanya CSV (bukan .xlsx); belum mendukung update produk yang sudah ada (hanya menambah), varian, stok awal, dan gambar. Ekspor memakai data lokal HP. Belum diuji di HP (pemilih berkas dan menu bagikan perlu dicoba di perangkat sungguhan).

**KEMAJUAN 2026-11-12 (no. 62 Absensi karyawan, kode `absensi`, Professional):** tersedia sebagian. Server: `GET /absensi/saya`, `POST /absensi/masuk`, `POST /absensi/keluar`, `GET /absensi?dari&sampai&tz_menit` (digerbang fitur `absensi`; tiap karyawan hanya mencatat dirinya; rekap semua karyawan untuk izin `laporan.lihat`, peran lain hanya melihat miliknya). Aplikasi: Lainnya > Absensi: tombol absen masuk/keluar, status sedang masuk sejak jam berapa, rekap jam kerja per karyawan dan riwayat (Hari ini / 7 hari / Bulan ini). Batas hari mengikuti zona waktu perangkat. **Belum ada:** foto dan lokasi saat absen (kolom sudah ada di tabel), jam kerja/jadwal dan penandaan terlambat (status selalu "hadir"), izin/sakit/alpa, koreksi absensi oleh pemilik, ekspor, dan absensi offline. Belum diuji di HP.

**KEMAJUAN 2026-11-13 (no. 53 Upload pelanggan via template, kode `customer_import`, Professional):** tersedia. Aplikasi: Lainnya > Impor pelanggan (izin `pelanggan.kelola`): bagikan template CSV, pilih berkas (koma atau titik koma; kolom nama, no_hp, email, tanggal_lahir, catatan), pratinjau baris siap/bermasalah, "Periksa dulu" (simulasi di server) dan "Impor". Server: `POST /pelanggan/impor` (maks 500 baris, per baris berdiri sendiri; nomor HP dibersihkan dan 0812/62812/+62812 dianggap sama; nomor yang sudah terdaftar atau ganda dalam berkas ditolak; email dan panjang nomor divalidasi). **Batas:** hanya menambah (tidak memperbarui pelanggan lama), tanpa poin/level member/batas kasbon, hanya CSV, butuh internet. Belum diuji di HP.
