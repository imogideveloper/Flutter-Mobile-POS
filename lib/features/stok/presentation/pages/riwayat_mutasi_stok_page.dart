import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/mutasi_item.dart';
import '../../domain/riwayat_mutasi.dart';
import '../providers/stok_providers.dart';

final _formatQty = NumberFormat.decimalPattern('id_ID');
final _formatWaktu = DateFormat('d MMM yyyy HH:mm', 'id_ID');

/// Argumen rute riwayat mutasi satu produk.
class RiwayatMutasiArgs {
  const RiwayatMutasiArgs({required this.produkId, required this.produkNama});

  final String produkId;
  final String produkNama;
}

/// Riwayat mutasi stok satu produk (IMOGI no. 49): setiap penjualan, pembelian, opname, dan
/// penyesuaian beserta saldo sesudahnya, supaya selisih stok bisa ditelusuri.
class RiwayatMutasiStokPage extends ConsumerStatefulWidget {
  const RiwayatMutasiStokPage({super.key, required this.produkId, required this.produkNama});

  final String produkId;
  final String produkNama;

  @override
  ConsumerState<RiwayatMutasiStokPage> createState() => _RiwayatMutasiStokPageState();
}

class _RiwayatMutasiStokPageState extends ConsumerState<RiwayatMutasiStokPage> {
  FilterMutasi _filter = FilterMutasi.semua;

  @override
  Widget build(BuildContext context) {
    final outletId = ref.watch(currentOutletIdProvider);
    final riwayat = ref.watch(riwayatMutasiProdukProvider((outletId, widget.produkId)));
    final saldoSaatIni = ref.watch(stokOutletProvider(outletId)).maybeWhen(
          data: (items) => items.where((i) => i.produkId == widget.produkId).fold<double?>(
              null, (a, i) => (a ?? 0) + i.jumlah),
          orElse: () => null,
        );

    return Scaffold(
      appBar: AppBar(title: Text('Riwayat stok · ${widget.produkNama}')),
      body: riwayat.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat riwayat: $e')),
        data: (semua) {
          if (semua.isEmpty) {
            return const EmptyState(icon: Icons.history, message: 'Belum ada mutasi untuk produk ini');
          }
          final tampil = saringMutasi(semua, _filter);
          final ringkas = ringkasMutasi(semua);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              AppCard(
                child: Row(
                  children: [
                    _Angka(
                      label: 'Saldo sekarang',
                      nilai: saldoSaatIni == null ? '-' : _formatQty.format(saldoSaatIni),
                      kunci: 'riwayatStok.saldo',
                    ),
                    _Angka(label: 'Total masuk', nilai: '+${_formatQty.format(ringkas.masuk)}', kunci: 'riwayatStok.masuk', warna: AppColors.primaryDark),
                    _Angka(label: 'Total keluar', nilai: '-${_formatQty.format(ringkas.keluar)}', kunci: 'riwayatStok.keluar', warna: AppColors.dangerText),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final f in FilterMutasi.values)
                    ChoiceChip(
                      key: Key('riwayatStok.filter.${f.name}'),
                      label: Text(switch (f) {
                        FilterMutasi.semua => 'Semua',
                        FilterMutasi.masuk => 'Masuk',
                        FilterMutasi.keluar => 'Keluar',
                      }),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (tampil.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text('Tidak ada mutasi pada filter ini', style: AppTypography.secondary),
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < tampil.length; i++) _BarisMutasi(item: tampil[i], garis: i < tampil.length - 1),
                    ],
                  ),
                ),
              if (semua.length >= 300)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text('Menampilkan 300 mutasi terbaru.', style: AppTypography.secondary),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Angka extends StatelessWidget {
  const _Angka({required this.label, required this.nilai, required this.kunci, this.warna});

  final String label;
  final String nilai;
  final String kunci;
  final Color? warna;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: AppTypography.secondary, textAlign: TextAlign.center),
          Text(nilai, key: Key(kunci), style: AppTypography.bodyEmphasis.copyWith(color: warna)),
        ],
      ),
    );
  }
}

class _BarisMutasi extends StatelessWidget {
  const _BarisMutasi({required this.item, required this.garis});

  final MutasiItem item;
  final bool garis;

  @override
  Widget build(BuildContext context) {
    final warna = item.masuk ? AppColors.primaryDark : AppColors.dangerText;
    final waktu = _formatWaktu.format(DateTime.fromMillisecondsSinceEpoch(item.createdAt, isUtc: true).toLocal());
    return Container(
      key: Key('riwayatStok.baris.${item.id}'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: garis
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderDefault)))
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(labelMutasi(item.jenis), style: AppTypography.bodyEmphasis),
                Text(waktu, style: AppTypography.secondary),
                if (item.catatan != null && item.catatan!.isNotEmpty)
                  Text(item.catatan!, style: AppTypography.secondary),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${item.masuk ? '+' : ''}${_formatQty.format(item.qty)}',
                  style: AppTypography.bodyEmphasis.copyWith(color: warna)),
              if (item.saldoSetelah != null)
                Text('Saldo ${_formatQty.format(item.saldoSetelah)}', style: AppTypography.secondary),
            ],
          ),
        ],
      ),
    );
  }
}
