import 'package:flutter_riverpod/flutter_riverpod.dart';

/// URL dasar backend FastAPI. TODO sebelum produksi: jadikan ini
/// configurable (mis. lewat halaman pengaturan atau build flavor) - untuk
/// sekarang disetel ke alamat dev lokal.
///
/// - Emulator Android: 10.0.2.2 = loopback host dari sisi emulator.
/// - HP fisik via USB: localhost BERLAKU kalau sudah jalankan
///   `adb reverse tcp:8001 tcp:8001` (device meneruskan localhost:8001
///   miliknya ke port 8001 di mesin dev) - itu dipakai sekarang krn testing
///   manual pakai HP fisik, bukan emulator.
/// - Port host 8001 (bukan 8000) krn 8000 dipakai Frappe/ERPNext di mesin
///   dev; lihat mapping `8001:8000` di backend/docker-compose.yml.
const _kBaseUrlDefault = 'http://localhost:8001';

final baseUrlProvider = Provider<String>((ref) => _kBaseUrlDefault);
