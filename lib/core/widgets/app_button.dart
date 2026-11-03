import 'package:flutter/material.dart';

/// Tombol utama penuh-lebar (height 48-54, bg primary) - alias tipis di atas
/// FilledButton supaya pemanggilannya singkat di tiap layar. SENGAJA
/// dibungkus SizedBox(width: double.infinity) DI SINI (bukan lewat
/// FilledButtonTheme global) - banyak FilledButton lain di app dipakai
/// sebagai tombol kecil inline (anak Row tanpa Expanded), yang akan error
/// "BoxConstraints forces an infinite width" kalau theme global memaksa
/// lebar tak terbatas.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(onPressed: onPressed, icon: icon, label: Text(label));
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Tombol sekunder (outline, bg putih) - untuk aksi pendamping. Tidak
/// dipaksa penuh-lebar secara default (dipakai juga berdampingan dalam
/// Row, mis. grid 2 kolom) - pakai [fullWidth] kalau perlu.
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.fullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final button = icon == null
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: Text(label));
    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
