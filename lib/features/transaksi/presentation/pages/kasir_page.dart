import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/barcode_scan_page.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../produk/domain/produk.dart';
import '../../../produk/presentation/providers/produk_providers.dart';
import '../../../shift/presentation/providers/shift_providers.dart';
import '../../../stok/domain/stok_item.dart';
import '../../../stok/presentation/providers/stok_providers.dart';
import '../providers/harga_keranjang_provider.dart' show pengaturanOutletProvider;
import '../providers/keranjang_provider.dart';
import '../providers/transaksi_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

class KasirPage extends ConsumerWidget {
  const KasirPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletId = ref.watch(currentOutletIdProvider);
    final shiftAktif = ref.watch(shiftTerbukaProvider(outletId));
    final jumlahPesananTersimpan =
        ref.watch(pesananTersimpanProvider).maybeWhen(data: (v) => v.length, orElse: () => 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir'),
        actions: [
          // F3.E.2 - badge jumlah pesanan tersimpan (open bill), SELALU
          // ditampilkan (tidak digate fitur apa pun - cuma pemilihan meja
          // yang digate 'tipe_order').
          IconButton(
            key: const Key('kasirForm.pesananTersimpan'),
            onPressed: () => context.push('/kasir/pesanan-tersimpan'),
            icon: Badge(
              label: Text('$jumlahPesananTersimpan'),
              isLabelVisible: jumlahPesananTersimpan > 0,
              child: const Icon(Icons.bookmark_border),
            ),
          ),
        ],
      ),
      body: shiftAktif.when(
        data: (shift) => shift == null
            ? EmptyState(
                icon: Icons.point_of_sale_outlined,
                message: 'Buka shift dulu sebelum mulai transaksi',
                action: FilledButton(
                  onPressed: () => context.push('/shift/buka'),
                  child: const Text('Buka Shift'),
                ),
              )
            : const _KasirGrid(),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat shift: $error')),
      ),
    );
  }
}

class _KasirGrid extends ConsumerStatefulWidget {
  const _KasirGrid();

  @override
  ConsumerState<_KasirGrid> createState() => _KasirGridState();
}

class _KasirGridState extends ConsumerState<_KasirGrid> {
  String _kataCari = '';

  Future<void> _scan() async {
    final hasil = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const BarcodeScanPage()),
    );
    if (hasil == null || !mounted) return;

    final produkAktif = await ref.read(produkAktifProvider.future);
    final match = produkAktif.firstWhereOrNull((p) => p.barcode == hasil || p.sku == hasil);
    if (match == null) {
      if (mounted) {
        showAppToast(context,
            message: 'Produk dengan kode "$hasil" tidak ditemukan', variant: ToastVariant.warning);
      }
      return;
    }
    ref.read(keranjangProvider.notifier).tambah(match);
  }

  /// Kuncinya adanya SATU titik cek ini - sebelumnya `tambah()` di
  /// KeranjangNotifier tidak pernah membatasi qty sama sekali (bug nyata:
  /// stok tersisa 4, tetap bisa ditambah sampai 32). `izinkan_stok_minus`
  /// (pengaturan_outlet) SUDAH ada kolomnya & disync dari server, tapi
  /// sebelumnya TIDAK PERNAH dibaca di mana pun di app - kolomnya
  /// mubazir. Dibalas null = boleh tambah, non-null = stok TERSEDIA saat
  /// ini (dipakai pesan toast).
  double? _stokTersediaJikaMentok({
    required Produk produk,
    required StokItem? stok,
    required double qtyDimintaSetelahnya,
    required bool izinkanStokMinus,
  }) {
    if (!produk.lacakStok || izinkanStokMinus) return null;
    final tersedia = stok?.jumlah ?? 0;
    return qtyDimintaSetelahnya > tersedia ? tersedia : null;
  }

  void _tambahKeKeranjang({
    required Produk produk,
    required StokItem? stok,
    required double qtySaatIni,
    required bool izinkanStokMinus,
  }) {
    final tersedia = _stokTersediaJikaMentok(
      produk: produk,
      stok: stok,
      qtyDimintaSetelahnya: qtySaatIni + 1,
      izinkanStokMinus: izinkanStokMinus,
    );
    if (tersedia != null) {
      showAppToast(
        context,
        message: tersedia <= 0
            ? 'Stok "${produk.nama}" habis'
            : 'Stok "${produk.nama}" tidak cukup - sisa ${tersedia.toStringAsFixed(0)}',
        variant: ToastVariant.warning,
      );
      return;
    }
    ref.read(keranjangProvider.notifier).tambah(produk);
  }

  @override
  Widget build(BuildContext context) {
    final outletId = ref.watch(currentOutletIdProvider);
    final produkAktif = ref.watch(produkAktifProvider);
    final stokOutlet = ref.watch(stokOutletProvider(outletId));
    final keranjang = ref.watch(keranjangProvider);
    final subtotal = ref.watch(subtotalKeranjangProvider);
    final belumSync = ref.watch(transaksiBelumSyncCountProvider);
    final totalQty = keranjang.fold<double>(0, (sum, item) => sum + item.qty);
    final izinkanStokMinus = ref
        .watch(pengaturanOutletProvider(outletId))
        .maybeWhen(data: (v) => v?.izinkanStokMinus ?? true, orElse: () => true);

    final stokByProdukId = {
      for (final item in stokOutlet.maybeWhen(data: (v) => v, orElse: () => const []))
        item.produkId: item,
    };

    return Column(
      children: [
        belumSync.maybeWhen(
          data: (jumlah) => jumlah == 0
              ? const SizedBox.shrink()
              : Container(
                  width: double.infinity,
                  color: AppColors.warningBg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    'Offline · $jumlah transaksi menunggu sync. Kasir tetap jalan.',
                    style: AppTypography.secondary.copyWith(
                      color: AppColors.warningTextStrong,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.sm),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Cari produk atau SKU',
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Scan barcode',
                onPressed: _scan,
              ),
            ),
            onChanged: (value) => setState(() => _kataCari = value.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: produkAktif.when(
            data: (items) {
              final tampil = _kataCari.isEmpty
                  ? items
                  : items
                      .where((p) =>
                          p.nama.toLowerCase().contains(_kataCari) ||
                          (p.sku?.toLowerCase().contains(_kataCari) ?? false))
                      .toList();

              if (tampil.isEmpty) {
                return const EmptyState(icon: Icons.inventory_2_outlined, message: 'Belum ada produk');
              }

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xs,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 0.82,
                ),
                itemCount: tampil.length,
                itemBuilder: (context, index) {
                  final produk = tampil[index];
                  final diKeranjang = keranjang.firstWhereOrNull((item) => item.produkId == produk.id);
                  final stok = stokByProdukId[produk.id];
                  return _ProdukGridTile(
                    produk: produk,
                    stok: stok,
                    qtyDiKeranjang: diKeranjang?.qty,
                    onTap: () => _tambahKeKeranjang(
                      produk: produk,
                      stok: stok,
                      qtySaatIni: diKeranjang?.qty ?? 0,
                      izinkanStokMinus: izinkanStokMinus,
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(child: Text('Gagal memuat produk: $error')),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: Material(
              color: keranjang.isEmpty ? AppColors.borderStrong : AppColors.primary,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: keranjang.isEmpty ? null : () => context.push('/kasir/keranjang'),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Bug nyata (laporan pengguna: teks "X item" mepet ke
                      // tepi atas tombol) - Column di sini sebelumnya TIDAK
                      // diberi `mainAxisSize: min`, jadi ikut melar mengisi
                      // tinggi Row penuh (default MainAxisSize.max) dan
                      // kedua baris teks terdorong ke ATAS alih-alih berada
                      // di tengah tombol.
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${totalQty.toStringAsFixed(0)} item',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatRupiah.format(subtotal),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Lihat keranjang',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProdukGridTile extends StatelessWidget {
  const _ProdukGridTile({
    required this.produk,
    required this.stok,
    required this.qtyDiKeranjang,
    required this.onTap,
  });

  final Produk produk;
  final StokItem? stok;
  final double? qtyDiKeranjang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String stokLabel = '';
    Color stokColor = AppColors.textSecondary;
    final jumlah = stok?.jumlah;
    if (produk.lacakStok) {
      if (jumlah == null || jumlah <= 0) {
        stokLabel = 'Habis';
        stokColor = AppColors.dangerText;
      } else if (stok!.stokMenipis) {
        stokLabel = 'Sisa ${jumlah.toStringAsFixed(0)}';
        stokColor = AppColors.warningTextStrong;
      } else {
        stokLabel = 'Stok ${jumlah.toStringAsFixed(0)}';
      }
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // TIDAK lagi di-disable keras saat habis - keputusan boleh/tidak
        // sekarang satu pintu lewat _tambahKeKeranjang() (induk), yang
        // menghormati pengaturan "izinkan stok minus" per outlet (toast
        // penjelas kalau ditolak, bukan tile mati tanpa respons apa pun).
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: qtyDiKeranjang != null ? AppColors.primary : AppColors.borderDefault,
              width: qtyDiKeranjang != null ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1.3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _FotoProduk(produk: produk),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    produk.nama,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyEmphasis.copyWith(fontSize: 13),
                  ),
                  Text(_formatRupiah.format(produk.hargaJual), style: AppTypography.moneyAmount),
                  if (stokLabel.isNotEmpty)
                    Text(
                      stokLabel,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: stokColor),
                    ),
                ],
              ),
              if (qtyDiKeranjang != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: Text(
                      qtyDiKeranjang!.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Palet warna placeholder foto produk - dipilih berputar per produk (hash
/// id) supaya grid Kasir tidak monoton satu warna kalau banyak produk belum
/// punya foto sungguhan, sama prinsip visual dgn avatar berwarna di layar
/// lain.
const _paletteFotoProduk = [
  (AppColors.brownBg, AppColors.brownText),
  (AppColors.primaryTint, AppColors.primaryDark),
  (AppColors.indigoBg, AppColors.indigoText),
  (AppColors.warningBgAlt, AppColors.warningTextStrong),
];

/// Foto produk di tile Kasir - pakai foto sungguhan ([Produk.gambarUrl],
/// diisi dari image_picker di form produk) kalau ada, fallback ikon di atas
/// warna solid kalau belum.
///
/// Bug nyata (laporan pengguna: "lingkaran kosong gak ada tulisannya" di
/// grid Kasir) - sebelumnya dipakai `AvatarInitial.fromName(..., size:
/// 999)` dipaksa masuk ke kotak `AspectRatio` yang ukuran sungguhannya jauh
/// lebih kecil. `size` pada AvatarInitial dipakai LANGSUNG utk menghitung
/// fontSize (`size * 0.4` = ~400px) - teks inisialnya jadi raksasa lalu
/// abis kepotong habis oleh ClipRRect, yang nyisa cuma lingkaran warna
/// kosong. Ikon (bukan teks skala-manual) aman dari kelas bug ini krn
/// ukurannya tetap kecil apa pun ukuran kotaknya.
class _FotoProduk extends StatelessWidget {
  const _FotoProduk({required this.produk});

  final Produk produk;

  @override
  Widget build(BuildContext context) {
    final gambarUrl = produk.gambarUrl;
    if (gambarUrl != null && gambarUrl.isNotEmpty) {
      return Image.file(
        File(gambarUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final (bg, fg) = _paletteFotoProduk[produk.id.hashCode.abs() % _paletteFotoProduk.length];
    return Container(
      color: bg,
      alignment: Alignment.center,
      child: Icon(Icons.inventory_2_outlined, color: fg, size: 26),
    );
  }
}
