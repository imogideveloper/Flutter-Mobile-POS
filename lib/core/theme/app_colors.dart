import 'package:flutter/material.dart';

/// Token warna resmi, diekstrak dari mockup "Desain App Kasir POS" (16 layar
/// referensi). Jangan tambah warna baru di luar sini - semua widget harus
/// memakai token ini supaya tampilan konsisten lintas layar.
abstract final class AppColors {
  // Latar & permukaan
  static const bg = Color(0xFFF4F6F3);
  static const surface = Color(0xFFFFFFFF);

  // Teks
  static const textPrimary = Color(0xFF17201C);
  static const textSecondary = Color(0xFF5F6B66);
  static const textTertiary = Color(0xFF9FB1A9);

  // Border
  static const borderDefault = Color(0xFFE3E8E4);
  static const borderStrong = Color(0xFFCFD8D3);

  // Primary (teal) - tombol utama, link, tab aktif
  static const primary = Color(0xFF0F6E58);
  static const primaryDark = Color(0xFF0A5443);
  static const primaryTint = Color(0xFFE3F1EC);
  static const primaryTintBorder = Color(0xFFB8DCCF);

  // Warning/amber - badge paket, stok menipis, sync pending
  static const warningBg = Color(0xFFFDF0E1);
  static const warningBgAlt = Color(0xFFF1E7DC);
  static const warningText = Color(0xFF9A4A07);
  static const warningTextStrong = Color(0xFF7A3E06);

  // Danger/merah - void, hapus, gagal
  static const dangerBg = Color(0xFFFDECEA);
  static const dangerBorder = Color(0xFFE5B8B3);
  static const dangerText = Color(0xFFB42318);
  static const dangerTextStrong = Color(0xFF8F1D13);

  // Indigo - avatar/badge member
  static const indigoBg = Color(0xFFE9ECF7);
  static const indigoText = Color(0xFF2F3E7A);

  // Coklat - avatar inisial toko
  static const brownBg = Color(0xFFF1E7DC);
  static const brownText = Color(0xFF6B4A2B);
}
