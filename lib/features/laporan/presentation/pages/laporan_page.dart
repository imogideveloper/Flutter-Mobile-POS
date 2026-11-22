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
import '../../../../core/providers/izin_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../produk/domain/margin_produk.dart';
import '../../../transaksi/presentation/providers/harga_keranjang_provider.dart' show pengaturanOutletProvider;
import '../../../transaksi/domain/metode_bayar_label.dart';
import '../../data/laporan_repository.dart';
import '../../domain/ringkasan_laporan.dart';
import '../providers/laporan_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

const _warnaMetode = [AppColors.primary, AppColors.accentGreenSoft, AppColors.accentOrange, AppColors.textTertiary];

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
              color: aktif ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: aktif ? FontWeight.w700 : FontWeight.w600,
                color: aktif ? AppColors.surface : AppColors.textSecondary,
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
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
          if (ringkasan.penjualanHarian.length >= 2)
            FiturTerkunci(
              kode: 'tren_penjualan',
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _KartuTren(data: ringkasan.penjualanHarian, sebelumnya: ringkasan.penjualanPeriodeSebelumnya),
              ),
            ),
          if (ringkasan.trenKategori.isNotEmpty)
            FiturTerkunci(
              kode: 'tren_penjualan',
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _KartuTrenItem(
                  key: const Key('laporan.trenKategori'),
                  judul: 'Tren per kategori',
                  data: ringkasan.trenKategori,
                ),
              ),
            ),
          if (ringkasan.trenProduk.isNotEmpty)
            FiturTerkunci(
              kode: 'tren_penjualan',
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _KartuTrenItem(
                  key: const Key('laporan.trenProduk'),
                  judul: 'Tren per produk',
                  data: ringkasan.trenProduk,
                ),
              ),
            ),
          if (ringkasan.jamRamai.isNotEmpty) ..._kartuJamRamai(),
          if (ringkasan.metodeBayar.isNotEmpty) ..._kartuMetodeBayar(),
          _kartuProdukTerlaris(),
          if (ringkasan.marginProduk.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            FiturTerkunci(kode: 'product_margin', child: _KartuMarginProduk(data: ringkasan.marginProduk)),
          ],
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
                        '${ringkasan.metodeBayar[i].labelTampil(labelMetodeBayar(ringkasan.metodeBayar[i].metodeBayarId, nama: namaMetode))} '
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

/// HPP dan margin tiap produk pada periode laporan (IMOGI no. 72). Margin di bawah batas outlet
/// (Pengaturan struk, bawaan 50%) diberi warna peringatan; produk tanpa HPP ditandai tersendiri.
class _KartuMarginProduk extends ConsumerWidget {
  const _KartuMarginProduk({required this.data});

  final List<MarginProdukLaporan> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(izinSayaProvider).value?.contains('produk.lihat_margin') ?? true)) {
      return const SizedBox.shrink();
    }
    final outletId = ref.watch(currentOutletIdProvider);
    final batas = ref.watch(pengaturanOutletProvider(outletId)).value?.batasMargin ?? batasMarginBawaan;
    final totalOmzet = data.fold<int>(0, (a, b) => a + b.omzet);
    final totalHpp = data.fold<int>(0, (a, b) => a + b.hpp);
    return AppCard(
      key: const Key('laporan.marginProduk'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('HPP & margin per produk', style: AppTypography.bodyEmphasis),
          const SizedBox(height: 2),
          Text(
            'Laba ${_formatRupiah.format(totalOmzet - totalHpp)} dari penjualan ${_formatRupiah.format(totalOmzet)}. '
            'Batas margin $batas%.',
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final m in data)
            Padding(
              key: Key('laporan.margin.${m.namaProduk}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.namaProduk, style: AppTypography.bodyEmphasis),
                        Text(
                          '${m.qty.toStringAsFixed(m.qty == m.qty.roundToDouble() ? 0 : 1)}× · HPP ${_formatRupiah.format(m.hpp)}',
                          style: AppTypography.secondary,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_formatRupiah.format(m.laba), style: AppTypography.bodyEmphasis),
                      Text(
                        _labelMargin(m, batas),
                        style: AppTypography.secondary.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _warnaMargin(m, batas),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _labelMargin(MarginProdukLaporan m, int batas) {
  if (m.hppKosong) return 'HPP belum diisi';
  final persen = m.marginPersen;
  if (persen == null) return '-';
  return 'Margin ${persen.round()}%';
}

Color _warnaMargin(MarginProdukLaporan m, int batas) {
  if (m.hppKosong) return AppColors.textTertiary;
  final persen = m.marginPersen;
  if (persen != null && persen < batas) return AppColors.warningTextStrong;
  return AppColors.primaryDark;
}

/// Grafik tren penjualan per hari (IMOGI no. 65): batang per tanggal, puncak disorot, plus rata-rata harian
/// dan perbandingan paruh akhir dengan paruh awal periode. Dihitung offline dari transaksi lokal.
class _KartuTren extends StatelessWidget {
  const _KartuTren({required this.data, this.sebelumnya});

  final List<PenjualanHarian> data;

  /// Total periode sebelumnya yang sama panjang; null bila tidak ada pembanding.
  final int? sebelumnya;

  @override
  Widget build(BuildContext context) {
    final maks = data.map((d) => d.total).reduce((a, b) => a > b ? a : b);
    final puncak = data.firstWhere((d) => d.total == maks);
    final total = data.fold<int>(0, (a, d) => a + d.total);
    final rataRata = (total / data.length).round();

    final tengah = data.length ~/ 2;
    final awal = data.take(tengah).fold<int>(0, (a, d) => a + d.total);
    final akhir = data.skip(data.length - tengah).fold<int>(0, (a, d) => a + d.total);
    final String? perubahan = awal <= 0 ? null : '${akhir >= awal ? '+' : ''}${((akhir - awal) / awal * 100).round()}%';
    final naik = akhir >= awal;
    final formatTanggal = DateFormat('d/M');

    return AppCard(
      key: const Key('laporan.tren'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tren penjualan', style: AppTypography.bodyEmphasis),
              if (perubahan != null)
                Text(
                  '$perubahan vs paruh awal',
                  key: const Key('laporan.tren.perubahan'),
                  style: AppTypography.secondary.copyWith(
                    color: naik ? AppColors.primaryDark : AppColors.dangerText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Rata-rata ${_formatRupiah.format(rataRata)}/hari · puncak ${formatTanggal.format(puncak.tanggal)} (${_formatRupiah.format(puncak.total)})',
            style: AppTypography.secondary,
          ),
          if (sebelumnya != null && sebelumnya! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _bandingPeriode(total, sebelumnya!),
                key: const Key('laporan.tren.periodeSebelumnya'),
                style: AppTypography.secondary,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 120,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in data)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 22,
                            height: maks == 0 ? 2 : (92 * d.total / maks).clamp(2, 92).toDouble(),
                            decoration: BoxDecoration(
                              color: d.total == maks ? AppColors.primary : AppColors.primaryTintBorder,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(formatTanggal.format(d.tanggal), style: AppTypography.secondary.copyWith(fontSize: 9)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kalimat perbandingan total periode ini dengan periode sebelumnya yang sama panjang.
String _bandingPeriode(int sekarang, int sebelumnya) {
  final persen = ((sekarang - sebelumnya) / sebelumnya * 100).round();
  final arah = persen > 0 ? 'naik $persen%' : (persen < 0 ? 'turun ${-persen}%' : 'sama');
  return 'Dibanding periode sebelumnya (${_formatRupiah.format(sebelumnya)}): $arah';
}

/// Omzet lima kategori atau produk teratas beserta perubahannya dibanding periode sebelumnya yang sama
/// panjang. Dihitung offline dari transaksi lokal.
class _KartuTrenItem extends StatelessWidget {
  const _KartuTrenItem({super.key, required this.judul, required this.data});

  final String judul;
  final List<TrenItemLaporan> data;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(judul, style: AppTypography.bodyEmphasis),
          const SizedBox(height: 2),
          Text('Dibanding periode sebelumnya yang sama panjang.', style: AppTypography.secondary),
          const SizedBox(height: AppSpacing.sm),
          for (final t in data)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text(t.nama, style: AppTypography.bodyEmphasis)),
                  Text(_formatRupiah.format(t.omzet), style: AppTypography.secondary),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 62,
                    child: Text(
                      _labelPerubahan(t),
                      key: Key('laporan.tren.${t.nama}'),
                      textAlign: TextAlign.right,
                      style: AppTypography.secondary.copyWith(
                        color: _warnaPerubahan(t),
                        fontWeight: FontWeight.w700,
                      ),
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

String _labelPerubahan(TrenItemLaporan t) {
  if (t.baru) return 'Baru';
  final p = t.perubahanPersen;
  if (p == null) return '-';
  final bulat = p.round();
  return bulat > 0 ? '+$bulat%' : '$bulat%';
}

Color _warnaPerubahan(TrenItemLaporan t) {
  if (t.baru) return AppColors.primaryDark;
  final p = t.perubahanPersen;
  if (p == null || p.round() == 0) return AppColors.textSecondary;
  return p > 0 ? AppColors.primaryDark : AppColors.dangerText;
}
