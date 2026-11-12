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
import '../../domain/pengeluaran.dart';

/// Laporan laba rugi (IMOGI no. 69), dihitung server dari transaksi selesai dan pengeluaran.
/// Butuh internet. Hanya role dengan izin laporan.lihat dan paket yang memiliki fitur ini.
class LabaRugiPage extends ConsumerStatefulWidget {
  const LabaRugiPage({super.key});

  @override
  ConsumerState<LabaRugiPage> createState() => _LabaRugiPageState();
}

class _LabaRugiPageState extends ConsumerState<LabaRugiPage> {
  RentangPengeluaran _rentang = RentangPengeluaran.bulanIni;
  LabaRugi? _data;
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
      final json = await ref.read(backendApiProvider).laporanLabaRugi(
            accessToken: sesi.accessToken,
            dari: isoDenganOffset(dari),
            // [sampai] eksklusif: awal hari berikutnya.
            sampai: isoDenganOffset(DateTime(sampai.year, sampai.month, sampai.day + 1)),
          );
      _data = LabaRugi.dariJson(json);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laba rugi')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final r in RentangPengeluaran.values)
                  ChoiceChip(
                    key: Key('labaRugi.rentang.${r.name}'),
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
              Text(_error!, key: const Key('labaRugi.error'), textAlign: TextAlign.center),
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
              Text(d.rugi ? 'Rugi bersih' : 'Laba bersih', style: AppTypography.secondary),
              Text(
                '${d.rugi ? '-' : ''}Rp ${formatRupiahDigits(d.labaBersih.abs())}',
                key: const Key('labaRugi.labaBersih'),
                style: AppTypography.headerTitle.copyWith(
                  fontSize: 24,
                  color: d.rugi ? AppColors.dangerText : AppColors.primaryDark,
                ),
              ),
              Text('${d.jumlahTransaksi} transaksi', style: AppTypography.secondary),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            children: [
              _baris('Penjualan kotor', d.penjualanKotor),
              _baris('Diskon', -d.diskon, kunci: 'diskon'),
              _baris('Penjualan bersih', d.penjualanBersih, tebal: true, kunci: 'penjualanBersih'),
              _baris('HPP (harga pokok penjualan)', -d.hpp, kunci: 'hpp'),
              const Divider(),
              _baris('Laba kotor', d.labaKotor, tebal: true, kunci: 'labaKotor'),
              const SizedBox(height: AppSpacing.sm),
              if (d.biayaOperasional.isEmpty)
                _baris('Biaya operasional', 0)
              else
                for (final e in d.biayaOperasional.entries)
                  _baris(labelKategoriPengeluaran(e.key), -e.value, kunci: 'biaya.${e.key}'),
              _baris('Total biaya operasional', -d.totalBiayaOperasional, tebal: true, kunci: 'totalBiaya'),
              const Divider(),
              _baris(d.rugi ? 'Rugi bersih' : 'Laba bersih', d.labaBersih, tebal: true),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Catatan: pajak/service yang dipungut (Rp ${formatRupiahDigits(d.pajakDipungut)}) bukan pendapatan '
          'sehingga tidak dihitung. Belanja bahan (Rp ${formatRupiahDigits(d.belanjaBahan)}) tidak dikurangkan lagi '
          'karena sudah tercermin di HPP. Refund belum diperhitungkan.',
          key: const Key('labaRugi.catatan'),
          style: AppTypography.secondary,
        ),
      ],
    );
  }

  Widget _baris(String label, int nilai, {bool tebal = false, String? kunci}) {
    final gaya = tebal ? AppTypography.bodyEmphasis : null;
    final teks = '${nilai < 0 ? '-' : ''}Rp ${formatRupiahDigits(nilai.abs())}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: gaya)),
          Text(teks, key: kunci == null ? null : Key('labaRugi.$kunci'), style: gaya),
        ],
      ),
    );
  }
}
