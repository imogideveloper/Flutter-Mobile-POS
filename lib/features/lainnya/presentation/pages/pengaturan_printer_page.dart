import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/printer/pengaturan_printer_providers.dart';
import '../../../../core/printer/printer_service.dart';
import '../../../../core/struk/esc_pos_converter.dart';
import '../../../../core/struk/penyusun_struk.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';

/// Pengaturan printer Bluetooth (tahap 4 bagian D.1) - minta izin, cari
/// printer yang SUDAH dipasangkan (pairing dilakukan di pengaturan
/// Bluetooth OS, bukan di sini), pilih lebar kertas, cetak tes. Pilihan
/// disimpan LOKAL per HP (PengaturanPrinterDao) - tidak pernah disync.
class PengaturanPrinterPage extends ConsumerStatefulWidget {
  const PengaturanPrinterPage({super.key});

  @override
  ConsumerState<PengaturanPrinterPage> createState() => _PengaturanPrinterPageState();
}

class _PengaturanPrinterPageState extends ConsumerState<PengaturanPrinterPage> {
  List<PerangkatBluetooth> _daftarPerangkat = [];
  String? _macTerpilih;
  String? _namaTerpilih;
  int _lebarKertasMm = 58;
  bool _cetakOtomatis = true;
  bool _mencari = false;
  bool _mencetakTes = false;
  bool _sudahMuatPengaturan = false;

  @override
  void initState() {
    super.initState();
    _cariPerangkat();
  }

  void _muatDariPengaturanTersimpan(dynamic pengaturan) {
    if (_sudahMuatPengaturan || pengaturan == null) return;
    _sudahMuatPengaturan = true;
    setState(() {
      _macTerpilih = pengaturan.macAddress as String?;
      _namaTerpilih = pengaturan.namaPrinter as String?;
      _lebarKertasMm = pengaturan.lebarKertasMm as int;
      _cetakOtomatis = pengaturan.cetakOtomatis as bool;
    });
  }

  Future<void> _cariPerangkat() async {
    setState(() => _mencari = true);
    try {
      final printer = ref.read(printerServiceProvider);
      final diizinkan = await printer.izinDiberikan() || await printer.mintaIzin();
      if (!diizinkan) {
        if (mounted) {
          showAppToast(context,
              message: 'Izin Bluetooth ditolak - tidak bisa mencari printer', variant: ToastVariant.warning);
        }
        return;
      }
      final aktif = await printer.bluetoothAktif();
      if (!aktif) {
        if (mounted) {
          showAppToast(context,
              message: 'Bluetooth mati - nyalakan dulu lalu coba lagi', variant: ToastVariant.warning);
        }
        return;
      }
      final daftar = await printer.perangkatTerpasang();
      if (mounted) setState(() => _daftarPerangkat = daftar);
    } finally {
      if (mounted) setState(() => _mencari = false);
    }
  }

  Future<void> _cetakTes() async {
    if (_macTerpilih == null) return;
    setState(() => _mencetakTes = true);
    try {
      final printer = ref.read(printerServiceProvider);
      final tersambung = await printer.statusTersambung();
      if (!tersambung) {
        final sukses = await printer.sambungkan(_macTerpilih!);
        if (!sukses) {
          if (mounted) {
            showAppToast(context, message: 'Gagal terhubung ke printer', variant: ToastVariant.danger);
          }
          return;
        }
      }

      final pengaturan = PengaturanStrukData(lebarKertasMm: _lebarKertasMm);
      final baris = <BarisStruk>[
        const BarisStruk('TES CETAK', rata: RataStruk.tengah, tebal: true),
        BarisStruk('-' * pengaturan.lebarKarakter),
        const BarisStruk('Printer tersambung dgn benar.'),
        BarisStruk('Lebar kertas: $_lebarKertasMm mm'),
        BarisStruk('-' * pengaturan.lebarKarakter),
      ];
      final bytes = await konversiKeEscPos(baris: baris, lebarKertasMm: _lebarKertasMm);
      final berhasilCetak = await printer.cetakBytes(bytes);
      if (mounted) {
        showAppToast(
          context,
          message: berhasilCetak ? 'Cetak tes terkirim' : 'Gagal mencetak',
          variant: berhasilCetak ? ToastVariant.success : ToastVariant.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _mencetakTes = false);
    }
  }

  Future<void> _simpan() async {
    await ref.read(pengaturanPrinterDaoProvider).simpan(
          macAddress: _macTerpilih,
          namaPrinter: _namaTerpilih,
          lebarKertasMm: _lebarKertasMm,
          cetakOtomatis: _cetakOtomatis,
        );
    if (mounted) {
      showAppToast(context, message: 'Pengaturan printer disimpan', variant: ToastVariant.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pengaturanAsync = ref.watch(pengaturanPrinterProvider);
    pengaturanAsync.whenData(_muatDariPengaturanTersimpan);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer struk'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _mencari ? null : _cariPerangkat,
            tooltip: 'Cari ulang',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Text('Printer terpasangkan', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
          const SizedBox(height: AppSpacing.sm),
          if (_mencari)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.lg), child: CircularProgressIndicator()))
          else if (_daftarPerangkat.isEmpty)
            Text(
              'Belum ada printer terpasangkan - pasangkan dulu lewat Pengaturan Bluetooth HP.',
              style: AppTypography.secondary,
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final perangkat in _daftarPerangkat)
                    RadioListTile<String>(
                      key: Key('pengaturanPrinter.perangkat.${perangkat.macAddress}'),
                      title: Text(perangkat.nama),
                      subtitle: Text(perangkat.macAddress, style: AppTypography.secondary),
                      value: perangkat.macAddress,
                      groupValue: _macTerpilih,
                      onChanged: (value) => setState(() {
                        _macTerpilih = value;
                        _namaTerpilih = perangkat.nama;
                      }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          Text('Lebar kertas', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  key: const Key('pengaturanPrinter.lebar58'),
                  label: const Text('58 mm'),
                  selected: _lebarKertasMm == 58,
                  onSelected: (_) => setState(() => _lebarKertasMm = 58),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ChoiceChip(
                  key: const Key('pengaturanPrinter.lebar80'),
                  label: const Text('80 mm'),
                  selected: _lebarKertasMm == 80,
                  onSelected: (_) => setState(() => _lebarKertasMm = 80),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            key: const Key('pengaturanPrinter.cetakOtomatis'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Cetak otomatis setelah bayar'),
            value: _cetakOtomatis,
            onChanged: (value) => setState(() => _cetakOtomatis = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              key: const Key('pengaturanPrinter.cetakTes'),
              onPressed: _macTerpilih == null || _mencetakTes ? null : _cetakTes,
              child: Text(_mencetakTes ? 'Mencetak...' : 'Cetak tes'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('pengaturanPrinter.simpan'),
              onPressed: _simpan,
              child: const Text('Simpan'),
            ),
          ),
        ],
      ),
    );
  }
}
