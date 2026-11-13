# -*- coding: utf-8 -*-
"""Perbarui tiga workbook dengan kemajuan 2026-11-10 sampai 2026-11-13, tanpa mengarang bukti.

Aturan (docs/alur_kerja.md): tidak ada status Done/QA Passed/Pass tanpa bukti perangkat; tidak ada
hasil uji, PIC, tanggal eksekusi, atau persetujuan yang dikarang; tidak ada ID TASK baru. Test case dan
skenario UAT baru berstatus Not Tested / Not Prepared (rencana uji, bukan hasil).

Jalankan: python _perbarui_progres_2026-11-13.py <Tracker.xlsx> <QA.xlsx> <UAT.xlsx>
Idempoten: dijalankan dua kali tidak menggandakan baris atau catatan.
"""
import copy
import re
import sys

import openpyxl

TGL = "2026-11-13"
MARKER = f"[{TGL}]"


# ----------------------------------------------------------------------------- utilitas
def cari_baris(ws, kolom, nilai, mulai=7):
    for r in range(mulai, ws.max_row + 1):
        if str(ws.cell(r, kolom).value) == str(nilai):
            return r
    return None


def kolom_by_header(ws, header_row=6):
    return {ws.cell(header_row, c).value: c for c in range(1, ws.max_column + 1) if ws.cell(header_row, c).value}


def tambah_catatan(sel, teks):
    """Menambahkan teks ke sel sekali saja (dikenali dari awal teksnya)."""
    lama = sel.value or ""
    if teks[:60] in lama:
        return False
    sel.value = (lama + " " if lama else "") + teks
    return True


def salin_gaya(ws, dari_baris, ke_baris):
    for c in range(1, ws.max_column + 1):
        a, b = ws.cell(dari_baris, c), ws.cell(ke_baris, c)
        if a.has_style:
            b.font = copy.copy(a.font)
            b.fill = copy.copy(a.fill)
            b.border = copy.copy(a.border)
            b.alignment = copy.copy(a.alignment)
            b.number_format = a.number_format
            b.protection = copy.copy(a.protection)
    if ws.row_dimensions[dari_baris].height:
        ws.row_dimensions[ke_baris].height = ws.row_dimensions[dari_baris].height


# ----------------------------------------------------------------------------- tracker
GAP = {
    37: "SEBAGIAN (2026-11-13): penanda margin rendah di form dan daftar produk (filter Margin rendah, lencana, peringatan di form) dengan batas per outlet di Pengaturan struk (bawaan 50% untuk F&B, migrasi 0016); HPP kosong ditandai tersendiri. Hak akses lihat harga beli mengikuti izin produk.kelola (belum ada izin khusus). Lulus tes otomatis, belum diuji di HP.",
    36: "SEBAGIAN (2026-11-14): CRUD produk, kategori, dan harga ada; kini kasir juga punya tab kategori (Semua + kategori yang berisi produk, urut menurut pengaturan kategori) yang digabung dengan pencarian. Belum: pengaturan urutan khusus tab kasir terpisah dari urutan kategori. Lulus tes otomatis, belum diuji di HP.",
    56: "SEBAGIAN (2026-11-13): promo bisa ditandai Khusus ulang tahun (gerbang paket birthday_promo, migrasi 0017); tanggal lahir pelanggan bisa diisi di form, ikut impor CSV, dan kini ikut sync ke HP (disimpan yyyymmdd); di keranjang promo itu hanya bisa dipilih bila pelanggan berulang tahun hari ini, dicabut otomatis bila pelanggan diganti; daftar pelanggan menandai yang berulang tahun hari ini. Belum: pemberitahuan otomatis ke pelanggan, penerapan otomatis tanpa dipilih kasir, validasi di server saat checkout, rentang hari (mis. seminggu). Belum diuji di HP.",
    # No IMOGI: teks temuan baru (status berubah Belum ada -> Sebagian)
    38: "SEBAGIAN (2026-11-12): Lainnya > Impor & ekspor produk: template CSV, pratinjau, simulasi dan impor (maks 500 baris) lewat POST /produk/impor. Belum: .xlsx, memperbarui produk lama, varian, stok awal, gambar. Plugin file_picker baru; lulus tes otomatis, belum diuji di HP.",
    39: "SEBAGIAN (2026-11-12): ekspor seluruh produk HP ke CSV lewat menu bagikan. Lulus tes otomatis, belum diuji di HP.",
    53: "SEBAGIAN (2026-11-13): Lainnya > Impor pelanggan: template CSV, pratinjau, simulasi dan impor lewat POST /pelanggan/impor; nomor HP dinormalkan. Belum: memperbarui pelanggan lama, poin/level. Belum diuji di HP.",
    62: "SEBAGIAN (2026-11-12): Lainnya > Absensi: absen masuk/keluar, rekap jam kerja, endpoint /absensi (waktu server, batas hari mengikuti zona perangkat). Belum: foto, lokasi, jadwal, terlambat, koreksi, offline. Belum diuji di HP.",
    67: "SEBAGIAN (2026-11-12): Lainnya > Pengeluaran (Owner/Manajer), 9 kategori F&B, rentang hari/7 hari/bulan, total dan rincian, catat dan hapus; server /pengeluaran (migrasi 0015). Belum: offline, edit, foto nota, berulang. Belum diuji di HP.",
    69: "SEBAGIAN (2026-11-12): Lainnya > Laba rugi: penjualan kotor, diskon, HPP, laba kotor, biaya operasional, laba bersih; server /laporan/laba-rugi. Rumus keputusan sementara (belanja bahan tidak dikurangkan lagi, refund belum dihitung), perlu validasi akuntan. Belum diuji di HP.",
    70: "SEBAGIAN (2026-11-12): tab PPh Final di Lainnya > Rekap pajak: estimasi tarif 0,5% x peredaran bruto per bulan; server /laporan/pph-final. Ambang bebas pajak belum dihitung, hanya estimasi. Belum diuji di HP.",
    73: "SEBAGIAN (2026-11-12): tab PPN/PB1 di Lainnya > Rekap pajak: pajak dan service dipungut per nama dan tarif; server /laporan/rekap-pajak. Belum: ekspor, PPN masukan/keluaran, pelaporan SPT. Belum diuji di HP.",
}

# Feature ID -> (catatan, TC terkait yang ditambahkan, status baru atau None)
FEAT = {
    "FEAT-060": ("Filter kategori di kasir (IMOGI no. 36): baris tab kategori di atas daftar produk kasir (Semua + kategori berisi produk, urut menurut pengaturan), digabung dengan pencarian nama/SKU; kategori yang kosong disembunyikan. Lulus tes otomatis; belum diuji di HP.", ["TC-095", "TC-096"], "Ready for QA"),
    "FEAT-073": ("Promo ulang tahun (IMOGI no. 56): tahap pertama selesai di kode (penanda pada promo, tanggal lahir pelanggan ikut sync, promo hanya bisa dipilih saat pelanggan berulang tahun hari ini). Belum divalidasi di server saat checkout dan tidak otomatis. Lulus tes otomatis; belum diuji di HP.", ["TC-092", "TC-093", "TC-094"], "In Progress"),
    "FEAT-071": ("Harga beli & margin (IMOGI no. 37): penanda margin di bawah batas per outlet (bawaan 50%, Pengaturan struk), filter dan lencana di daftar produk, peringatan di form; HPP kosong ditandai. Hak akses lihat harga beli mengikuti izin produk.kelola (keputusan sementara, docs/perlu_konfirmasi.md J1). Lulus tes otomatis; belum diuji di HP.", ["TC-089", "TC-090", "TC-091"], "In Progress"),
    "FEAT-076": ("Pengeluaran & biaya operasional: tahap pertama selesai di kode (online-only, 9 kategori, izin laporan.lihat). Lulus tes otomatis; belum diuji di HP.", ["TC-070", "TC-071", "TC-072"], "In Progress"),
    "FEAT-077": ("Laporan laba rugi: tahap pertama selesai di kode (rumus sementara, perlu validasi akuntan). Lulus tes otomatis; belum diuji di HP.", ["TC-073", "TC-074"], "In Progress"),
    "FEAT-078": ("Estimasi PPh Final 0,5% per bulan: tahap pertama selesai di kode (tarif tetap, ambang bebas pajak belum dihitung). Lulus tes otomatis; belum diuji di HP.", ["TC-076"], "In Progress"),
    "FEAT-080": ("Rekap PPN/PB1 dan service: tahap pertama selesai di kode. Lulus tes otomatis; belum diuji di HP.", ["TC-075"], "In Progress"),
    "FEAT-035": ("Impor produk via template CSV: tahap pertama selesai di kode (hanya menambah, maks 500 baris, butuh internet, plugin file_picker baru). Lulus tes otomatis; belum diuji di HP.", ["TC-077", "TC-078"], "In Progress"),
    "FEAT-034": ("Ekspor produk ke CSV (menu bagikan): tahap pertama selesai di kode. Lulus tes otomatis; belum diuji di HP.", ["TC-079"], "In Progress"),
    "FEAT-036": ("Impor pelanggan via template CSV: tahap pertama selesai di kode (hanya menambah, nomor HP dinormalkan). Lulus tes otomatis; belum diuji di HP.", ["TC-080", "TC-081"], "In Progress"),
    "FEAT-038": ("Absensi karyawan: tahap pertama selesai di kode (masuk/keluar, rekap; tanpa foto, lokasi, jadwal, status terlambat; waktu server, wajib online). Lulus tes otomatis; belum diuji di HP.", ["TC-082", "TC-083", "TC-084"], "In Progress"),
    "FEAT-041": ("Status pesanan: tambahan estimasi selesai per outlet (migrasi 0014) dan tombol Kabari pelanggan lewat WhatsApp saat Siap. Lulus tes otomatis; belum diuji di HP. Estimasi hanya satu angka per outlet.", ["TC-085", "TC-086"], None),
    "FEAT-028": ("Hak akses menu: menu Lainnya, rute, dan tab Produk/Laporan disaring menurut izin role; jalur Keluar/ganti kasir dipindah ke Lainnya. Matriks izin per menu adalah keputusan sementara (docs/perlu_konfirmasi.md B1-B7). Lulus tes otomatis; belum diuji di HP.", ["TC-087", "TC-088"], None),
    "FEAT-050": ("Sync otomatis latar depan selesai di kode (BUG-004 Ready for Retest). Tidak mencakup sync saat aplikasi tertutup penuh. Lulus tes otomatis; belum diuji di HP.", [], "Ready for QA"),
}

PAKET_FITUR = {  # kode fitur di sheet lama "Paket & Fitur" -> (status, temuan)
    "ekspor_impor": ("Sebagian", "2026-11-12: impor produk CSV dan impor pelanggan CSV ada (POST /produk/impor, /pelanggan/impor), ekspor produk CSV ada di aplikasi. Belum diuji di HP."),
    "absensi": ("Sebagian", "2026-11-12: endpoint /absensi dan layar Absensi (masuk/keluar, rekap). Tanpa foto, lokasi, jadwal. Belum diuji di HP."),
}

CATATAN_TASK = {
    "TASK-122": "2026-11-12: penjagaan izin menu Lainnya, rute, dan tab Produk/Laporan; jalur Keluar/ganti kasir di Lainnya (tes otomatis lulus). Belum diuji di HP; matriks izin perlu konfirmasi lead.",
    "TASK-111": "2026-11-13: tidak ada perubahan; menunggu uji HP (TC-038).",
}


def perbarui_tracker(path):
    wb = openpyxl.load_workbook(path)
    n = {"gap": 0, "feat": 0, "paket": 0, "task": 0}

    ws = wb["Gap Imogi"]
    kol = kolom_by_header(ws)
    for no, teks in GAP.items():
        r = cari_baris(ws, kol["No"], no)
        if r is None:
            print("  PERINGATAN: Gap Imogi no", no, "tidak ditemukan")
            continue
        if ws.cell(r, kol["Status di Aplikasi"]).value != "Sebagian":
            n["gap"] += 1
        ws.cell(r, kol["Status di Aplikasi"]).value = "Sebagian"
        ws.cell(r, kol["Temuan"]).value = teks

    ws = wb["Feature Inventory"]
    kol = kolom_by_header(ws)
    for fid, (catatan, tcs, status) in FEAT.items():
        r = cari_baris(ws, kol["Feature ID"], fid)
        if r is None:
            print("  PERINGATAN:", fid, "tidak ditemukan")
            continue
        if status and ws.cell(r, kol["Current Status"]).value != status:
            ws.cell(r, kol["Current Status"]).value = status
            n["feat"] += 1
        if tambah_catatan(ws.cell(r, kol["Notes"]), f"{MARKER} {catatan}"):
            n["feat"] += 1
        sel_tc = ws.cell(r, kol["Related Test Case ID"])
        ada = [t.strip() for t in str(sel_tc.value or "").replace("None", "").split(",") if t.strip()]
        for tc in tcs:
            if tc not in ada:
                ada.append(tc)
        sel_tc.value = ", ".join(ada) if ada else sel_tc.value

    ws = wb["Paket & Fitur"]
    kol = kolom_by_header(ws)
    for kode, (status, temuan) in PAKET_FITUR.items():
        r = cari_baris(ws, kol["Kode Fitur"], kode)
        if r is None:
            print("  PERINGATAN: Paket & Fitur", kode, "tidak ditemukan")
            continue
        ws.cell(r, kol["Status Implementasi"]).value = status
        ws.cell(r, kol["Temuan Kode"]).value = temuan
        n["paket"] += 1

    ws = wb["Task Tracker"]
    kol = kolom_by_header(ws)
    for tid, teks in CATATAN_TASK.items():
        r = cari_baris(ws, kol["Task ID"], tid)
        if r is None:
            print("  PERINGATAN:", tid, "tidak ditemukan")
            continue
        if tambah_catatan(ws.cell(r, kol["Notes"]), teks):
            n["task"] += 1

    ws = wb["Instructions"]
    for r in range(1, ws.max_row + 1):
        if ws.cell(r, 1).value == "Gap Imogi" and "2026-11-13" not in str(ws.cell(r, 2).value):
            ws.cell(r, 2).value = str(ws.cell(r, 2).value) + (
                " Diperbarui 2026-11-13: 8 fitur berubah dari Belum ada ke Sebagian (no. 38, 39, 53, 62, 67, 69, 70, 73); "
                "belum ada yang Lengkap karena belum ada uji HP."
            )
    wb.save(path)
    print(f"{path}: {n}")


# ----------------------------------------------------------------------------- QA
H, M, L, C = "High", "Medium", "Low", "Critical"
TC_BARU = [
    # id, fitur, modul, skenario, deskripsi, prasyarat, langkah, data, hasil harapan, prioritas, tipe
    ("TC-070", "FEAT-076", "Akuntansi", "Catat pengeluaran dan lihat total", "Pemilik mencatat dua pengeluaran dan melihat total hari ini.",
     "Paket Starter ke atas; login Owner; internet aktif.", "1. Lainnya > Pengeluaran\n2. Tambah: Belanja bahan Rp 150.000\n3. Tambah: Gas LPG Rp 25.000\n4. Lihat rentang Hari ini",
     "Dua pengeluaran di atas", "Total Rp 175.000; rincian per kategori benar; kedua baris tampil di daftar.", H, "Functional"),
    ("TC-071", "FEAT-076", "Akuntansi", "Kasir tidak melihat menu Pengeluaran", "Menu keuangan tidak tampil untuk peran Kasir.",
     "Login Kasir.", "1. Lainnya", "-", "Menu Pengeluaran dan Laba rugi tidak tampil.", H, "Negative"),
    ("TC-072", "FEAT-076", "Akuntansi", "Pengeluaran saat tidak ada internet", "Fitur online-only memberi pesan jelas.",
     "Login Owner; matikan internet.", "1. Lainnya > Pengeluaran", "-", "Pesan butuh internet dan tombol Coba lagi; tidak crash.", M, "Negative"),
    ("TC-073", "FEAT-077", "Akuntansi", "Laba rugi sesuai hitungan manual", "Angka laba rugi cocok dengan perhitungan tangan.",
     "Paket Professional ke atas; produk harga 15.000 dan HPP 6.000; internet aktif.",
     "1. Jual 2 produk itu\n2. Catat pengeluaran: gas 5.000, sewa 3.000, belanja bahan 10.000\n3. Lainnya > Laba rugi > Hari ini",
     "Lihat langkah", "Penjualan bersih 30.000; HPP 12.000; laba kotor 18.000; biaya operasional 8.000; laba bersih 10.000; belanja bahan 10.000 tidak dikurangkan lagi.", H, "Functional"),
    ("TC-074", "FEAT-077", "Akuntansi", "Laba rugi terkunci di paket di bawah Professional", "Paket Gratis/Starter tidak membuka laporan.",
     "Paket Starter; login Owner.", "1. Lainnya", "-", "Menu Laba rugi terkunci atau memberi pesan paket; server menolak 403.", M, "Negative"),
    ("TC-075", "FEAT-080", "Akuntansi", "Rekap PB1 dan service cocok dengan struk", "Total pajak dan service di rekap sama dengan jumlah di struk.",
     "Paket Professional ke atas; pajak PB1 dan service aktif; internet aktif.", "1. Buat dua transaksi\n2. Lainnya > Rekap pajak > PPN / PB1",
     "-", "Total pajak dan service sama dengan jumlah di struk; service dipisah dari pajak.", H, "Functional"),
    ("TC-076", "FEAT-078", "Akuntansi", "Estimasi PPh Final 0,5%", "Estimasi sama dengan 0,5% dari penjualan sebelum pajak.",
     "Paket Professional ke atas; ada transaksi di dua bulan.", "1. Lainnya > Rekap pajak > PPh Final > Bulan ini", "Omzet 45.000 (contoh)",
     "Estimasi Rp 225 untuk omzet 45.000; rincian per bulan benar; catatan batas tampil.", M, "Functional"),
    ("TC-077", "FEAT-035", "Produk", "Impor produk dari CSV", "Produk dari template muncul setelah impor dan sync.",
     "Paket Starter ke atas; login Owner; internet aktif.",
     "1. Lainnya > Impor & ekspor produk > Bagikan template\n2. Isi di Excel dan simpan sebagai CSV\n3. Pilih berkas CSV > Periksa dulu > Impor\n4. Buka daftar Produk",
     "Template dengan 3 produk dan 1 kategori baru", "Ringkasan benar; produk dan kategori baru muncul di daftar setelah sync; harga dan HPP sesuai.", H, "Functional"),
    ("TC-078", "FEAT-035", "Produk", "Baris salah dan SKU ganda ditolak", "Baris bermasalah ditolak dengan alasan, baris lain tetap masuk.",
     "Berkas CSV berisi satu baris tanpa nama, satu SKU yang sudah ada, dua baris valid.", "1. Pilih berkas > Periksa dulu > Impor", "-",
     "Baris salah ditolak dengan alasan jelas; dua baris valid tersimpan.", M, "Negative"),
    ("TC-079", "FEAT-034", "Produk", "Ekspor produk dapat dibuka di Excel", "CSV hasil ekspor terbaca di Excel/Sheets.",
     "Ada beberapa produk dengan kategori.", "1. Lainnya > Impor & ekspor produk > Ekspor produk (CSV)\n2. Buka berkas yang dibagikan", "-",
     "Kolom dan nilai benar, nama bermakna koma tidak merusak kolom.", L, "Functional"),
    ("TC-080", "FEAT-036", "Pelanggan", "Impor pelanggan dengan format nomor berbeda", "Nomor 0812, 62812, dan +62812 diperlakukan sama.",
     "Paket Professional ke atas; login Owner; internet aktif.", "1. Lainnya > Impor pelanggan > Bagikan template\n2. Isi 3 pelanggan dengan format nomor berbeda\n3. Impor",
     "-", "Pelanggan tersimpan dengan nomor ternormalisasi; muncul di menu Pelanggan setelah sync.", M, "Functional"),
    ("TC-081", "FEAT-036", "Pelanggan", "Nomor HP ganda ditolak", "Nomor yang sudah terdaftar tidak diimpor lagi.",
     "Sudah ada pelanggan bernomor 0812xxxx.", "1. Impor berkas berisi nomor yang sama dalam format +62", "-", "Baris ditolak dengan alasan 'sudah terdaftar'.", M, "Negative"),
    ("TC-082", "FEAT-038", "Karyawan", "Absen masuk dan keluar", "Karyawan mencatat jam masuk dan keluar sendiri.",
     "Paket Professional ke atas; login Kasir; internet aktif.", "1. Lainnya > Absensi > Absen masuk\n2. Tunggu beberapa menit\n3. Absen keluar", "-",
     "Status 'Sedang masuk sejak jam X' lalu 'Belum absen masuk'; riwayat memuat durasi.", H, "Functional"),
    ("TC-083", "FEAT-038", "Karyawan", "Kasir hanya melihat absensi sendiri", "Pemilik melihat semua, kasir hanya miliknya.",
     "Dua karyawan sudah absen.", "1. Login Kasir > Absensi\n2. Login Owner > Absensi", "-",
     "Kasir hanya melihat dirinya; Owner melihat rekap kedua karyawan.", M, "Negative"),
    ("TC-084", "FEAT-038", "Karyawan", "Jam absen sesuai WIB", "Jam tampil sesuai zona waktu perangkat dan batas hari benar.",
     "HP berzona WIB; absen masuk pagi hari.", "1. Absen masuk pukul 06:00\n2. Lihat rentang Hari ini", "-",
     "Jam tampil 06:00 dan absen masuk ke rekap hari ini (bukan hari kemarin).", M, "Functional"),
    ("TC-085", "FEAT-041", "Dapur", "Estimasi selesai pesanan", "Jam estimasi dan keterlambatan tampil di Status pesanan.",
     "Paket yang memiliki Status pesanan; login Owner.", "1. Pengaturan struk > isi Estimasi 15 menit > Simpan\n2. Buat pesanan\n3. Buka Status pesanan, tunggu lewat 15 menit", "15 menit",
     "Tampil 'Estimasi selesai HH:mm', lalu 'Terlambat N mnt'; hilang setelah Siap.", M, "Functional"),
    ("TC-086", "FEAT-041", "Dapur", "Kabari pelanggan lewat WhatsApp saat siap", "Tombol membuka WhatsApp ke nomor pelanggan dengan pesan siap.",
     "Pesanan dengan pelanggan bernomor HP; WhatsApp terpasang.", "1. Majukan pesanan sampai Siap\n2. Ketuk Kabari pelanggan (WhatsApp)", "-",
     "WhatsApp terbuka ke nomor pelanggan dengan pesan berisi nomor antrian; tombol tidak muncul bila pelanggan tanpa nomor.", M, "Functional"),
    ("TC-087", "FEAT-028", "Karyawan", "Menu Lainnya sesuai peran", "Kasir tidak melihat pengaturan milik pemilik.",
     "Ada akun Owner dan Kasir.", "1. Login Kasir > Lainnya\n2. Login Owner > Lainnya", "-",
     "Kasir tidak melihat Stok, Pajak, Karyawan, Paket langganan, tab Produk dan Laporan; Owner melihat semuanya.", H, "Functional"),
    ("TC-088", "FEAT-028", "Karyawan", "Keluar/ganti kasir dari Lainnya", "Kasir dapat keluar akun tanpa tab Produk.",
     "Login Kasir.", "1. Lainnya > Keluar / ganti kasir", "-", "Kembali ke layar pilih pengguna; akun berikutnya bisa masuk.", H, "Functional"),
    ("TC-089", "FEAT-071", "Produk", "Penanda margin rendah di daftar dan form produk", "Produk dengan margin di bawah batas ditandai.",
     "Login Owner; produk A harga 18.000 HPP 7.000, produk B harga 10.000 HPP 7.000.", "1. Lainnya > Pengaturan struk: pastikan Batas margin 50\n2. Buka tab Produk\n3. Ketuk filter Margin rendah\n4. Buka produk B", "Produk A dan B",
     "Produk B tampil dengan lencana Margin rendah 30% (batas 50%) dan satu-satunya di filter; produk A tidak ditandai; form B menampilkan peringatan di bawah batas.", H, "Functional"),
    ("TC-090", "FEAT-071", "Produk", "Batas margin per outlet dapat diubah dan tersinkron", "Batas baru langsung dipakai penanda.",
     "Login Owner; internet aktif.", "1. Pengaturan struk: ubah Batas margin menjadi 25, Simpan\n2. Buka tab Produk", "Batas 25",
     "Produk B (margin 30%) tidak lagi ditandai; nilai 25 bertahan setelah sync dan buka ulang aplikasi.", M, "Functional"),
    ("TC-091", "FEAT-071", "Produk", "HPP kosong ditandai, bukan margin 100 persen", "Produk tanpa HPP diberi penanda tersendiri.",
     "Produk harga 3.000 tanpa HPP.", "1. Buka tab Produk", "-", "Tampil HPP belum diisi; produk tidak masuk filter Margin rendah.", L, "Negative"),
]

TC_BARU += [
    ("TC-095", "FEAT-060", "Kasir", "Tab kategori menyaring produk di kasir", "Kasir memilih kategori untuk mempersempit produk.",
     "Shift terbuka; ada kategori Minuman dan Makanan berisi produk, satu kategori kosong, satu produk tanpa kategori.",
     "1. Buka tab Kasir\n2. Ketuk tab Makanan\n3. Ketuk tab Minuman\n4. Ketuk Semua", "-",
     "Tab hanya menampilkan Semua dan kategori yang berisi produk; ketuk kategori hanya menampilkan produknya; Semua menampilkan seluruhnya termasuk yang tanpa kategori.", H, "Functional"),
    ("TC-096", "FEAT-060", "Kasir", "Tab kategori digabung dengan pencarian", "Pencarian bekerja di dalam kategori terpilih.",
     "Sama dengan TC-095.", "1. Ketuk tab Minuman\n2. Ketik nama produk Makanan di kolom cari\n3. Ketik nama produk Minuman", "-",
     "Produk di luar kategori tidak muncul walau namanya cocok; produk di dalam kategori muncul.", M, "Functional"),
    ("TC-092", "FEAT-073", "Pelanggan", "Tanggal lahir pelanggan tersimpan dan ikut sync", "Tanggal lahir diisi di form dan tetap ada setelah sync.",
     "Login Owner; internet aktif.", "1. Menu Pelanggan > edit pelanggan > Pilih tanggal lahir > Simpan\n2. Lainnya > Sync\n3. Buka ulang pelanggan itu", "Tanggal lahir hari ini (bulan dan tanggal)",
     "Tanggal lahir tampil kembali dengan benar; pelanggan itu ditandai Ulang tahun hari ini di daftar.", M, "Functional"),
    ("TC-093", "FEAT-073", "Pelanggan", "Promo ulang tahun hanya bisa dipilih saat pelanggan berulang tahun", "Kasir memilih promo ulang tahun untuk pelanggan yang berulang tahun hari ini.",
     "Paket Professional ke atas; promo ditandai Khusus ulang tahun; pelanggan A berulang tahun hari ini, pelanggan B tidak.",
     "1. Buat keranjang, pilih pelanggan A, buka Promo\n2. Pilih Diskon Ulang Tahun, lanjut bayar\n3. Ulangi dengan pelanggan B", "-",
     "Untuk A promo bisa dipilih dan diskon terpotong di total; untuk B promo tampak nonaktif dengan keterangan hanya untuk yang berulang tahun.", H, "Functional"),
    ("TC-094", "FEAT-073", "Pelanggan", "Promo ulang tahun dicabut bila pelanggan diganti dan terkunci di paket bawah", "Penjaga promo dan gerbang paket bekerja.",
     "Keranjang berisi promo ulang tahun untuk pelanggan A; paket Pro untuk uji gerbang.", "1. Ganti pelanggan A dengan B\n2. Lihat total\n3. Di paket Pro, buat promo dan nyalakan Khusus ulang tahun", "-",
     "Promo hilang dari total saat pelanggan diganti; di paket Pro server menolak dengan pesan fitur terkunci.", M, "Negative"),
]

NOTE_TC = "Diusulkan 2026-11-13 dari cara uji fitur; fitur lulus tes otomatis tetapi belum dijalankan di HP. ID berurutan; QA/lead boleh menyesuaikan."


def perbarui_qa(path):
    wb = openpyxl.load_workbook(path)
    ws = wb["Test Case"]
    kol = kolom_by_header(ws)
    tambah = 0
    for tc in TC_BARU:
        if cari_baris(ws, kol["Test Case ID"], tc[0]) is not None:
            continue
        r = ws.max_row + 1
        salin_gaya(ws, r - 1, r)
        nilai = {
            "Test Case ID": tc[0], "Related Feature ID": tc[1], "Module": tc[2], "Test Scenario": tc[3],
            "Test Case Description": tc[4], "Preconditions": tc[5], "Test Steps": tc[6], "Test Data": tc[7],
            "Expected Result": tc[8], "Priority": tc[9], "Test Type": tc[10], "Platform": "Android",
            "Test Status": "Not Tested", "Notes": NOTE_TC,
        }
        for nama, v in nilai.items():
            ws.cell(r, kol[nama]).value = v
        tambah += 1

    # TC-064 (status pesanan): catat kemajuan
    r = cari_baris(ws, kol["Test Case ID"], "TC-064")
    if r is not None:
        tambah_catatan(ws.cell(r, kol["Notes"]),
                       f"{MARKER} fitur bertambah: estimasi selesai dan tombol WhatsApp saat siap (TC-085, TC-086). Belum diuji di HP.")

    ws = wb["Instructions"]
    for r in range(1, ws.max_row + 1):
        if ws.cell(r, 1).value == "Test Case" and re.search(r"TC-070 sampai TC-0\d\d", str(ws.cell(r, 2).value)):
            # Perluas rentang pada kalimat yang sudah ada (jangan menambah kalimat kedua).
            ws.cell(r, 2).value = re.sub(r"TC-070 sampai TC-0\d\d", "TC-070 sampai TC-096", str(ws.cell(r, 2).value))
        elif ws.cell(r, 1).value == "Test Case" and "TC-096" not in str(ws.cell(r, 2).value):
            ws.cell(r, 2).value = str(ws.cell(r, 2).value) + (
                " TC-070 sampai TC-096 ditambahkan 2026-11-13 (diusulkan, Not Tested) untuk fitur baru: pengeluaran, laba rugi, "
                "rekap pajak, impor/ekspor produk, impor pelanggan, absensi, estimasi dan WhatsApp status pesanan, hak akses menu. "
                "Belum ada yang dijalankan di HP."
            )
    wb.save(path)
    print(f"{path}: {tambah} test case ditambahkan")


# ----------------------------------------------------------------------------- UAT
UAT_BARU = [
    ("UAT-016", "FEAT-076", "Akuntansi", "Pemilik memantau biaya dan laba bulanan",
     "Pemilik mencatat biaya harian lalu melihat laba rugi bulan berjalan.",
     "Paket Professional ke atas; ada transaksi bulan ini; HPP produk terisi.",
     "1. Catat pengeluaran gas, sewa, belanja bahan\n2. Buka Laba rugi > Bulan ini",
     "Pemilik memahami laba atau rugi bulan ini dari satu layar.",
     "High", "Laba bersih = penjualan bersih - HPP - biaya operasional; pemilik/akuntan mengonfirmasi rumus sudah sesuai (belanja bahan tidak dihitung dua kali)."),
    ("UAT-017", "FEAT-038", "Karyawan", "Karyawan absen masuk dan keluar",
     "Karyawan mencatat kehadiran, pemilik melihat rekap jam kerja.",
     "Paket Professional ke atas; akun karyawan.",
     "1. Karyawan absen masuk saat mulai kerja\n2. Absen keluar saat pulang\n3. Pemilik membuka rekap",
     "Jam kerja tiap karyawan tercatat dan terbaca pemilik.",
     "Medium", "Jam sesuai WIB; rekap sama dengan kehadiran sebenarnya; pemilik menyatakan cukup tanpa foto/lokasi atau meminta tambahan."),
    ("UAT-018", "FEAT-035", "Produk", "Pemilik memasukkan banyak produk dari template",
     "Pemilik mengisi template CSV dan mengimpor puluhan produk sekaligus.",
     "Paket Starter ke atas; daftar produk dalam Excel.",
     "1. Bagikan template\n2. Salin data produk ke template, simpan CSV\n3. Impor",
     "Puluhan produk masuk tanpa mengetik satu per satu.",
     "High", "Jumlah produk di aplikasi sama dengan berkas; kategori terbentuk; baris salah dijelaskan; pemilik menyatakan alurnya mudah."),
    ("UAT-019", "FEAT-041", "Dapur", "Pelanggan dikabari saat pesanan siap",
     "Kasir/barista mengabari pelanggan lewat WhatsApp saat pesanan siap.",
     "Pesanan dengan pelanggan bernomor HP; paket Status pesanan.",
     "1. Majukan pesanan sampai Siap\n2. Ketuk Kabari pelanggan",
     "Pelanggan menerima pesan bahwa pesanan siap diambil.",
     "Medium", "Pesan terkirim ke nomor yang benar dengan isi yang wajar; pemilik memutuskan apakah pengiriman otomatis dibutuhkan."),
]


def perbarui_uat(path):
    wb = openpyxl.load_workbook(path)
    ws = wb["UAT Scenario"]
    kol = kolom_by_header(ws)
    tambah = 0
    for u in UAT_BARU:
        if cari_baris(ws, kol["UAT ID"], u[0]) is not None:
            continue
        r = ws.max_row + 1
        salin_gaya(ws, r - 1, r)
        nilai = {
            "UAT ID": u[0], "Related Feature ID": u[1], "Module": u[2], "Business Scenario": u[3],
            "Scenario Description": u[4], "Preconditions": u[5], "User Steps": u[6],
            "Expected Business Result": u[7], "Priority": u[8], "Acceptance Criteria": u[9],
            "UAT Status": "Not Prepared",
            "Notes": "Draf 2026-11-13 untuk fitur baru; belum disetujui lead dan belum dijalankan.",
        }
        for nama, v in nilai.items():
            ws.cell(r, kol[nama]).value = v
        tambah += 1

    ws = wb["Instructions"]
    for r in range(1, ws.max_row + 1):
        if ws.cell(r, 1).value == "UAT Scenario" and "UAT-019" not in str(ws.cell(r, 2).value):
            ws.cell(r, 2).value = str(ws.cell(r, 2).value) + (
                " UAT-016 sampai UAT-019 ditambahkan 2026-11-13 sebagai draf (Not Prepared) untuk fitur baru; "
                "belum disetujui lead."
            )
    wb.save(path)
    print(f"{path}: {tambah} skenario ditambahkan")


if __name__ == "__main__":
    tracker, qa, uat = sys.argv[1:4]
    perbarui_tracker(tracker)
    perbarui_qa(qa)
    perbarui_uat(uat)
