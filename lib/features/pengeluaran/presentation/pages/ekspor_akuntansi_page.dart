import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../produk/presentation/providers/impor_produk_providers.dart' show pembagiBerkasProvider;
import 'settlement_page.dart' show tanggalIso;

/// Ekspor ringkasan harian ke CSV untuk software akuntansi (IMOGI no. 85). Butuh internet; berkas dibuat server
/// lalu dibagikan lewat menu bagikan. Tiap baris membawa kode akun usulan dari bagan akun standar.
class EksporAkuntansiPage extends ConsumerStatefulWidget {
  const EksporAkuntansiPage({super.key});

  @override
  ConsumerState<EksporAkuntansiPage> createState() => _EksporAkuntansiPageState();
}

class _EksporAkuntansiPageState extends ConsumerState<EksporAkuntansiPage> {
  late DateTime _dari = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _sampai = DateTime.now();
  bool _mengekspor = false;

  Future<void> _pilih({required bool awal}) async {
    final t = await showDatePicker(
      context: context,
      initialDate: awal ? _dari : _sampai,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (t == null) return;
    setState(() => awal ? _dari = t : _sampai = t);
  }

  Future<void> _ekspor() async {
    if (_sampai.isBefore(_dari)) {
      showAppToast(context, message: 'Tanggal sampai harus sesudah tanggal dari', variant: ToastVariant.warning);
      return;
    }
    setState(() => _mengekspor = true);
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
      final json = await ref.read(backendApiProvider).getJson(
        accessToken: sesi.accessToken,
        path: '/ekspor-akuntansi',
        query: {'dari': tanggalIso(_dari), 'sampai': tanggalIso(_sampai)},
      );
      final m = json as Map;
      if ((m['jumlah_baris'] as int) == 0) {
        if (mounted) showAppToast(context, message: 'Tidak ada data pada rentang ini', variant: ToastVariant.info);
        return;
      }
      await ref.read(pembagiBerkasProvider)(m['nama_berkas'] as String, m['csv'] as String);
    } on BackendException catch (e) {
      if (mounted) {
        showAppToast(
          context,
          message: e.tidakAdaKoneksi ? 'Butuh internet untuk mengekspor.' : e.message,
          variant: ToastVariant.danger,
        );
      }
    } catch (e) {
      if (mounted) showAppToast(context, message: 'Gagal mengekspor: $e', variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _mengekspor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ekspor ke software akuntansi')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ringkasan harian (CSV)', style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Satu baris per tanggal: penjualan bersih, pajak dipungut, HPP, penerimaan per metode '
                  'bayar, dan biaya per kategori, lengkap dengan kode akun dari bagan akun standar.',
                  style: AppTypography.secondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ListTile(
            key: const Key('ekspor.dari'),
            title: const Text('Dari tanggal'),
            subtitle: Text(tanggalIso(_dari)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () => _pilih(awal: true),
          ),
          ListTile(
            key: const Key('ekspor.sampai'),
            title: const Text('Sampai tanggal'),
            subtitle: Text(tanggalIso(_sampai)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () => _pilih(awal: false),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            key: const Key('ekspor.bagikan'),
            onPressed: _mengekspor ? null : _ekspor,
            icon: const Icon(Icons.ios_share_outlined),
            label: Text(_mengekspor ? 'Menyiapkan...' : 'Ekspor & bagikan'),
          ),
        ],
      ),
    );
  }
}
