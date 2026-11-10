# -*- coding: utf-8 -*-
"""Perbarui catatan kemajuan di POS Project Tracker.xlsx tanpa mengubah struktur sheet.

Skrip pembangkit lama (build_docs.py) sudah hilang bersama folder sementara, jadi
pembaruan dilakukan langsung pada sel teks: tiap pasangan (lama, baru) diganti di
semua sheet, lalu jumlah penggantian dicetak. Jalankan: python _perbarui_catatan.py <berkas.xlsx>
"""
import sys

import openpyxl

PENGGANTI = [
    # Gap Imogi dan Feature Inventory
    ("Belum ada pilihan kategori yang masuk tiket, tombol auto-print terpisah, cetak ulang dari riwayat, dan uji di printer (belum ada perangkat).",
     "KEMAJUAN 2026-11-10: kategori bisa dikeluarkan dari tiket (saklar 'Masuk tiket dapur' di form kategori, migrasi 0013) dan tiket bisa dicetak ulang dari detail riwayat. Belum ada tombol auto-print terpisah, tiket per stasiun, dan uji di printer (belum ada perangkat)."),
    ("Belum ada estimasi selesai, pesan WhatsApp saat siap, tahap Diantar untuk pesanan antar pada alur standar, dan uji di HP.",
     "KEMAJUAN 2026-11-10: pesanan bertipe antar otomatis memuat tahap Diantar. Belum ada estimasi selesai, pesan WhatsApp saat siap, dan uji di HP."),
    ("Belum ada pengaturan awalan dan angka awal, panggilan suara, layar antrian, dan nama di layar antrian. Belum diuji di HP.",
     "KEMAJUAN 2026-11-10: awalan dan angka awal bisa diatur per outlet di Pengaturan struk (migrasi 0012). Belum ada panggilan suara, layar antrian, dan nama di layar antrian. Belum diuji di HP."),
    # Feature Inventory (kalimat KEMAJUAN lama)
    ("belum ada pilihan kategori, cetak ulang dari riwayat, dan uji printer.",
     "KEMAJUAN 2026-11-10: kategori bisa dikeluarkan dari tiket dan tiket bisa dicetak ulang dari riwayat; belum ada uji printer."),
    ("belum ada estimasi selesai, WA saat siap, tahap Diantar standar, dan uji HP.",
     "KEMAJUAN 2026-11-10: tahap Diantar untuk pesanan bertipe antar sudah ada; belum ada estimasi selesai, WA saat siap, dan uji HP."),
    ("belum ada pengaturan awalan/angka awal, suara, layar antrian, dan uji di HP.",
     "KEMAJUAN 2026-11-10: awalan dan angka awal sudah bisa diatur; belum ada suara, layar antrian, dan uji di HP."),
    # Task Tracker
    ("Sisa: estimasi selesai, WA saat siap, tahap Diantar, kategori di tiket, cetak ulang dari riwayat, uji printer.",
     "2026-11-10: tahap Diantar, kategori di tiket, dan cetak ulang dari riwayat selesai di kode. Sisa: estimasi selesai, WA saat siap, uji printer."),
    ("Sisa: awalan dan angka awal, uji di HP.",
     "2026-11-10: awalan dan angka awal selesai di kode. Sisa: uji di HP."),
]


def main(path: str) -> None:
    wb = openpyxl.load_workbook(path)
    total = 0
    for ws in wb:
        for row in ws.iter_rows():
            for cell in row:
                v = cell.value
                if isinstance(v, str) and not v.startswith("="):
                    for lama, baru in PENGGANTI:
                        if lama in v:
                            v = v.replace(lama, baru)
                            total += 1
                    if v != cell.value:
                        cell.value = v
    wb.save(path)
    print(f"{path}: {total} penggantian")


if __name__ == "__main__":
    main(sys.argv[1])
