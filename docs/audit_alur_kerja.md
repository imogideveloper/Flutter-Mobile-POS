# Audit alur kerja terhadap arahan (2026-11-10)

Dasar: isi aktual tiga workbook di `docs/dokumentasi-qa/`, kode di branch `feature/alur-kafe-imogi`, dan arahan di `docs/alur_kerja.md`.
Tidak ada kode atau workbook yang diubah dalam audit ini. Semua temuan di bawah diverifikasi dari berkas aktual.

## A. Ketidaksesuaian pekerjaan kita dengan arahan

| # | Arahan | Kondisi aktual | Dampak |
|---|---|---|---|
| A1 | Prioritaskan transaksi, stok, pembayaran, login, sync **sebelum** fitur F&B baru | Sesi lalu membangun varian, tiket dapur, status pesanan, antrian, kategori tiket (TASK-113, 117, 118) sementara BUG-012, 014, 015 masih Open, TASK-107 (TC Critical kasir) Backlog, TASK-122 (login PIN) Backlog | Urutan terbalik. Fitur baru bertambah, fondasi belum tervalidasi |
| A2 | Jangan tetapkan Release Scope sepihak; TASK-103/104/105 dulu | TASK-103/104/105 masih To Do, sementara fitur F&B terus dibangun | Risiko membangun fitur di luar scope final |
| A3 | Jangan ubah requirement sepihak | Server kini **menerima transaksi offline walau pelanggan, tipe order, meja tidak ada di server** (pelanggan dan poin ditukar dikosongkan) dan menerima transaksi pada shift yang sudah tutup. Requirement-nya tidak pernah tertulis | Keputusan perilaku diambil tanpa persetujuan lead; poin loyalitas bisa hilang. Perlu konfirmasi |
| A4 | Hasil uji dan retest dicatat dengan bukti | BUG-010, 011, 013, 018 sampai 021 berstatus Ready for Retest, tetapi **sheet Retest & Regression hanya berisi data dummy**. Bukti nyata (server menerima 14 transaksi, 2 shift pada 2026-11-10) belum tercatat | Bukti ada tetapi tidak terdokumentasi |
| A5 | Setiap perubahan kode punya test case, hasil, dan keterkaitan task/bug | Empat fitur 2026-11-10 (cetak ulang tiket, tahap Diantar, awalan antrian, kategori tiket) hanya ada di catatan TASK-117/118 dan Gap Imogi. **Tidak ada FEAT, TC, atau task sendiri** di workbook QA | Tidak bisa diuji atau dilacak terpisah |
| A6 | Jangan ubah struktur workbook; perbarui berdasarkan bukti | Ketiga workbook sebelumnya **dibangkitkan ulang dari skrip** yang kini hilang. Jika pemilik mengedit manual (mis. di Drive), editan itu bisa tertimpa. Sheet "Gap Imogi" dan "Batas Paket" ditambahkan atas permintaan pengguna, bukan arahan ini | Risiko menimpa pekerjaan manual; skrip tidak bisa diulang |
| A7 | Data dummy diabaikan atau dihapus | Dummy masih ada: BUG-901..903, RUN-901..903, RETEST-901, UAT-RUN-901/902. Ikut terhitung di ringkasan jumlah (tile) kecuali rumusnya mengecualikan | Angka ringkasan bisa menyesatkan |
| A8 | Jangan mengarang identitas | Commit memakai `nurul-izzhh <nurul-izzhh@users.noreply.github.com>`. Pengguna hanya menyebut nama, **email noreply saya susun sendiri** | Penulis commit mungkin tidak terhubung ke akun GitHub yang benar |
| A9 | Done hanya dengan bukti | Kepatuhan baik di sini: tidak ada task Done tanpa bukti; fitur varian, kontrol jumlah, dan sync shift tertulis In Progress / Ready for QA | Sesuai. Tetap jaga |

## B. Konflik antara arahan dan workbook (didokumentasikan, belum diputuskan)

| # | Arahan menyebut | Workbook berisi | Catatan |
|---|---|---|---|
| B1 | BUG-019 = "sinkronisasi data pelanggan"; BUG-020 = "transaksi offline dan data induk pelanggan" | BUG-019 = sync berhenti bila server belum memakai kode terbaru; BUG-020 = ditolak "Pelanggan tidak ditemukan"; BUG-018 = shift tidak dikirim | Deskripsi BUG-019 berbeda. Workbook dipertahankan |
| B2 | UAT-009 = Refund | UAT-009 = pembayaran split; refund = **UAT-012** | Pakai ID workbook |
| B3 | TASK-022 sampai 027 ada di Task Tracker | ID itu ada di **Project Timeline** (seri TASK-0xx), bukan Task Tracker (seri 1xx) | Dua seri ID, sesuai catatan di Instructions workbook |
| B4 | Daftar task berhenti di TASK-115 | Workbook punya TASK-116 sampai TASK-133 (meja, tiket dapur, antrian, paket, perbaikan bug, fondasi IMOGI) | Task ini dipertahankan |
| B5 | Temuan 1: "login PIN tidak berhasil" | BUG-009: tombol "Masuk dengan PIN karyawan" tidak melakukan apa pun di perangkat baru | Gejalanya mungkin hanya sebagian temuan. Perlu direproduksi setelah perangkat dipasangkan |
| B6 | RUN-002 (TC-007 qty) tercatat **Pass** | Catatannya sendiri: "angka tidak bisa diketik" (kini dikerjakan di BUG-021) | Pass dengan catatan kekurangan. Retest setelah BUG-021 |
| B7 | RUN-003 (TC-009 stok melebihi) Fail terkait **BUG-012** | BUG-012 = pengaturan outlet gagal tersimpan; akar masalah TC-009 memang karena saklar stok minus tidak bisa dimatikan | Keterkaitan sah, tetapi tidak langsung |

## C. Audit kode untuk bug utama

| Bug | Kondisi kode | Tes otomatis | Evidence perangkat | Status workbook | Kesimpulan |
|---|---|---|---|---|---|
| BUG-013 void ganda | Void kedua ditolak (`TransaksiSudahDivoidException`), stok tidak bertambah lagi | Ada (`transaksi_repository_test.dart`) | Belum | Ready for Retest | Sesuai. Menunggu uji HP |
| BUG-018 shift tidak dikirim | Shift dikirim sebelum transaksi; transaksi sah pada shift tutup; kas dihitung ulang | Ada (backend dan Flutter) | **Sebagian:** server menerima 14 transaksi dan 2 shift dari HP | Ready for Retest | Perlu retest lengkap dan catatan evidence |
| BUG-019 parser pull | Toleran terhadap field yang tidak ada | Tidak ada tes khusus | Terlihat di log | Ready for Retest | Tambah tes khusus |
| BUG-020 pelanggan hilang | Diterima tanpa pelanggan | Ada (backend) | Server menerima transaksi tersebut | Ready for Retest | **Butuh keputusan lead (A3)** |
| BUG-021 kontrol jumlah | Minus, plus, isi manual di kartu dan keranjang; batas stok | Ada (1 alur widget) | Belum | Ready for Retest | Lihat B6; belum diuji penghapusan dan modifier di total |
| **BUG-012 paket Gratis** | **Belum diperbaiki.** App selalu mengirim `tampil_logo` dengan nilai dari server (bawaan `true`), lalu server menolak 403 pada paket Gratis | Tidak ada | Gagal di HP | **Open** | Akar masalah jelas, perbaikan kecil. Belum dikerjakan |
| **BUG-009 login PIN** | **Belum diperbaiki.** `AuthGatePage` memberi `onSelesai: () {}` ke `OtpLoginPage` | Tidak ada | Gagal di HP | **Open** | Pengguna sempat menjawab "Nanti dulu"; arahan baru memasukkannya ke Fase 4 |

## D. Test case Critical yang belum dijalankan
Sembilan dari Critical berstatus Not Tested: **TC-011, TC-012** (pembayaran), **TC-041** (build release), **TC-042, TC-057, TC-058, TC-061** (varian), **TC-065** (tiket dapur), **TC-068** (sync shift). TC-011 dan TC-012 berada di jalur pembayaran, Fase 2 dan 6.

## E. Hambatan
- **Printer Bluetooth** (TC-018..020, TASK-108): perangkat belum ada. Blocked.
- **Kunci Xendit test** (QRIS, TC-014): belum ada. Blocked.
- **Keputusan lead:** Release Scope (TASK-104), tanggal mulai proyek (TASK-105), harga dan kuota paket (TASK-119), perilaku data induk hilang saat sync (A3), dashboard (TASK-133).
- **Perangkat:** pemasangan APK dan uji butuh layar HP terbuka dan konfirmasi OPPO.

## F. Pekerjaan yang aman dikerjakan tanpa keputusan lead
1. BUG-012: kirim `tampil_logo` hanya bila berubah, atau gate di server hanya saat nilai berubah (Fase 5).
2. Tes untuk kontrol jumlah: hapus item, total dengan modifier, qty tidak negatif (Fase 2).
3. Tes retry sync tidak menggandakan transaksi dan sinkron kas masuk/keluar shift (Fase 3).
4. Reproduksi login PIN dan tambah tes untuk BUG-009 (Fase 4), bila pengguna mengizinkan.
5. Catat evidence nyata ke sheet Retest, tambah FEAT/TC untuk empat fitur 2026-11-10.

## G. Hasil pekerjaan lanjutan (2026-11-10)

Format laporan task sesuai `docs/alur_kerja.md`.

### TASK-125 / BUG-012 (Fase 5), pengaturan outlet paket Gratis
- **Related Feature ID:** FEAT-012. **Kondisi awal:** Open, Backlog.
- **Temuan:** klien mengirim ulang seluruh pengaturan tiap simpan, termasuk `tampil_logo=true` (nilai bawaan server). Server menolak 403 pada paket tanpa fitur logo, sehingga **semua** pengaturan lain ikut gagal tersimpan.
- **Perubahan:** `backend/app/routers/outlet.py`: gate fitur hanya berlaku saat nilai benar-benar berubah menjadi aktif (berlaku untuk `struk_ringkas`, `tampil_logo`, `pakai_nomor_antrean`). Aturan paket tidak berubah: logo yang sedang mati tetap tidak bisa dinyalakan tanpa fitur `logo_struk`.
- **Tes otomatis:** 2 tes baru di `backend/tests/test_pengaturan_struk.py` (simpan pengaturan lain pada paket Gratis berhasil; menyalakan logo dari mati tetap 403). 14 tes di berkas itu lulus.
- **Tes perangkat:** belum. **Status akhir:** BUG-012 Ready for Retest, TASK-125 Review 80%. Belum Closed.
- **Risiko:** logo bernilai `true` pada toko Gratis tetap tersimpan sebagai nilai bawaan. Perlu keputusan lead apakah bawaan seharusnya `false` untuk paket tanpa fitur logo.
- **Next action:** retest di HP: simpan pengaturan non-logo pada paket Gratis (TC-054).

### TASK-114 / BUG-021 (Fase 2), kontrol jumlah
- **Tes otomatis baru:** `test/keranjang_qty_test.dart` (8 tes): qty 0 atau negatif menghapus baris, tidak pernah ada baris dengan qty ≤ 0; produk sama ditambah berulang menjadi satu baris; ubah qty tidak memengaruhi produk lain; subtotal mengikuti qty; subtotal dengan tambahan = (harga + tambahan) x qty; qty pecahan; item yang dihapus tidak ikut tersimpan di transaksi dan total sesuai qty akhir.
- **Belum tercakup:** validasi stok pada isian manual sudah diuji di alur widget, tetapi pengaruh perubahan qty terhadap total pembayaran dan tiket dapur belum diuji end-to-end. **Tes perangkat:** belum.

### TASK-115 / BUG-018, 019, 020 (Fase 3), integritas sync
- **Tes otomatis baru:** `backend/tests/test_sync_integritas.py` (4 tes): retry batch tiga kali tidak menggandakan transaksi, shift, maupun potongan stok; push shift "buka" yang terlambat tidak membuka kembali shift yang sudah tutup; satu transaksi ditolak tidak menahan yang lain, alasan dikirim balik, dan sync log bernilai `sebagian`; transaksi yang ditolak bisa diterima pada pengiriman berikutnya setelah penyebabnya hilang. Flutter: 1 tes baru di `test/sync_repository_test.dart` (ditolak tetap menunggu dan dikirim ulang; yang diterima tidak dikirim lagi).
- **Temuan audit, kini dikerjakan:** kas masuk/keluar shift (`kas_shift`) sebelumnya tidak dikirim HP, sehingga kas yang seharusnya di server bisa berbeda dari HP. Kini dikirim bersama shiftnya (idempoten per id) dan server menghitung ulang kas setelahnya. Tes: backend (kas 100.000 + 30.000 tunai + 20.000 masuk - 5.000 keluar = 145.000, retry tidak menggandakan) dan Flutter (payload kas_shift). Status TASK-115 tetap In Progress sampai retest di HP.
- **Tes perangkat:** sebagian (server menerima 14 transaksi dan 2 shift dari HP pada 2026-11-10); retest lengkap dan pencatatan ke sheet Retest masih diperlukan.

### Hasil tes keseluruhan
Lihat ringkasan pada laporan sesi; semua tes otomatis relevan lulus.

### TASK-127 / BUG-015 (Fase 6), metode pembayaran di riwayat
- **Related Feature ID:** FEAT-014. **Kondisi awal:** Open, Backlog.
- **Temuan:** `labelMetodeBayar()` hanya mengenali dua id placeholder lama. Id metode bayar asli dari server berbentuk UUID, sehingga semua transaksi asli tampil "-". Cacat yang sama ada di ringkasan metode di Laporan.
- **Perubahan:** `metode_bayar_label.dart` mencari nama di peta id-ke-nama dari tabel `metode_bayar` lokal; `namaMetodeBayarProvider` (termasuk metode nonaktif karena transaksi lama masih merujuknya); dipakai di `riwayat_list_page.dart`, `transaksi_detail_page.dart`, dan `laporan_page.dart`. Split tetap "Campuran", id placeholder lama tetap dikenali.
- **Tes otomatis:** `test/metode_bayar_label_test.dart` (7 tes), termasuk transaksi nyata yang dibayar dengan UUID tampil sebagai "Transfer Bank".
- **Tes perangkat:** belum. **Status akhir:** BUG-015 Ready for Retest, TASK-127 Review 80%. Belum Closed.
- **Next action:** retest di HP: bayar tunai dan transfer lalu cek Riwayat dan Laporan (TC-056).

### BUG-014 (Fase 6), Refund "transaksi tidak ditemukan"
- **Related Feature ID:** FEAT-014. **Task:** tidak ada task terpisah di Task Tracker (dicatat pada bug). **Kondisi awal:** Open.
- **Temuan:** refund selalu online dan memakai id item dari server. Transaksi yang belum tersinkron tidak ada di server, sehingga server membalas 404 dan layar menampilkan teks mentah "transaksi tidak ditemukan", **setelah** PIN persetujuan diminta.
- **Perubahan:** `transaksi_detail_page.dart`: sebelum PIN, cek `disinkronPada`; bila belum, dialog "Transaksi belum tersinkron" dengan tombol "Sinkronkan sekarang" (menjalankan sync, lalu lanjut bila transaksi diterima server; pesan jelas bila offline, sync gagal, atau transaksi ditolak). `refund_page.dart`: respons 404 menampilkan petunjuk sinkron.
- **Tes otomatis:** `test/refund_belum_sync_test.dart` (dialog muncul, PIN belum diminta, Batal aman) dan 1 tes baru di `test/refund_flow_test.dart` (404 menampilkan petunjuk). Alur refund yang sudah ada tetap lulus.
- **Tes perangkat:** belum. **Status akhir:** BUG-014 Ready for Retest. Belum Closed.
- **Catatan:** dugaan penyebab di bug (transaksi belum tersync, BUG-010) terkonfirmasi lewat kode. Refund pada transaksi yang tersinkron tetap bergantung pada koneksi (sesuai desain refund online).
- **Next action:** retest di HP: buat transaksi, refund sebelum sync (muncul ajakan sinkron), sinkronkan, lalu refund berhasil (TC-023).

### TASK-122 / BUG-009 (Fase 4), tombol "Masuk dengan PIN karyawan"
- **Related Feature ID:** FEAT-057 (login), FEAT-001. **Kondisi awal:** Open, Backlog. Temuan manual pengguna nomor 1 sudah memiliki ID bug (BUG-009), tidak dibuat bug baru.
- **Temuan:** `AuthGatePage` memberi `onSelesai: () {}` (kosong) ke `OtpLoginPage` pada perangkat yang belum dipasangkan, jadi tombol tidak melakukan apa pun. Perangkat baru juga belum punya data karyawan (karyawan = pengguna dari server), sehingga layar PIN memang belum bisa dipakai di sana.
- **Perubahan:** `otp_login_page.dart`: parameter baru `onMasukDenganPin`; tombol hanya tampil bila diisi. `login_page.dart` mengisinya (kembali ke pilih pengguna + PIN) saat membuka halaman OTP dari "Lupa PIN kasir?". Di perangkat baru tombol disembunyikan dan diganti petunjuk "karyawan masuk dengan PIN setelah perangkat dipasangkan pemilik". Perilaku sebelumnya (tombol hidup di halaman lupa PIN) dipertahankan.
- **Tes otomatis:** `test/otp_login_pin_button_test.dart` (2 tes): perangkat baru tanpa tombol mati dan dengan petunjuk; perangkat terpasang: tombol kembali ke pilih pengguna. Login PIN yang sudah ada (`login_flow_test.dart`: PIN benar masuk, PIN salah ditolak) tetap lulus.
- **Tes perangkat:** belum. **Status akhir:** BUG-009 Ready for Retest, TASK-122 Review 60%. Belum Closed.
- **Belum dicakup (Fase 4):** (1) reproduksi login PIN karyawan asal server di HP (pengguna sync, hash PIN, kunci percobaan); gejala "login PIN tidak berhasil" mungkin lebih luas dari tombol ini; (2) audit hak akses per role (kasir tidak boleh menjalankan fungsi owner); (3) logout dan sesi. Butuh akses HP dan akun karyawan nyata.
- **Keputusan yang dibutuhkan:** apakah karyawan di perangkat baru perlu jalur masuk sendiri (mis. kode undangan), atau cukup menunggu pemilik memasangkan perangkat (perilaku sekarang).
- **Next action:** retest di HP (TC-052): pasang aplikasi baru, pastikan tidak ada tombol mati dan petunjuk tampil; pada perangkat terpasang uji "Lupa PIN kasir?" lalu tombol PIN.

### TASK-111 / BUG-004 (Fase 3), sync otomatis
- **Related Feature ID:** FEAT-050. **Kondisi awal:** Open, Backlog. Audit: sync hanya berjalan lewat tombol Sync (dan sebagian layar pengaturan secara "api-lupakan"); **tidak ada pemicu otomatis** dan **tidak ada penjaga sync bersamaan** (beberapa pemanggil bisa menjalankan push/pull tumpang tindih).
- **Perubahan:** `lib/core/network/auto_sync.dart` (kelas `AutoSync`, `AutoSyncHost`, `picuSyncSetelahTransaksi`), dipasang di `main.dart`. Pemicu: aplikasi dibuka atau kembali aktif, koneksi pulih (offline ke online), berkala tiap 5 menit selama aplikasi terbuka, dan setelah pembayaran (dipicu `StrukPage` **sesudah** snapshot struk tersimpan, karena snapshot ikut payload sync). Jeda minimum 30 detik; jeda dilipatgandakan tiap gagal (maks 15 menit); gagal tidak menampilkan error. `SyncRepository.jalankan()` kini satu sync pada satu waktu (pemanggil bersamaan menunggu hasil yang sama). Penghitung "menunggu sync" dan status paket dimuat ulang setelah sync sukses.
- **Tes otomatis:** `test/auto_sync_test.dart` (6 tes: jeda, paksa, tidak bersamaan, backoff dan pemulihan, perangkat belum terpasang, pemicu host) dan 1 tes di `test/sync_repository_test.dart` (single-flight). Seluruh 289 tes Flutter lulus.
- **Tes perangkat:** belum. **Status akhir:** BUG-004 Ready for Retest, TASK-111 Review 70%. Belum Closed.
- **Batas yang perlu diketahui lead:** sync **tidak** berjalan saat aplikasi tertutup penuh (tanpa workmanager/layanan latar belakang). Risiko transaksi tertahan bila HP rusak sebelum aplikasi dibuka lagi tetap ada, tetapi jauh lebih kecil. Belum ada indikator status sync di layar utama.
- **Keputusan yang dibutuhkan:** apakah sync latar belakang saat aplikasi tertutup (workmanager) masuk Release 1.
- **Next action:** retest di HP (TC-038): buat transaksi tanpa membuka menu Sync, tunggu sampai 1 menit, cek server; matikan data lalu nyalakan lagi dan pastikan transaksi tertahan terkirim.

### TASK-122 (Fase 4), hak akses per role di menu Lainnya
- **Related Feature ID:** FEAT-057 (login/role). **Kondisi awal:** tidak ada ID bug; temuan audit kode, belum dilaporkan pengguna.
- **Temuan:** matriks izin role sudah ada (`seed.dart`: Kasir hanya transaksi.buat, shift.buka_tutup, kas.keluar_masuk, pelanggan.kelola) dan dipakai untuk PIN-approval (void, refund, batal pesanan, ubah/hapus pengguna). Namun **menu Lainnya menampilkan semua pengaturan ke semua role**: kasir bisa membuka Stok, Kategori, Pajak, Metode bayar, Outlet dan struk, Karyawan, Paket langganan. Tidak ada izin yang diperiksa di layar-layar itu.
- **Perubahan:** `IzinService.daftarIzin` (sumber sama dengan `hasIzin`: role_izin dari server lebih dulu, lalu seed lokal), `izinSayaProvider`, dan `lainnya_page.dart` menyembunyikan baris menu sesuai izin: shift/kas = shift.buka_tutup; Pelanggan = pelanggan.kelola; Stok = stok.kelola; Kategori, Varian = produk.kelola; Outlet dan struk, Metode bayar, Tipe pesanan, Level member, Paket langganan = pengaturan.kelola; Pajak dan Promo = promo.kelola; Karyawan = pengguna.kelola. Printer dan Status pesanan tetap terbuka (perangkat/alur kerja kasir). Belum login atau izin belum termuat = menu terbatas tersembunyi.
- **Tes otomatis:** `test/izin_service_test.dart` (+2): owner punya izin Pengguna/Pengaturan/Stok/Laporan, kasir tidak; role dari tabel sync dipakai bila ada. Seluruh 291 tes Flutter lulus.
- **Tes perangkat:** belum. Status TASK-122 tidak diubah (tetap Review 60%).
- **BATAS (belum dicakup):** (1) hanya menyembunyikan menu, **rute tidak dijaga** (URL langsung/tautan dalam aplikasi tetap bisa membuka); (2) tab bawah **Produk dan Laporan** masih terlihat semua role (izin produk.kelola dan laporan.lihat belum diterapkan di sana); (3) pemetaan izin ke menu (mis. Pajak = promo.kelola, Level member = pengaturan.kelola) adalah **keputusan saya**, karena dokumen IMOGI yang dipegang tidak merinci izin per menu; (4) karyawan asal server memakai role sistem (roleId tidak diganti), perlu dipastikan di HP bahwa role Kasir dari server terpetakan benar, bila tidak menu karyawan itu kosong (gagal aman, bukan terbuka).
- **Keputusan yang dibutuhkan:** lead mengonfirmasi matriks izin per menu dan apakah Produk/Laporan disembunyikan untuk kasir.
- **Next action:** retest di HP: login sebagai Kasir lalu buka Lainnya (hanya shift/kas, pelanggan, status pesanan, printer yang tampil); login Owner (semua tampil).
- **Lanjutan (rute dan tab dijaga):** `IzinGuard` (`lib/core/widgets/izin_guard.dart`) membungkus halaman yang dijaga di `app_router.dart` (Pengguna, Stok, Shift/Kas, Tipe pesanan, Level member, Kategori, Varian, Pajak, Promo, Outlet-struk, Metode bayar, Paket langganan, Pelanggan/Piutang, Laporan, Produk) dengan izin yang sama seperti menu; tanpa izin tampil "Tidak ada akses", bukan isi halaman. Tab bawah Produk (produk.kelola) dan Laporan (laporan.lihat) disembunyikan di `AppShell`. Tes: `test/izin_guard_test.dart` (3) dan `shift_kasir_identity_test.dart` diubah memakai jalur Lainnya serta memastikan kasir tidak melihat tab Produk/Laporan/menu Karyawan. Seluruh tes lulus.
- **Dampak yang perlu diketahui:** kasir tidak lagi bisa membuka halaman Produk (sebelumnya terbuka) dan tidak melihat tab Laporan. Jalur masuk ke Shift bagi kasir kini lewat Lainnya. Rute Riwayat/Kasir tidak dijaga (hak dasar kasir). Rute `/status-pesanan` dan printer tetap terbuka. Tetap belum diuji di HP, dan keputusan lead atas matriks izin per menu masih dibutuhkan; jika lead memutuskan kasir boleh melihat Laporan/Produk, ubah izin role Kasir (bukan kode).

### TASK-122 (Fase 4), logout dan sesi
- **Temuan:** satu-satunya tombol "Keluar" (ganti kasir) ada di menu titik tiga halaman **Produk**. Setelah tab Produk disembunyikan untuk kasir (perubahan penjagaan izin di atas), **kasir kehilangan jalur logout**; ini regresi akibat perubahan saya, ditemukan sebelum sampai ke HP.
- **Perubahan:** baris "Keluar / ganti kasir" (menampilkan nama pengguna aktif) di grup Akun menu Lainnya, terlihat semua role. Menu titik tiga di Produk tidak diubah.
- **Tes otomatis:** `test/logout_kasir_test.dart` (kasir tanpa tab Produk keluar lewat Lainnya, sesi berakhir). Seluruh 295 tes lulus.
- **Sifat sesi (perilaku lama, tidak diubah):** sesi hanya di memori; menutup aplikasi = pilih akun lagi. Keranjang/pesanan belum disimpan tidak dibersihkan saat ganti kasir (belum diputuskan, perlu keputusan lead).
- **Tes perangkat:** belum. Next action: di HP login Kasir, buka Lainnya, ketuk "Keluar / ganti kasir", pastikan kembali ke pilih pengguna.

### FEAT no. 26 (Status pesanan), estimasi selesai
- **Catatan alur:** fitur baru, belum punya TASK/FEAT/TC terpisah di workbook (sama seperti empat fitur 2026-11-10); ID perlu ditetapkan lead/QA, tidak saya karang.
- **Perubahan:** backend migrasi 0014 + `estimasi_menit` (model, skema 0..480, gate `status_pesanan` hanya saat nilai berubah menjadi > 0, sync pull); Flutter kolom drift (skema 12), field di Pengaturan struk (terkunci paket), fungsi murni `labelEstimasiPesanan` ([estimasi_pesanan.dart](lib/features/transaksi/domain/estimasi_pesanan.dart)), tampilan di kartu Status Pesanan.
- **Tes otomatis:** backend `test_estimasi_menit_bawaan_validasi_dan_gate_status_pesanan` (30 tes terkait lulus di container); Flutter `estimasi_pesanan_test.dart` (3), `status_pesanan_test.dart` (+1 widget). Seluruh 299 tes Flutter lulus. Migrasi 0014 sudah diterapkan di Docker lokal.
- **Tes perangkat:** belum. **Batas:** satu angka per outlet, bukan per produk; bukan "bukti" Done.
- **Catatan proses:** `dart format` sempat memformat ulang puluhan berkas yang tidak saya ubah; sudah dibatalkan sebelum commit (diff hanya perubahan fitur).
- **Next action:** di HP (paket Enterprise/Bisnis) isi estimasi 15 menit di Pengaturan struk, buat pesanan, cek Status Pesanan (jam estimasi, lalu "Terlambat" setelah lewat).

### FEAT no. 26 (Status pesanan), pesan WhatsApp saat siap
- **Catatan alur:** fitur baru tanpa TASK/FEAT/TC terpisah di workbook (ID belum ditetapkan lead/QA).
- **Perubahan:** `pesan_pesanan_siap.dart` (teks murni), tombol di `status_pesanan_page.dart` memakai `kirimStrukWhatsApp` yang sudah ada. Tombol tampil hanya saat status Siap dan pelanggan punya nomor HP; tanpa pelanggan atau tanpa nomor, tidak tampil.
- **Tes otomatis:** `pesan_pesanan_siap_test.dart` (3) dan `status_pesanan_test.dart` (+2 widget). Seluruh 304 tes Flutter lulus. Pembukaan WhatsApp sungguhan tidak diuji otomatis.
- **Temuan di sela pekerjaan (belum diperbaiki, di luar lingkup):** `StrukPage._kirimWhatsApp` memanggil `kirimStrukWhatsApp(teks: teks)` tanpa `noHpPelanggan`, jadi "Kirim WhatsApp" di struk selalu memakai menu bagikan walau pelanggan punya nomor HP, padahal dokumentasi helper menyebut nomor dipakai langsung. Perlu keputusan apakah ini disengaja.
- **Tes perangkat:** belum. Next action: di HP buat pesanan dengan pelanggan bernomor HP, majukan sampai Siap, ketuk tombol, pastikan WhatsApp terbuka ke nomor itu dengan pesan benar.

### FEAT no. 67 (Catat pengeluaran), tahap pertama
- **Catatan alur:** fitur baru dari daftar gap (❌ Belum ada, inti kafe, paket Starter); belum punya TASK/FEAT/TC di workbook, ID perlu ditetapkan lead/QA.
- **Keputusan saya yang perlu dikonfirmasi lead:** (1) izin memakai `laporan.lihat` (Owner/Manajer; kasir tidak bisa) karena izin `pengeluaran.kelola` belum ada di katalog izin; (2) kategori bawaan di atas disusun dari panduan F&B, bukan daftar resmi IMOGI; (3) online-only mengikuti pola data master lain, padahal pengeluaran di lapangan sering dicatat tanpa sinyal (offline-first belum, butuh keputusan antrian sync).
- **Perubahan:** backend model/migrasi 0015/skema/router/tes (`test_pengeluaran.py`, 6 tes; penyapu isolasi toko `test_isolasi_semua_endpoint.py` diperluas, dan ia sempat menolak endpoint baru sampai didaftarkan, sesuai rancangan); `seed.py` uji ditambah fitur `expenses`; Flutter metode API, `pengeluaran.dart`, `pengeluaran_page.dart`, rute `/pengeluaran` (dijaga izin), menu Lainnya (dijaga izin dan paket).
- **Tes otomatis:** backend 7 tes terkait lulus; seluruh suite backend 407 lulus (3 gagal lama: 2 fixture lingkungan + 1 isolasi yang kini diperbaiki). Flutter `pengeluaran_page_test.dart` (7); seluruh 311 tes Flutter lulus. Migrasi 0015 sudah diterapkan di Docker lokal.
- **Tes perangkat:** belum. Next action: di HP (paket Starter ke atas, login Owner) buka Lainnya > Pengeluaran, catat belanja bahan Rp 150.000 dan gas Rp 25.000, cek total 175.000; coba login Kasir (menu tidak tampil); matikan internet (muncul pesan butuh internet).

### FEAT no. 69 (Laporan laba rugi), tahap pertama
- **Catatan alur:** fitur baru (gap ❌, inti kafe, paket Professional); ID TASK/FEAT/TC belum ditetapkan.
- **Keputusan saya yang perlu dikonfirmasi lead (rumus akuntansi):** (1) pendapatan = subtotal − diskon (tanpa pajak/service); (2) HPP = hpp_satuan × qty item, dikirim HP dari HPP produk; (3) belanja bahan DIKELUARKAN dari biaya agar tidak dihitung dua kali, padahal bila toko tidak mengisi HPP produk, belanja bahan justru satu-satunya biaya bahan (laba bisa tampak terlalu besar); (4) refund belum mengurangi pendapatan; (5) dasar akrual sederhana (tanggal transaksi dan tanggal pengeluaran), bukan kas. Hasil ini bukan laporan keuangan resmi/pajak.
- **Perubahan:** backend `laba_rugi_service.py`, skema `LabaRugiOut`, endpoint di `routers/laporan.py`, seed uji `profit_loss`; Flutter `laba_rugi.dart`, `laba_rugi_page.dart`, rute `/laba-rugi`, menu Lainnya. Tanggal dikirim dengan offset zona waktu (`isoDenganOffset`) agar tanggal pengeluaran tidak bergeser sehari.
- **Tes otomatis:** backend `test_laba_rugi.py` (4: hitungan, di luar rentang, gerbang paket/izin/rentang, isolasi toko) + penyapu isolasi lulus; Flutter `laba_rugi_page_test.dart` (5). Seluruh 316 tes Flutter lulus.
- **Tes perangkat:** belum. Next action: di HP (paket Professional ke atas, login Owner) isi HPP produk, jual 2 gelas, catat pengeluaran gas dan sewa, buka Lainnya > Laba rugi dan cocokkan hitungan dengan kalkulator.

### FEAT no. 73 dan no. 70 (Rekap pajak, PPh Final), tahap pertama
- **Catatan alur:** fitur baru (gap ❌, inti kafe, paket Professional); ID TASK/FEAT/TC belum ditetapkan.
- **Keputusan saya yang perlu dikonfirmasi lead/konsultan pajak:** (1) tarif PPh Final 0,5% dipasang tetap (konstanta di server) dan dasar = subtotal dikurangi diskon (tanpa pajak/service); (2) ambang peredaran bruto yang dibebaskan dan masa berlaku tarif UMKM TIDAK dihitung, jadi angka bisa lebih besar dari yang sebenarnya terutang; (3) rekap pajak mengelompokkan dari baris pajak per transaksi (`transaksi_pajak`), pajak berbeda nama atau tarif tampil terpisah; (4) pajak tanpa tautan master dibaca sebagai pajak biasa kecuali namanya diawali "Service"; (5) transaksi void tidak ikut, refund belum diperhitungkan. Hasil ini bukan laporan pajak resmi.
- **Perubahan:** backend `pajak_service.py`, skema `RekapPajakOut`/`PphFinalOut`, dua endpoint di `routers/laporan.py`, seed uji `tax_recap` dan `tax_pph`; Flutter `rekap_pajak.dart`, `rekap_pajak_page.dart`, rute `/rekap-pajak`, menu Lainnya (digerbang `tax_recap`; tab PPh memakai gerbang `tax_pph` di server, pesan jelas bila terkunci).
- **Tes otomatis:** backend `test_rekap_pajak.py` (4: pengelompokan dan service, void tidak ikut, PPh per bulan, gerbang paket/izin/rentang); Flutter `rekap_pajak_page_test.dart` (5). Seluruh 321 tes Flutter lulus; suite backend 416 lulus, 2 gagal lama (fixture lingkungan).
- **Tes perangkat:** belum. Next action: di HP (paket Professional ke atas, login Owner) aktifkan pajak PB1 dan service, buat dua transaksi, buka Lainnya > Rekap pajak, cocokkan total dengan struk; buka tab PPh Final dan cek 0,5% x penjualan sebelum pajak.

### FEAT no. 38 dan no. 39 (Impor dan ekspor produk), tahap pertama
- **Catatan alur:** fitur baru (gap ❌, inti kafe, Starter); ID TASK/FEAT/TC belum ditetapkan. **Dependensi baru:** `file_picker ^13.3.3` (plugin native) ditambahkan ke `pubspec.yaml`; APK debug tetap terbangun, perilaku di perangkat belum diuji.
- **Keputusan saya yang perlu dikonfirmasi:** (1) format CSV, bukan .xlsx (Excel bisa menyimpan CSV; mendukung .xlsx butuh paket tambahan); (2) impor hanya menambah, duplikat SKU/barcode ditolak (tidak memperbarui produk lama); (3) kategori yang belum ada dibuat otomatis dari nama; (4) HPP dan harga dibulatkan ke rupiah; (5) sel ekspor berawalan `= + - @` diberi apostrof untuk mencegah injeksi rumus Excel.
- **Perubahan:** backend `routers/produk_impor.py`, `schemas/produk_impor.py`; Flutter `produk_csv.dart` (template, baca, ekspor; fungsi murni), `impor_produk_providers.dart` (pemilih berkas dan pembagi berkas yang bisa diganti saat tes), `impor_ekspor_produk_page.dart`, rute `/impor-produk`, menu Lainnya.
- **Tes otomatis:** backend `test_produk_impor.py` (5 tes: simpan dan kategori baru, simulasi tidak menyimpan, baris salah/duplikat, kuota paket, gerbang paket/izin/batas baris) dan penyapu isolasi lulus; Flutter `produk_csv_test.dart` (10) dan `impor_ekspor_produk_test.dart` (6). Seluruh 337 tes Flutter lulus.
- **Tes perangkat:** belum. Next action: di HP (paket Starter ke atas, login Owner) bagikan template, isi di Excel, simpan CSV, impor lewat Pilih berkas CSV, cek produk muncul setelah sync; coba file dengan SKU ganda dan harga "Rp 15.000"; lalu ekspor dan buka hasilnya di Excel.

### FEAT no. 62 (Absensi karyawan), tahap pertama
- **Catatan alur:** fitur baru (gap ❌, inti kafe, Professional); ID TASK/FEAT/TC belum ditetapkan. Tabel `absensi` sudah ada di server dan HP (sebelumnya "hanya tabel lokal"); endpoint dan layar baru.
- **Keputusan saya yang perlu dikonfirmasi:** (1) absen tanpa foto dan tanpa GPS (IMOGI mungkin mewajibkan); (2) tidak ada jam kerja sehingga tidak ada status terlambat (selalu "hadir"); (3) satu karyawan hanya boleh punya satu absen terbuka, masuk ganda ditolak 409; (4) rekap semua karyawan memakai izin `laporan.lihat` (Owner/Manajer); (5) waktu absen memakai jam server (bukan jam HP) agar tidak bisa dimanipulasi, konsekuensinya wajib online; (6) menu Absensi terlihat semua peran (dijaga paket saja), karena setiap karyawan harus bisa absen.
- **Temuan teknis di sela pekerjaan:** batas hari awalnya memakai UTC sehingga shift pagi WIB (06:00) jatuh ke hari sebelumnya; diperbaiki dengan parameter `tz_menit` dan batas dikonversi ke UTC sebelum kueri (tes menangkap perbedaan perilaku SQLite dan Postgres saat membandingkan waktu berzona). Laporan lain yang memakai tanggal tanpa offset (pengeluaran memakai tanggal murni, aman) tidak terpengaruh, tetapi **laporan penjualan lama menerima datetime dari klien apa adanya**; belum diaudit untuk kasus serupa.
- **Tes otomatis:** backend `test_absensi.py` (6 tes: alur masuk/keluar, rekap durasi, pembatasan lihat, rentang dan validasi, gerbang paket dan outlet asing, offset zona) + penyapu isolasi; Flutter `absensi_page_test.dart` (6). Seluruh 343 tes Flutter lulus; backend 427 lulus, 2 gagal lama (fixture lingkungan).
- **Tes perangkat:** belum. Next action: di HP (paket Professional ke atas) login Kasir, buka Lainnya > Absensi, absen masuk, tunggu beberapa menit, absen keluar; login Owner dan cek rekap memuat kedua karyawan; cek jam tampil sesuai WIB.
