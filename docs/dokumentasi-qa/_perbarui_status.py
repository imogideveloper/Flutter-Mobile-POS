# -*- coding: utf-8 -*-
"""Perbarui status BUG/TASK di workbook berdasarkan bukti nyata, tanpa mengubah struktur sheet.

Jalankan: python _perbarui_status.py <QA.xlsx> <Tracker.xlsx>
Hanya mengisi sel Status/Fixed Date/Progress/Notes pada baris dengan ID yang cocok.
"""
import datetime
import sys

import openpyxl

TANGGAL = datetime.datetime(2026, 11, 10)

# (ID, {nama kolom: nilai}); catatan DITAMBAHKAN ke sel Notes yang sudah ada.
BUG = {
    "BUG-009": {
        "Status": "Ready for Retest",
        "Fixed Date": TANGGAL,
        "_catatan": " 2026-11-10: tombol 'Masuk dengan PIN karyawan' kini hanya tampil bila ada layar PIN untuk dituju (halaman OTP "
                    "dibuka dari LoginPage di perangkat yang sudah dipasangkan, tombol kembali ke pilih pengguna + PIN). Di perangkat "
                    "baru tombol disembunyikan dan diganti petunjuk bahwa karyawan masuk dengan PIN setelah perangkat dipasangkan "
                    "pemilik. Tes otomatis lulus (otp_login_pin_button_test.dart). Login PIN pada perangkat yang sudah dipasangkan "
                    "sudah dicakup login_flow_test.dart tetapi BELUM diuji di HP; login PIN karyawan asal server dan hak akses per role "
                    "belum diaudit. Belum Closed.",
    },
    "BUG-014": {
        "Status": "Ready for Retest",
        "Fixed Date": TANGGAL,
        "_catatan": " 2026-11-10: tombol Refund kini memeriksa dulu apakah transaksi sudah tersinkron; bila belum, muncul ajakan "
                    "'Sinkronkan sekarang' SEBELUM PIN diminta, lalu refund dilanjutkan jika sync berhasil. Halaman refund juga "
                    "menampilkan petunjuk sinkron untuk respons 404. Tes otomatis lulus (refund_belum_sync_test.dart, refund_flow_test.dart). "
                    "Belum diuji di HP; retest: buat transaksi lalu refund sebelum sync (TC-023). Tidak ada TASK terpisah di Task Tracker.",
    },
    "BUG-015": {
        "Status": "Ready for Retest",
        "Fixed Date": TANGGAL,
        "_catatan": " 2026-11-10: nama metode bayar kini dicari di tabel metode_bayar lokal (id UUID dari server) lewat "
                    "namaMetodeBayarProvider; dipakai di daftar riwayat, detail transaksi, dan ringkasan metode di laporan. "
                    "Split tetap 'Campuran'; id placeholder lama tetap dikenali. Tes otomatis lulus (test/metode_bayar_label_test.dart). "
                    "Belum diuji di HP; retest: bayar tunai dan transfer lalu cek Riwayat (TC-056).",
    },
    "BUG-012": {
        "Status": "Ready for Retest",
        "Fixed Date": TANGGAL,
        "_catatan": " 2026-11-10: server hanya menolak saat logo/struk ringkas/antrean BENAR-BENAR berubah menjadi aktif "
                    "(routers/outlet.py); klien mengirim ulang seluruh pengaturan sehingga tampil_logo=true bawaan tidak lagi "
                    "menggagalkan penyimpanan. Tes otomatis lulus (test_pengaturan_struk.py). Aturan paket tidak berubah. "
                    "Belum diuji di HP; retest: simpan pengaturan non-logo pada paket Gratis.",
    },
}
TASK = {
    "TASK-122": {
        "Status": "Review",
        "Progress (%)": 0.6,
        "_catatan": " 2026-11-10: tombol mati diperbaiki dan lulus tes otomatis; menunggu uji di HP (TC-052). Sisa Fase 4: reproduksi "
                    "login PIN karyawan asal server di HP dan audit hak akses per role (kasir tidak boleh fungsi owner).",
    },
    "TASK-127": {
        "Status": "Review",
        "Progress (%)": 0.8,
        "_catatan": " 2026-11-10: kode diperbaiki dan lulus tes otomatis; menunggu uji di HP (TC-056).",
    },
    "TASK-115": {
        "_catatan": " 2026-11-10: kas masuk/keluar shift kini ikut dikirim HP bersama shiftnya (idempoten per id); kas yang "
                    "seharusnya dihitung ulang server setelah kas masuk/keluar dan transaksi tersimpan. Tes otomatis lulus "
                    "(backend dan Flutter). Belum diuji di HP; progress tetap 90% sampai retest sync di perangkat.",
    },
    "TASK-125": {
        "Status": "Review",
        "Progress (%)": 0.8,
        "_catatan": " 2026-11-10: kode diperbaiki dan lulus tes otomatis; menunggu uji di HP (TC-054).",
    },
}


def cari_header(ws, nama_id):
    for r in range(1, 12):
        if ws.cell(r, 1).value == nama_id:
            return r
    raise SystemExit(f"header '{nama_id}' tidak ditemukan di {ws.title}")


def terapkan(ws, nama_id, data, kolom_catatan):
    h = cari_header(ws, nama_id)
    kolom = {ws.cell(h, c).value: c for c in range(1, ws.max_column + 1)}
    n = 0
    for r in range(h + 1, ws.max_row + 1):
        kode = ws.cell(r, 1).value
        if kode in data:
            for nama, nilai in data[kode].items():
                if nama == "_catatan":
                    sel = ws.cell(r, kolom[kolom_catatan])
                    teks = sel.value or ""
                    # Idempoten: bersihkan catatan yang terlanjur dobel, jangan menambah yang sama dua kali.
                    while nilai in teks and teks.count(nilai) > 1:
                        teks = teks.replace(nilai, "", 1)
                    if nilai not in teks:
                        teks += nilai
                    sel.value = teks
                else:
                    ws.cell(r, kolom[nama]).value = nilai
            n += 1
    print(ws.title, n, "baris diperbarui")


def main(qa: str, tracker: str) -> None:
    wb = openpyxl.load_workbook(qa)
    terapkan(wb["Bug Tracker"], "Bug ID", BUG, "Notes")
    wb.save(qa)
    wb = openpyxl.load_workbook(tracker)
    terapkan(wb["Task Tracker"], "Task ID", TASK, "Notes")
    wb.save(tracker)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
