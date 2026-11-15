import 'package:flutter/foundation.dart';

/// Apakah perangkat punya kamera yang dipakai pemindai barcode
/// (`mobile_scanner` hanya mendukung Android/iOS, bukan Windows/Linux).
/// Memakai [defaultTargetPlatform] supaya bisa diuji dengan
/// `debugDefaultTargetPlatformOverride`.
bool get adaKameraPemindai =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Lebar layar (dp) mulai dari mana tampilan memakai tata letak desktop
/// (navigasi samping), bukan navigasi bawah ponsel.
const double lebarMinimalDesktop = 900;

/// Lebar maksimum isi halaman di layar lebar supaya layar ponsel tidak
/// meregang sampai ribuan piksel.
const double lebarMaksimalIsi = 1200;
