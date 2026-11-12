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
