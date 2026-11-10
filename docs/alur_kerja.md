# Alur kerja proyek IMOGI POS F&B

Ringkasan arahan pemilik proyek (dikutip dari "Instruksi audit dan pelaksanaan proyek", ditambahkan 2026-11-10).
Berlaku untuk siapa pun (manusia atau agen) yang melanjutkan pekerjaan. Tiap penyimpangan dicatat di
`docs/audit_alur_kerja.md`, bukan dipilih diam-diam.

## Sumber utama
1. `POS Project Tracker.xlsx`, `POS QA & Testing.xlsx`, `POS UAT & Release.xlsx` (di `docs/dokumentasi-qa/`)
2. `Panduan-Menu-Pengaturan-IMOGI-POS.pdf` dan `IMOGI POS Menu & Fitur.html`
3. Temuan uji manual pengguna

## Prinsip
- Audit kode dan dokumen **sebelum** mengubah apa pun; periksa apakah fitur sudah ada atau sedang dibangun.
- Pertahankan ID TASK, FEAT, TC, RUN, BUG, RETEST, UAT, REL. ID baru hanya untuk temuan atau pekerjaan baru.
- Jangan hapus task, bug, test case, atau catatan lama tanpa alasan dan jejak.
- **Done / QA Passed / Closed hanya dengan bukti.** Kode selesai bukan bukti. Tes otomatis bukan pengganti uji perangkat.
- Jangan mengarang hasil, evidence, tanggal, PIC, approval, atau status.
- Fitur yang terkunci paket bukan bug sebelum aturan paket diperiksa.
- Jangan ubah requirement, Release Scope, atau acceptance criteria sepihak. Butuh perangkat, akun, atau keputusan lead: tandai Blocked dan jelaskan.
- Konflik antara tracker, QA, UAT, kode, dan temuan manual: **dokumentasikan**, jangan pilih salah satu diam-diam.
- Tidak ada tindakan produksi, transaksi nyata, perubahan data pelanggan, atau release tanpa otorisasi.
- Prioritas: akurasi transaksi, stok, pembayaran, login, dan sinkronisasi **sebelum** fitur F&B baru.

## Urutan fase
| Fase | Prioritas | Fokus |
|---|---|---|
| 1 | P0 | Validasi requirement dan Release Scope (TASK-103, 104, 105) |
| 2 | P0 | Alur kasir dan kontrol jumlah (FEAT-002, 005, 058; TASK-107, 114; BUG-021) |
| 3 | P0 | Integritas transaksi, stok, sync (BUG-013, 018, 019, 020; TASK-111, 115) |
| 4 | P0/P1 | Login dan hak akses (FEAT-001; TC-001..003; BUG-009; TASK-122) |
| 5 | P1 | Pengaturan outlet dan batas paket (BUG-012; FEAT-012; TASK-125) |
| 6 | P1 | Pembayaran, QRIS, refund (BUG-014, 015) |
| 7 | P1 | Struk dan printer (FEAT-010; TASK-108) |
| 8 | P1 | UAT (15 skenario, approval nyata) |
| 9 | P2 | Persiapan release (TASK-109, 110, 112; REL-001..038) |

## Status
- Task: Backlog, To Do, In Progress, Review, Done, Blocked, Overdue.
- Testing: bedakan Belum diuji, Lulus tes otomatis, Gagal, Ready for Retest, Retest Passed, Blocked, QA Passed.
- UAT: Pass, Fail, Blocked, Not Tested. Approval diisi manual oleh pihak berwenang.
- Jangan menambah status baru tanpa memeriksa konsistensi workbook.
- Data dummy (BUG-901..903, RUN-901..903, RETEST-901, UAT-RUN-901/902) **bukan hasil nyata**; abaikan atau hapus sesuai petunjuk workbook.

## Format laporan per task
Task ID, Related Feature ID, Related Bug ID, Phase, kondisi awal, temuan, perubahan, file kode, alasan,
test case, hasil tes otomatis, hasil tes perangkat, evidence, dependency, status akhir, progress, risiko, next action.
Bila terhambat: hambatan, data/perangkat yang dibutuhkan, keputusan yang dibutuhkan, pihak pemutus, task terdampak.

## Laporan akhir sesi
A. Ringkasan eksekutif, B. Prioritas task, C. Bug (ID, severity, reproduksi, penyebab, perbaikan, retest, status, evidence),
D. QA, E. UAT, F. Kesiapan release (checklist, Critical/High Open, UAT pass rate, approval, keputusan), G. Next actions.
