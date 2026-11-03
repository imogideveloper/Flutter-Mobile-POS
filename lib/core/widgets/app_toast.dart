import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Toast custom, dipakai sbg pengganti [SnackBar] polos bawaan Flutter
/// utk notifikasi proaktif yang butuh lebih menonjol (mis. "Stok menipis"
/// sesudah checkout di struk_page.dart) - mengambang dari ATAS layar
/// (bukan bawah spt SnackBar) supaya tidak numpuk dgn bottom nav bar/FAB,
/// dan tidak ketiban keyboard kalau muncul saat field lagi fokus.
enum ToastVariant { success, warning, danger, info }

class _ToastStyle {
  const _ToastStyle({required this.bg, required this.fg, required this.icon});
  final Color bg;
  final Color fg;
  final IconData icon;
}

const _toastStyles = <ToastVariant, _ToastStyle>{
  ToastVariant.success: _ToastStyle(
    bg: AppColors.primaryTint,
    fg: AppColors.primaryDark,
    icon: Icons.check_circle_outline,
  ),
  ToastVariant.warning: _ToastStyle(
    bg: AppColors.warningBg,
    fg: AppColors.warningTextStrong,
    icon: Icons.inventory_2_outlined,
  ),
  ToastVariant.danger: _ToastStyle(
    bg: AppColors.dangerBg,
    fg: AppColors.dangerTextStrong,
    icon: Icons.error_outline,
  ),
  ToastVariant.info: _ToastStyle(
    bg: AppColors.indigoBg,
    fg: AppColors.indigoText,
    icon: Icons.info_outline,
  ),
};

OverlayEntry? _entryAktif;

/// Tampilkan toast mengambang di atas layar manapun yang sedang aktif.
/// Toast sebelumnya (kalau masih tampil) langsung diganti, bukan ditumpuk -
/// notifikasi beruntun (mis. checkout cepat berturut-turut) tidak bikin
/// toast menumpuk di layar.
void showAppToast(
  BuildContext context, {
  required String message,
  String? title,
  ToastVariant variant = ToastVariant.info,
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  // defensif: toast sebelumnya mungkin sudah lepas dari Overlay-nya sendiri
  // (mis. layar yang menampilkannya sudah ditutup sebelum timer auto-tutup
  // sempat jalan) - remove() pada entry yang overlay-nya sudah tidak
  // ter-mount tidak boleh menggagalkan toast BARU ini.
  try {
    _entryAktif?.remove();
  } catch (_) {
    // sudah terlepas duluan - abaikan.
  }
  _entryAktif = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AppToastView(
      title: title,
      message: message,
      variant: variant,
      duration: duration,
      onDismiss: () {
        if (entry.mounted) entry.remove();
        if (identical(_entryAktif, entry)) _entryAktif = null;
      },
    ),
  );
  _entryAktif = entry;
  overlay.insert(entry);
}

class _AppToastView extends StatefulWidget {
  const _AppToastView({
    required this.message,
    required this.variant,
    required this.duration,
    required this.onDismiss,
    this.title,
  });

  final String? title;
  final String message;
  final ToastVariant variant;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_AppToastView> createState() => _AppToastViewState();
}

class _AppToastViewState extends State<_AppToastView> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 160),
  );
  Timer? _timerAutoTutup;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timerAutoTutup = Timer(widget.duration, _tutup);
  }

  Future<void> _tutup() async {
    _timerAutoTutup?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timerAutoTutup?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _toastStyles[widget.variant]!;
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -200) _tutup();
                  },
                  onTap: _tutup,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: style.bg,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(style.icon, color: style.fg, size: 22),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.title != null) ...[
                                Text(
                                  widget.title!,
                                  style: AppTypography.bodyEmphasis.copyWith(color: style.fg),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                widget.message,
                                style: AppTypography.body.copyWith(color: style.fg),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        GestureDetector(
                          onTap: _tutup,
                          child: Icon(Icons.close, color: style.fg.withValues(alpha: 0.7), size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
