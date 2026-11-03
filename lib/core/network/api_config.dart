import 'package:flutter_riverpod/flutter_riverpod.dart';

/// URL dasar backend FastAPI. TODO sebelum produksi: jadikan ini
/// configurable (mis. lewat halaman pengaturan atau build flavor) - untuk
/// sekarang disetel ke alamat dev lokal.
///
/// - Emulator Android: 10.0.2.2 = loopback host dari sisi emulator.
/// - HP fisik via USB: localhost BERLAKU kalau sudah jalankan
///   `adb reverse tcp:8000 tcp:8000` (device meneruskan localhost:8000
///   miliknya ke port 8000 di mesin dev) - itu dipakai sekarang krn testing
///   manual pakai HP fisik, bukan emulator.
const _kBaseUrlDefault = 'http://localhost:8000';

final baseUrlProvider = Provider<String>((ref) => _kBaseUrlDefault);
