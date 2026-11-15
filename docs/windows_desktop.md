# Aplikasi Windows (desktop)

Permintaan lead: aplikasi dapat dipasang dengan tampilan desktop. Disusun 2026-11-15.

## Status

| Hal | Status |
|---|---|
| Folder `windows/` (proyek Flutter desktop) | Ada, judul jendela "IMOGI POS", ukuran awal 1280x800 |
| Tata letak lebar (≥ 900 dp): navigasi samping, isi maksimal 1200 dp | Ada, lulus tes otomatis |
| Pemindai barcode tanpa kamera: dialog ketik/scan (pemindai USB/Bluetooth terbaca sebagai keyboard) | Ada, lulus tes otomatis |
| **Build `.exe`** | **Belum bisa: Visual Studio belum terpasang di komputer pengembangan** |
| Uji jalan di Windows | Belum (menunggu build) |

## Syarat build (sekali saja)

1. Pasang **Visual Studio 2022 (Community)** dari visualstudio.microsoft.com dengan beban kerja **"Desktop development with C++"** (sekitar 6 sampai 10 GB).
2. Jalankan `flutter doctor`, baris "Visual Studio - develop Windows apps" harus bertanda centang.

## Build dan jalan

```
flutter run -d windows
flutter build windows --release
```

Hasil build: `build\windows\x64\runner\Release\` (folder berisi `apps_pos.exe` dan DLL pendamping; seluruh folder harus ikut dibawa). Installer (MSIX/Inno Setup) belum dibuat.

## Dukungan plugin di Windows

| Plugin | Windows | Penanganan |
|---|---|---|
| `mobile_scanner` (kamera) | Tidak | Dialog ketik/scan (`pindaiBarcode`) |
| `workmanager` (sync latar belakang) | Tidak | Tidak dipakai di kode saat ini |
| `print_bluetooth_thermal` | Ada implementasi Windows | **Belum teruji**; printer Bluetooth di PC mungkin butuh pairing Windows |
| `permission_handler`, `flutter_secure_storage`, `file_picker`, `share_plus`, `url_launcher`, `image_picker`, `connectivity_plus`, `path_provider` | Ada | Belum teruji di Windows |
| Database lokal (drift + SQLite) | Ada | Berkas di folder Dokumen pengguna; belum teruji |

## Yang perlu diketahui

- `flutter create` menaikkan 77 versi dependensi di `pubspec.lock`. Perubahan itu **tidak dipakai**: berkas dikembalikan, dependensi tetap sama dengan yang sudah diuji.
- Pada desktop, pencarian dan pembayaran belum dioptimalkan untuk mouse dan keyboard (pintasan keyboard, fokus otomatis, ukuran target klik).
- Enkripsi database lokal belum aktif (berlaku juga di Android).
