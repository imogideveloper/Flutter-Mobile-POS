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
- **Temuan audit (belum dikerjakan):** **kas masuk/keluar shift (`kas_shift`) belum dikirim oleh HP** padahal server mendukungnya. Akibatnya kas yang seharusnya di server bisa berbeda dari HP. Butuh penambahan push dan tes. Status TASK-115 tetap In Progress.
- **Tes perangkat:** sebagian (server menerima 14 transaksi dan 2 shift dari HP pada 2026-11-10); retest lengkap dan pencatatan ke sheet Retest masih diperlukan.

### Hasil tes keseluruhan
Lihat ringkasan pada laporan sesi; semua tes otomatis relevan lulus.
