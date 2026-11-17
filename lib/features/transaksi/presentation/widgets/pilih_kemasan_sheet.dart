import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../produk/domain/produk.dart';
import '../../domain/item_keranjang.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

/// Hasil pilih satuan jual (IMOGI no. 43): [kemasan] null = satuan dasar produk.
class PilihanSatuan {
  const PilihanSatuan(this.kemasan);

  final KemasanPilihan? kemasan;
}

String _isi(double isi) => isi == isi.roundToDouble() ? isi.toStringAsFixed(0) : isi.toString();

/// Lembar pilih satuan jual produk yang punya kemasan. Mengembalikan pilihan, atau null bila dibatalkan.
Future<PilihanSatuan?> tampilkanPilihKemasan(
  BuildContext context, {
  required Produk produk,
  required List<KemasanPilihan> kemasan,
}) {
  return showModalBottomSheet<PilihanSatuan>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jual ${produk.nama} per', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.md),
            _Baris(
              key: const Key('pilihKemasan.dasar'),
              judul: 'Satuan',
              keterangan: 'Per satuan dasar',
              harga: produk.hargaJual,
              onTap: () => Navigator.pop(ctx, const PilihanSatuan(null)),
            ),
            for (final k in kemasan)
              _Baris(
                key: Key('pilihKemasan.${k.nama}'),
                judul: k.nama,
                keterangan: 'Isi ${_isi(k.isi)} satuan',
                harga: k.harga,
                onTap: () => Navigator.pop(ctx, PilihanSatuan(k)),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Baris extends StatelessWidget {
  const _Baris({super.key, required this.judul, required this.keterangan, required this.harga, required this.onTap});

  final String judul;
  final String keterangan;
  final int harga;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderDefault),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(judul, style: AppTypography.bodyEmphasis),
                      Text(keterangan, style: AppTypography.secondary),
                    ],
                  ),
                ),
                Text(_rupiah.format(harga), style: AppTypography.bodyEmphasis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
