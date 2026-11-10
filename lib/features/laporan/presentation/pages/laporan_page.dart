import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../transaksi/presentation/providers/transaksi_providers.dart' show namaMetodeBayarProvider;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import '../../../transaksi/domain/metode_bayar_label.dart';
import '../../data/laporan_repository.dart';
import '../../domain/ringkasan_laporan.dart';
import '../providers/laporan_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

const _warnaMetode = [AppColors.primary, Color(0xFF5AB89A), Color(0xFFD97A1E), Color(0xFF9FB1A9)];

/// Sesuai mockup "Laporan" - semua angka dihitung langsung dari data
/// transaksi+item+pembayaran yang sudah ada di SQLite lokal, tidak ada
/// tabel baru. "Atur" (F3.C) - date range picker, dibatasi fitur
/// 'laporan_dasar' (Gratis 30 hari/Pro 365 hari/Bisnis tanpa batas, lihat
/// FeatureGate.batasUntuk) - backend /laporan/* punya pengecekan 422 yang
/// sama (pastikan_rentang_diizinkan) sbg lapis pertahanan kedua, tapi
/// Laporan di app ini murni lokal (tidak pernah panggil endpoint itu),
/// jadi gating yang BENAR-BENAR jalan di sini adalah yang di UI ini.
class LaporanPage extends ConsumerWidget {
  const LaporanPage({super.key});

  Future<void> _aturRentang(BuildContext context, WidgetRef ref) async {
    final gate = await ref.read(featureGateProvider.future);
    final batasHari = gate.batasUntuk('laporan_dasar');
    if (!context.mounted) return;

    final now = DateTime.now();
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (hasil == null || !context.mounted) return;

    final jumlahHari = hasil.end.difference(hasil.start).inDays + 1;
    if (rentangLaporanMelebihiBatas(jumlahHari: jumlahHari, batasHari: batasHari)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rentang melebihi batas paket'),
          content: Text(
            'Paket kamu cuma bisa lihat laporan $batasHari hari ke belakang. '
            'Rentang yang dipilih ($jumlahHari hari) melebihi itu - upgrade paket '
            'utk lihat laporan rentang lebih jauh.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Oke')),
          ],
        ),
      );
      return;
    }

    ref.read(rentangCustomLaporanProvider.notifier).state = (hasil.start, hasil.end);
    ref.read(periodeLaporanProvider.notifier).state = PeriodeLaporan.custom;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ringkasanAsync = ref.watch(ringkasanLaporanProvider);
    final periode = ref.watch(periodeLaporanProvider);
    final rentangCustom = ref.watch(rentangCustomLaporanProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0),
            child: _TabPeriode(
              periode: periode,
              rentangCustom: rentangCustom,
              onAtur: () => _aturRentang(context, ref),
            ),
          ),
          Expanded(
            child: ringkasanAsync.when(
              data: (ringkasan) => _IsiLaporan(ringkasan: ringkasan, namaMetode: ref.watch(namaMetodeBayarProvider).value ?? const <String, String>{}),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(child: Text('Gagal memuat laporan: $error')),
            ),
          ),
        ],
      ),
    );
  }
}

final _formatTanggalSingkat = DateFormat('d MMM', 'id_ID');

class _TabPeriode extends ConsumerWidget {
  const _TabPeriode({required this.periode, required this.rentangCustom, required this.onAtur});

  final PeriodeLaporan periode;
  final (DateTime, DateTime)? rentangCustom;
  final VoidCallback onAtur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget tab(String label, PeriodeLaporan? value, {Key? key}) {
      final aktif = value != null && value == periode;
      return Expanded(
        child: GestureDetector(
          key: key,
          onTap: () {
            if (value != null) {
              ref.read(periodeLaporanProvider.notifier).state = value;
            } else {
              onAtur();
            }
          },
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: aktif ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: aktif ? FontWeight.w700 : FontWeight.w600,
                color: aktif ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    final labelAtur = periode == PeriodeLaporan.custom && rentangCustom != null
        ? '${_formatTanggalSingkat.format(rentangCustom!.$1)}-${_formatTanggalSingkat.format(rentangCustom!.$2)}'
        : 'Atur';

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          tab('Hari ini', PeriodeLaporan.hariIni),
          tab('7 hari', PeriodeLaporan.tujuhHari),
          tab('30 hari', PeriodeLaporan.tigaPuluhHari),
          tab(labelAtur, null, key: const Key('laporanForm.atur')),
        ],
      ),
    );
  }
}

class _IsiLaporan extends StatelessWidget {
  const _IsiLaporan({required this.ringkasan, this.namaMetode = const {}});

  final RingkasanLaporan ringkasan;
  final Map<String, String> namaMetode;

  @override
  Widget build(BuildContext context) {
    if (ringkasan.jumlahTransaksi == 0) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        message: 'Belum ada transaksi selesai di periode ini.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kartuRingkasan(),
          const SizedBox(height: AppSpacing.md),
          if (ringkasan.jamRamai.isNotEmpty) ..._kartuJamRamai(),
          if (ringkasan.metodeBayar.isNotEmpty) ..._kartuMetodeBayar(),
          _kartuProdukTerlaris(),
        ],
      ),
    );
  }

  Widget _kartuRingkasan() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Penjualan bersih', style: TextStyle(color: Colors.white70, fontSize: 13)),
          Text(
            _formatRupiah.format(ringkasan.penjualanBersih),
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _statTeal('Laba kotor', _formatRupiah.format(ringkasan.labaKotor)),
              _statTeal('Transaksi', '${ringkasan.jumlahTransaksi}'),
              _statTeal('Rata-rata', _formatRupiah.format(ringkasan.rataRata)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTeal(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(value,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  List<Widget> _kartuJamRamai() {
    final maxTotal = ringkasan.jamRamai.map((j) => j.total).reduce((a, b) => a > b ? a : b);
    final puncak = ringkasan.jamRamai.reduce((a, b) => a.total >= b.total ? a : b);

    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Jam ramai', style: AppTypography.bodyEmphasis),
                Text(
                  'Puncak ${puncak.jam.toString().padLeft(2, '0')}.00 · ${_formatRupiah.format(puncak.total)}',
                  style: AppTypography.secondary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 110,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final j in ringkasan.jamRamai)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 24,
                              height: 90 * (j.total / maxTotal),
                              decoration: BoxDecoration(
                                color: j.total == maxTotal ? AppColors.primary : AppColors.primaryTintBorder,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(j.jam.toString().padLeft(2, '0'),
                                style: AppTypography.secondary.copyWith(fontSize: 10)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
    ];
  }

  List<Widget> _kartuMetodeBayar() {
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Metode bayar', style: AppTypography.bodyEmphasis),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (var i = 0; i < ringkasan.metodeBayar.length; i++) ...[
                    Expanded(
                      flex: (ringkasan.metodeBayar[i].persen * 10).round().clamp(1, 1000),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _warnaMetode[i % _warnaMetode.length],
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    if (i != ringkasan.metodeBayar.length - 1) const SizedBox(width: 2),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                for (var i = 0; i < ringkasan.metodeBayar.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _warnaMetode[i % _warnaMetode.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${ringkasan.metodeBayar[i].labelOverride ?? labelMetodeBayar(ringkasan.metodeBayar[i].metodeBayarId, nama: namaMetode)} '
                        '${ringkasan.metodeBayar[i].persen.round()}%',
                        style: AppTypography.secondary,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
    ];
  }

  Widget _kartuProdukTerlaris() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Produk terlaris', style: AppTypography.bodyEmphasis),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < ringkasan.produkTerlaris.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: AppTypography.bodyEmphasis.copyWith(color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: Text(ringkasan.produkTerlaris[i].namaProduk, style: AppTypography.bodyEmphasis),
                  ),
                  Text('${ringkasan.produkTerlaris[i].qty.toStringAsFixed(0)}×',
                      style: AppTypography.secondary),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 86,
                    child: Text(
                      _formatRupiah.format(ringkasan.produkTerlaris[i].total),
                      textAlign: TextAlign.right,
                      style: AppTypography.bodyEmphasis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
