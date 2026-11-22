import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/laba_rugi.dart';
import '../../domain/laba_rugi_konsolidasi.dart';
import '../../domain/pengeluaran.dart';

/// Laporan keuangan konsolidasi multi-outlet (IMOGI no. 84): laba rugi tiap outlet dan total toko.
/// Butuh internet; hanya Owner/Manajer dan paket yang memiliki fitur ini.
class LabaRugiKonsolidasiPage extends ConsumerStatefulWidget {
  const LabaRugiKonsolidasiPage({super.key});

  @override
  ConsumerState<LabaRugiKonsolidasiPage> createState() => _LabaRugiKonsolidasiPageState();
}

class _LabaRugiKonsolidasiPageState extends ConsumerState<LabaRugiKonsolidasiPage> {
  RentangPengeluaran _rentang = RentangPengeluaran.bulanIni;
  LabaRugiKonsolidasi? _data;
  String? _error;
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
      final (dari, sampai) = _rentang.tanggal(DateTime.now());
      final json = await ref.read(backendApiProvider).getJson(
        accessToken: sesi.accessToken,
        path: '/laporan/laba-rugi-konsolidasi',
        query: {
          'dari': isoDenganOffset(dari),
          // [sampai] eksklusif: awal hari berikutnya.
          'sampai': isoDenganOffset(DateTime(sampai.year, sampai.month, sampai.day + 1)),
        },
      );
      _data = LabaRugiKonsolidasi.dariJson(json as Map<String, dynamic>);
    } on BackendException catch (e) {
      _data = null;
      _error = e.tidakAdaKoneksi ? 'Butuh internet untuk melihat laporan.' : e.message;
    } catch (e) {
      _data = null;
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  String _rp(int nilai) => '${nilai < 0 ? '-' : ''}Rp ${formatRupiahDigits(nilai.abs())}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laba rugi konsolidasi')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final r in RentangPengeluaran.values)
                  ChoiceChip(
                    key: Key('konsolidasi.rentang.${r.name}'),
                    label: Text(r.label),
                    selected: _rentang == r,
                    onSelected: (_) {
                      setState(() => _rentang = r);
                      _muat();
                    },
                  ),
              ],
            ),
          ),
          Expanded(child: _isi()),
        ],
      ),
    );
  }

  Widget _isi() {
    if (_memuat && _data == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, key: const Key('konsolidasi.error'), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: _muat, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.total.rugi ? 'Rugi bersih total' : 'Laba bersih total', style: AppTypography.secondary),
              Text(
                _rp(d.total.labaBersih),
                key: const Key('konsolidasi.totalLaba'),
                style: AppTypography.headerTitle.copyWith(
                  fontSize: 24,
                  color: d.total.rugi ? AppColors.dangerText : AppColors.primaryDark,
                ),
              ),
              Text(
                '${d.perOutlet.length} outlet · ${d.total.jumlahTransaksi} transaksi',
                style: AppTypography.secondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final o in d.perOutlet) ...[
          AppCard(
            key: Key('konsolidasi.outlet.${o.outletId}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.outletNama, style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.sm),
                _baris('Penjualan bersih', o.laporan.penjualanBersih),
                _baris('HPP', -o.laporan.hpp),
                _baris('Biaya operasional', -o.laporan.totalBiayaOperasional),
                const Divider(),
                _baris(o.laporan.rugi ? 'Rugi bersih' : 'Laba bersih', o.laporan.labaBersih, tebal: true),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppCard(
          child: Column(
            children: [
              Text('Total seluruh toko', style: AppTypography.cardTitle),
              const SizedBox(height: AppSpacing.sm),
              _baris('Penjualan bersih', d.total.penjualanBersih, kunci: 'penjualanBersih'),
              _baris('HPP', -d.total.hpp),
              _baris('Biaya operasional', -d.total.totalBiayaOperasional),
              if (d.biayaTanpaOutlet != 0)
                _baris('  termasuk biaya tanpa outlet', -d.biayaTanpaOutlet, kunci: 'biayaTanpaOutlet'),
              const Divider(),
              _baris(d.total.rugi ? 'Rugi bersih' : 'Laba bersih', d.total.labaBersih, tebal: true),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Rumus sama dengan laporan Laba rugi per outlet (belanja bahan tidak dikurangkan lagi, refund sudah '
          'dikurangkan dari penjualan). Total toko memuat biaya yang dicatat tanpa outlet.',
          style: AppTypography.secondary,
        ),
      ],
    );
  }

  Widget _baris(String label, int nilai, {bool tebal = false, String? kunci}) {
    final gaya = tebal ? AppTypography.bodyEmphasis : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: gaya)),
          Text(_rp(nilai), key: kunci == null ? null : Key('konsolidasi.$kunci'), style: gaya),
        ],
      ),
    );
  }
}
