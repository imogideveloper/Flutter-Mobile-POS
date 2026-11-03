import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Gaya teks bernama sesuai mockup. Angka uang selalu pakai varian
/// `tabularFigures` supaya digit-digitnya sejajar di daftar harga.
abstract final class AppTypography {
  static TextStyle get _base => GoogleFonts.plusJakartaSans(color: AppColors.textPrimary);

  static TextStyle get headerTitle =>
      _base.copyWith(fontSize: 17, fontWeight: FontWeight.w700);

  static TextStyle get cardTitle =>
      _base.copyWith(fontSize: 16, fontWeight: FontWeight.w700);

  static TextStyle get body => _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400);

  static TextStyle get bodyEmphasis =>
      _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

  static TextStyle get secondary => _base.copyWith(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static TextStyle get totalPrice => _base.copyWith(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle get moneyAmount =>
      _base.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle get labelUppercase => _base.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 0.4,
  );
}
