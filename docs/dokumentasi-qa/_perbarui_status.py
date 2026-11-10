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
                    sel.value = (sel.value or "") + nilai
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
