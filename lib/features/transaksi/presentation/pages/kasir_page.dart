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
import '../../../../core/widgets/qty_dialog.dart';
import '../../../../core/widgets/qty_stepper.dart';
import '../../../produk/domain/produk.dart';
import '../../../produk/domain/kategori.dart';
import '../../../produk/presentation/providers/kategori_providers.dart';
import '../../../produk/presentation/providers/produk_providers.dart';
import '../../domain/filter_produk_kasir.dart';
import '../../../shift/presentation/providers/shift_providers.dart';
import '../../../stok/domain/stok_item.dart';
import '../../../stok/presentation/providers/stok_providers.dart';
import '../../domain/item_keranjang.dart';
import '../providers/harga_keranjang_provider.dart' show pengaturanOutletProvider;
import '../widgets/pilih_tambahan_sheet.dart';
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
  /// Tab kategori (IMOGI no. 36): null = semua kategori.
  String? _kategoriId;

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
    await _tambahDenganPilihan(match);
  }

  /// Produk yang punya varian/tambahan (IMOGI no. 42) membuka pemilih dulu;
  /// kasir yang membatalkan pemilih tidak menambah apa pun.
  Future<void> _tambahDenganPilihan(Produk produk) async {
    final grup = await ref.read(grupTambahanProdukProvider(produk.id).future);
    if (!mounted) return;
    if (grup.isEmpty) {
      ref.read(keranjangProvider.notifier).tambah(produk);
      return;
    }
    final pilihan = await tampilkanPilihTambahan(context, produk: produk, grup: grup);
    if (pilihan == null || !mounted) return;
    ref.read(keranjangProvider.notifier).tambah(produk, modifiers: pilihan);
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

  List<ItemKeranjang> _baris(String produkId) =>
      ref.read(keranjangProvider).where((i) => i.produkId == produkId).toList();

  /// Minus di kartu produk: mengurangi baris TERAKHIR produk itu. Produk dengan beberapa
  /// pilihan tambahan diatur per baris di keranjang agar pilihan lain tidak ikut berkurang.
  void _kurangi(Produk produk) {
    final baris = _baris(produk.id);
    if (baris.isEmpty) return;
    final terakhir = baris.last;
    ref.read(keranjangProvider.notifier).ubahQty(terakhir.kunciBaris, terakhir.qty - 1);
  }

  Future<void> _isiJumlah({
    required Produk produk,
    required StokItem? stok,
    required bool izinkanStokMinus,
  }) async {
    final baris = _baris(produk.id);
    if (baris.length != 1) {
      showAppToast(context,
          message: 'Produk ini punya beberapa pilihan. Atur jumlah per pilihan di keranjang.',
          variant: ToastVariant.info);
      context.push('/kasir/keranjang');
      return;
    }
    final hasil = await tampilkanIsiJumlah(context, judul: produk.nama, awal: baris.single.qty);
    if (hasil == null || !mounted) return;
    final tersedia = hasil > 0
        ? _stokTersediaJikaMentok(
            produk: produk, stok: stok, qtyDimintaSetelahnya: hasil, izinkanStokMinus: izinkanStokMinus)
        : null;
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
    ref.read(keranjangProvider.notifier).ubahQty(baris.single.kunciBaris, hasil);
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
    _tambahDenganPilihan(produk);
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
        produkAktif.maybeWhen(
          data: (items) => _BarisKategori(
            kategori: kategoriDenganProduk(
              ref.watch(kategoriAktifProvider(ref.watch(currentTokoIdProvider))).value ?? const [],
              items,
            ),
            dipilih: _kategoriId,
            onPilih: (id) => setState(() => _kategoriId = id),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        Expanded(
          child: produkAktif.when(
            data: (items) {
              // Kategori yang terpilih tetapi sudah tidak punya produk (mis. produk dinonaktifkan): anggap Semua.
              final kategoriAda = _kategoriId != null && items.any((p) => p.kategoriId == _kategoriId);
              final tampil = saringProdukKasir(items, kataCari: _kataCari, kategoriId: kategoriAda ? _kategoriId : null);

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
                  childAspectRatio: 0.7,
                ),
                itemCount: tampil.length,
                itemBuilder: (context, index) {
                  final produk = tampil[index];
                  // Satu produk bisa punya beberapa baris (pilihan tambahan berbeda).
                  final barisProduk = keranjang.where((item) => item.produkId == produk.id).toList();
                  final qtyProduk = barisProduk.isEmpty ? null : barisProduk.fold<double>(0, (a, i) => a + i.qty);
                  final stok = stokByProdukId[produk.id];
                  return _ProdukGridTile(
                    produk: produk,
                    stok: stok,
                    qtyDiKeranjang: qtyProduk,
                    onTap: () => _tambahKeKeranjang(
                      produk: produk,
                      stok: stok,
                      qtySaatIni: qtyProduk ?? 0,
                      izinkanStokMinus: izinkanStokMinus,
                    ),
                    onKurang: () => _kurangi(produk),
                    onIsiJumlah: () => _isiJumlah(produk: produk, stok: stok, izinkanStokMinus: izinkanStokMinus),
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
    required this.onKurang,
    required this.onIsiJumlah,
  });

  final Produk produk;
  final StokItem? stok;
  final double? qtyDiKeranjang;
  final VoidCallback onTap;
  final VoidCallback onKurang;
  final VoidCallback onIsiJumlah;

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
                  const Spacer(),
                  // Pola umum POS: produk yang sudah dipilih menampilkan - jumlah + langsung di kartu.
                  if (qtyDiKeranjang != null)
                    Center(
                      child: QtyStepper(
                        qty: qtyDiKeranjang!,
                        onIncrement: onTap,
                        onDecrement: onKurang,
                        onQtyTap: onIsiJumlah,
                      ),
                    ),
                ],
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

/// Baris tab kategori di atas daftar produk kasir. Hanya tampil bila ada minimal satu kategori
/// yang berisi produk; "Semua" selalu pertama.
class _BarisKategori extends StatelessWidget {
  const _BarisKategori({required this.kategori, required this.dipilih, required this.onPilih});

  final List<Kategori> kategori;
  final String? dipilih;
  final ValueChanged<String?> onPilih;

  @override
  Widget build(BuildContext context) {
    if (kategori.isEmpty) return const SizedBox.shrink();
    final aktif = kategori.any((k) => k.id == dipilih) ? dipilih : null;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              key: const Key('kasir.kategori.semua'),
              label: const Text('Semua'),
              selected: aktif == null,
              onSelected: (_) => onPilih(null),
            ),
          ),
          for (final k in kategori)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                key: Key('kasir.kategori.${k.id}'),
                label: Text(k.nama),
                selected: aktif == k.id,
                onSelected: (_) => onPilih(k.id),
              ),
            ),
        ],
      ),
    );
  }
}
