import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Lingkaran berisi 1-2 huruf inisial. Pakai [background]/[foreground]
/// sesuai konteks: indigo untuk member, coklat untuk profil toko, dst.
class AvatarInitial extends StatelessWidget {
  const AvatarInitial({
    super.key,
    required this.text,
    this.background = AppColors.indigoBg,
    this.foreground = AppColors.indigoText,
    this.size = 38,
  });

  final String text;
  final Color background;
  final Color foreground;
  final double size;

  factory AvatarInitial.fromName(
    String name, {
    Color background = AppColors.indigoBg,
    Color foreground = AppColors.indigoText,
    double size = 38,
  }) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.substring(0, 1)
        : parts.first.substring(0, 1) + parts.last.substring(0, 1);
    return AvatarInitial(
      text: initials.toUpperCase(),
      background: background,
      foreground: foreground,
      size: size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        text,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: size * 0.4),
      ),
    );
  }
}
