import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatar_initial.dart';
import '../../domain/pelanggan.dart';
import '../providers/pelanggan_providers.dart';

/// Bottom sheet pilih pelanggan - dipakai Keranjang (opsional, ada
/// "Tanpa pelanggan") dan BayarKasbonPage (tahap 3b-1, [wajibPilih] = true
/// supaya baris itu disembunyikan - kasbon wajib tahu siapa yang
/// berutang, aturan #1). Juga punya "+ Tambah pelanggan baru" supaya alur
/// "pilih/buat pelanggan" tidak memaksa kasir keluar dulu ke halaman
/// Pelanggan.
class PelangganPickerSheet extends ConsumerStatefulWidget {
  const PelangganPickerSheet({required this.daftar, this.wajibPilih = false, super.key});

  final List<Pelanggan> daftar;
  final bool wajibPilih;

  @override
  ConsumerState<PelangganPickerSheet> createState() => _PelangganPickerSheetState();
}

class _PelangganPickerSheetState extends ConsumerState<PelangganPickerSheet> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pilih pelanggan', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Tambah pelanggan baru'),
              onTap: () => _tambahPelangganBaru(context),
            ),
            if (!widget.wajibPilih)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_off_outlined),
                title: const Text('Tanpa pelanggan'),
                onTap: () => Navigator.of(context).pop(),
              ),
            if (widget.daftar.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('Belum ada pelanggan tersimpan', style: AppTypography.secondary),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.daftar.length,
                  itemBuilder: (context, index) {
                    final p = widget.daftar[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AvatarInitial.fromName(p.nama),
                      title: Text(p.nama),
                      subtitle: Text('${p.poin} poin'),
                      onTap: () => Navigator.of(context).pop(p),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _tambahPelangganBaru(BuildContext context) async {
    final namaController = TextEditingController();
    final noHpController = TextEditingController();
    final dibuat = await showDialog<bool>(
      context: context,
      // StatefulBuilder WAJIB di sini - tanpa ini `onPressed:` tombol
      // Simpan cuma dievaluasi SEKALI saat dialog pertama dibangun (nama
      // masih kosong), lalu tidak pernah dievaluasi ulang walau user
      // sudah mengetik (TextField.onChanged tidak otomatis me-rebuild
      // AlertDialog di luar dirinya) - tombol jadi disabled selamanya.
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pelanggan baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('pelangganPickerSheet.nama'),
                controller: namaController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nama'),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('pelangganPickerSheet.noHp'),
                controller: noHpController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'No. HP'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
            FilledButton(
              onPressed: namaController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (dibuat != true || !context.mounted) return;

    final tokoId = ref.read(currentTokoIdProvider);

    await ref.read(pelangganRepositoryProvider).tambahPelanggan(
      tokoId: tokoId,
      nama: namaController.text.trim(),
      noHp: noHpController.text.trim().isEmpty ? null : noHpController.text.trim(),
    );
    if (!context.mounted) return;

    final pelangganTerbaru = await ref.read(pelangganAktifProvider.future);
    final baru = pelangganTerbaru.where((p) => p.nama == namaController.text.trim()).lastOrNull;
    if (context.mounted) Navigator.of(context).pop(baru);
  }
}
