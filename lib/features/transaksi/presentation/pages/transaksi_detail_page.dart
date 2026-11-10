import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/pin_approval.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/providers/toko_profile_provider.dart';
import '../../../../core/struk/cetak_struk_helper.dart';
import '../../../../core/struk/penyusun_tiket_dapur.dart';
import '../../../dapur/presentation/tiket_dapur_helper.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import '../../../../core/struk/penyusun_struk.dart' as struk;
import '../../../../core/struk/struk_snapshot.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/detail_transaksi.dart';
import '../../domain/metode_bayar_label.dart';
import '../../data/local/tables/transaksi_table.dart' show TransaksiStatus;
import '../../data/transaksi_repository.dart' show TransaksiSudahDivoidException;
import '../providers/harga_keranjang_provider.dart';
import '../providers/transaksi_providers.dart';
import 'refund_page.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _formatWaktu = DateFormat('HH.mm, dd/MM/yyyy');

/// Sesuai mockup "Void transaksi" - detail transaksi lama + tombol Void +
/// Refund (F3.D, buka RefundPage - SELALU online, lihat docs/aturan_harga.md
/// bagian Refund). Alur PIN approval reuse mintaOtorisasi() yang sudah ada
/// (bukan keypad custom di mockup) - dialog PIN sudah ada & teruji, jadi
/// tidak ditulis ulang hanya demi match 1:1 visual keypad.
class TransaksiDetailPage extends ConsumerStatefulWidget {
  const TransaksiDetailPage({required this.transaksiId, super.key});

  final String transaksiId;

  @override
  ConsumerState<TransaksiDetailPage> createState() => _TransaksiDetailPageState();
}

class _TransaksiDetailPageState extends ConsumerState<TransaksiDetailPage> {
  bool _memvoid = false;
  bool _mencetak = false;

  /// "Cetak ulang" (temuan A.2, tahap 5) - SELALU tersedia (termasuk utk
  /// transaksi yang sudah di-void, beda dari Void/Refund yang cuma utk
  /// transaksi masih aktif), ditandai "** SALINAN **". Prioritas sumber
  /// data, supaya PERSIS sama dgn struk asli (bukan rekonstruksi dari
  /// data/pengaturan SAAT INI yang bisa sudah beda):
  /// 1. Snapshot LOKAL (`detail.snapshotStruk`) - transaksi dari device
  ///    ini sendiri, StrukPage sudah menyimpannya tepat setelah checkout.
  /// 2. Snapshot SERVER (`GET /transaksi/{id}`) - transaksi dari HP LAIN,
  ///    tidak pernah ada di drift lokal device ini sama sekali.
  /// 3. Fallback rekonstruksi dari [detail] + pengaturan SAAT INI -
  ///    HANYA utk transaksi lama/client lama yang belum pernah menyimpan
  ///    snapshot (keterbatasan jujur, lihat docs/aturan_harga.md) - TIDAK
  ///    dijamin identik kalau harga/pengaturan outlet berubah sejak itu.
  Future<void> _cetakUlang(DetailTransaksi detail) async {
    setState(() => _mencetak = true);
    try {
      final snapshotJson = detail.snapshotStruk ?? await _ambilSnapshotDariServer(detail.id);

      final List<struk.BarisStruk> baris;
      bool? tampilLogo;
      if (snapshotJson != null) {
        final (data: data, pengaturan: pengaturan) =
            strukSnapshotDariJson(jsonDecode(snapshotJson) as Map<String, dynamic>);
        baris = struk.susunStrukTransaksi(data: data, pengaturan: pengaturan, salinan: true);
        tampilLogo = pengaturan.tampilLogo;
      } else {
        baris = await _bangunBarisStrukFallback(detail);
      }

      final status = await cetakStruk(ref, baris, tampilkanLogo: tampilLogo ?? false);
      if (mounted) {
        showAppToast(context, message: labelStatusCetak(status), variant: variantStatusCetak(status));
      }
    } finally {
      if (mounted) setState(() => _mencetak = false);
    }
  }

  /// Cetak ulang tiket dapur dari riwayat (mis. tiket asli macet atau hilang).
  /// Isinya dibangun dari detail transaksi: menu, jumlah, dan tambahan, tanpa harga.
  Future<void> _cetakUlangTiket(DetailTransaksi detail) async {
    setState(() => _mencetak = true);
    try {
      final outletId = ref.read(currentOutletIdProvider);
      final pengaturanOutlet = await ref.read(pengaturanOutletProvider(outletId).future);
      final lebar = (pengaturanOutlet?.lebarKertasMm ?? 58) == 80 ? 48 : 32;
      final items = await itemUntukTiketDapur(ref, detail.items);
      if (items.isEmpty) {
        if (mounted) {
          showAppToast(context, message: 'Tidak ada item yang masuk tiket dapur', variant: ToastVariant.info);
        }
        return;
      }
      final baris = susunTiketDapur(
        lebar: lebar,
        data: TiketDapurData(
          nomorStruk: detail.nomorStruk,
          nomorAntrean: detail.nomorAntrean,
          tanggalEpochMs: detail.tanggal,
          items: items,
        ),
      );
      final status = await cetakStruk(ref, baris);
      if (mounted) {
        showAppToast(
          context,
          message: status == StatusCetak.berhasil ? 'Tiket dapur tercetak' : labelStatusCetak(status),
          variant: variantStatusCetak(status),
        );
      }
    } finally {
      if (mounted) setState(() => _mencetak = false);
    }
  }

  Future<String?> _ambilSnapshotDariServer(String transaksiId) async {
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) return null;
      final resp = await ref.read(backendApiProvider).ambilDetailTransaksi(
            accessToken: sesi.accessToken,
            transaksiId: transaksiId,
          );
      final snapshot = resp['snapshot_struk'];
      return snapshot == null ? null : jsonEncode(snapshot);
    } on BackendException {
      return null; // offline/gagal - turun ke fallback rekonstruksi
    }
  }

  /// Keterbatasan lama (dicatat, bukan ditutupi) - [DetailTransaksi] tidak
  /// punya rincian pajak per-baris/field kasbon lengkap, jadi reprint dari
  /// jalur ini tidak menampilkan itu, beda dari struk BARU langsung dari
  /// checkout (StrukPage, yang datanya lebih lengkap DAN sudah tersimpan
  /// sbg snapshot - jalur ini cuma dipakai kalau snapshot itu tidak ada).
  Future<List<struk.BarisStruk>> _bangunBarisStrukFallback(DetailTransaksi detail) async {
    final outletId = ref.read(currentOutletIdProvider);
    final pengaturanOutlet = await ref.read(pengaturanOutletProvider(outletId).future);
    final tokoProfile = await ref.read(tokoProfileProvider.future);

    final pengaturan = struk.PengaturanStrukData(
      headerStruk: pengaturanOutlet?.headerStruk,
      footerStruk: pengaturanOutlet?.footerStruk,
      lebarKertasMm: pengaturanOutlet?.lebarKertasMm ?? 58,
      tampilLogo: pengaturanOutlet?.tampilLogo ?? false,
      strukRingkas: pengaturanOutlet?.strukRingkas ?? false,
      pakaiNomorAntrean: pengaturanOutlet?.pakaiNomorAntrean ?? false,
    );
    final data = struk.StrukData(
      namaOutlet: tokoProfile?.namaToko ?? 'Toko',
      nomorStruk: detail.nomorStruk,
      nomorAntrean: detail.nomorAntrean,
      tanggalEpochMs: detail.tanggal,
      namaPelanggan: detail.namaPelanggan,
      items: [
        for (final item in detail.items)
          struk.ItemStruk(
            namaProduk: item.namaProduk,
            qty: item.qty,
            hargaSatuan: item.hargaSatuanFinal,
            subtotal: item.subtotal,
            modifiers: [for (final m in item.modifiers) m.nama],
          ),
      ],
      subtotal: detail.subtotal,
      diskonPromo: detail.totalDiskon,
      namaPromo: detail.namaPromo,
      total: detail.total,
      pembayaran: detail.totalBayar > 0
          ? [struk.PembayaranStruk(labelMetode: 'Dibayar', jumlah: detail.totalBayar)]
          : [],
      kembalian: detail.kembalian,
    );
    return struk.susunStrukTransaksi(data: data, pengaturan: pengaturan, salinan: true);
  }

  Future<void> _voidTransaksi(DetailTransaksi detail) async {
    final disetujuiOleh = await mintaOtorisasi(
      context: context,
      ref: ref,
      kodeIzin: 'transaksi.void',
      aksiLabel: 'Void transaksi #${detail.nomorStruk}',
    );
    if (disetujuiOleh == null) {
      if (mounted) {
        showAppToast(context, message: 'Void dibatalkan / PIN tidak valid', variant: ToastVariant.warning);
      }
      return;
    }

    if (!mounted) return;
    final alasan = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AlasanVoidSheet(detail: detail),
    );
    if (alasan == null || alasan.trim().isEmpty) return;

    setState(() => _memvoid = true);
    try {
      await ref.read(transaksiRepositoryProvider).voidTransaksiLama(
            transaksiId: detail.id,
            tokoId: ref.read(currentTokoIdProvider),
            outletId: ref.read(currentOutletIdProvider),
            alasan: alasan.trim(),
            disetujuiOleh: disetujuiOleh,
          );
      // Muat ulang detail supaya status "dibatalkan" terbaca dan tombol
      // Void/Refund hilang saat halaman dibuka lagi (BUG-013).
      ref.invalidate(detailTransaksiProvider(widget.transaksiId));
      if (mounted) {
        showAppToast(context, message: 'Transaksi dibatalkan (void)', variant: ToastVariant.success);
        Navigator.of(context).pop();
      }
    } on TransaksiSudahDivoidException {
      ref.invalidate(detailTransaksiProvider(widget.transaksiId));
      if (mounted) {
        showAppToast(context, message: 'Transaksi ini sudah di-void sebelumnya', variant: ToastVariant.warning);
      }
    } finally {
      if (mounted) setState(() => _memvoid = false);
    }
  }

  /// Refund selalu online dan memakai id item dari server, jadi transaksinya harus sudah ada
  /// di server. Mengembalikan true bila sudah tersinkron (atau berhasil disinkronkan sekarang).
  /// BUG-014: dulu transaksi yang belum tersync memunculkan "transaksi tidak ditemukan".
  Future<bool> _pastikanTersinkron(DetailTransaksi detail) async {
    Future<bool> sudah() async =>
        (await ref.read(transaksiDaoProvider).transaksiById(detail.id)).disinkronPada != null;
    if (await sudah()) return true;
    if (!mounted) return false;

    final sinkron = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transaksi belum tersinkron'),
        content: const Text(
          'Refund butuh transaksi ini sudah ada di server. Sinkronkan dulu, lalu refund bisa dilanjutkan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          FilledButton(
            key: const Key('transaksiDetail.sinkronDulu'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sinkronkan sekarang'),
          ),
        ],
      ),
    );
    if (sinkron != true || !mounted) return false;

    try {
      await ref.read(syncRepositoryProvider).jalankan();
    } on BackendException catch (e) {
      if (mounted) {
        showAppToast(
          context,
          message: e.tidakAdaKoneksi ? 'Tidak ada koneksi internet. Coba lagi saat online.' : 'Sync gagal: ${e.message}',
          variant: ToastVariant.danger,
        );
      }
      return false;
    }
    ref.invalidate(transaksiBelumSyncCountProvider);
    if (await sudah()) return true;
    if (mounted) {
      showAppToast(
        context,
        message: 'Transaksi ini belum diterima server (mungkin ditolak). Cek menu Lainnya untuk jumlah yang menunggu sync.',
        variant: ToastVariant.warning,
      );
    }
    return false;
  }

  Future<void> _refund(DetailTransaksi detail) async {
    if (!await _pastikanTersinkron(detail)) return;
    if (!mounted) return;
    final disetujuiOleh = await mintaOtorisasi(
      context: context,
      ref: ref,
      kodeIzin: 'transaksi.refund',
      aksiLabel: 'Refund transaksi #${detail.nomorStruk}',
    );
    if (disetujuiOleh == null) {
      if (mounted) {
        showAppToast(context, message: 'Refund dibatalkan / PIN tidak valid', variant: ToastVariant.warning);
      }
      return;
    }
    if (!mounted) return;

    final berhasil = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RefundPage(transaksi: detail, disetujuiOleh: disetujuiOleh),
      ),
    );
    if (berhasil == true) {
      ref.invalidate(detailTransaksiProvider(widget.transaksiId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(detailTransaksiProvider(widget.transaksiId));
    final namaMetode = ref.watch(namaMetodeBayarProvider).value ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.maybeWhen(
          data: (detail) => Text('#${detail.nomorStruk}'),
          orElse: () => const Text('Detail transaksi'),
        ),
      ),
      body: detailAsync.when(
        data: (detail) {
          final waktu = DateTime.fromMillisecondsSinceEpoch(detail.tanggal, isUtc: true).toLocal();
          final sudahVoid = detail.status == TransaksiStatus.dibatalkan;
          // Backend hanya terima refund utk status 'selesai'/'refund_sebagian'
          // (lihat refund_service.py) - 'refund' = semua qty sudah habis.
          final sudahRefundPenuh = detail.status == TransaksiStatus.refund;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_formatWaktu.format(waktu)} · ${labelMetodeBayar(detail.metodeBayarId, jumlahPembayaran: detail.jumlahPembayaran, nama: namaMetode)}'
                  '${detail.namaPelanggan != null ? ' · ${detail.namaPelanggan}' : ''}',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: AppSpacing.md),
                if (sudahVoid)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Transaksi ini sudah di-void'
                      '${detail.alasanVoid != null ? ': ${detail.alasanVoid}' : ''}',
                      style: const TextStyle(color: AppColors.dangerTextStrong, fontWeight: FontWeight.w600),
                    ),
                  ),
                AppCard(
                  child: Column(
                    children: [
                      for (final item in detail.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text('${item.namaProduk} × ${item.qty.toStringAsFixed(0)}'),
                              ),
                              Text(_formatRupiah.format(item.subtotal),
                                  style: AppTypography.bodyEmphasis),
                            ],
                          ),
                        ),
                      if (detail.totalDiskon > 0) ...[
                        const Divider(height: AppSpacing.lg),
                        _baris(detail.namaPromo ?? 'Promo', -detail.totalDiskon, muted: true),
                      ],
                      const Divider(height: AppSpacing.lg),
                      _baris('Subtotal', detail.subtotal, muted: true),
                      if (detail.totalPajak > 0) _baris('Pajak & biaya', detail.totalPajak, muted: true),
                      const Divider(height: AppSpacing.lg),
                      _baris('Total', detail.total, tebal: true),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    key: const Key('transaksiDetail.cetakUlang'),
                    onPressed: _mencetak ? null : () => _cetakUlang(detail),
                    icon: const Icon(Icons.print_outlined, size: 20),
                    label: Text(_mencetak ? 'Mencetak...' : 'Cetak ulang'),
                  ),
                ),
                if (ref.watch(featureGateProvider).value?.has('tiket_dapur') ?? false) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      key: const Key('transaksiDetail.cetakUlangTiket'),
                      onPressed: _mencetak ? null : () => _cetakUlangTiket(detail),
                      icon: const Icon(Icons.restaurant_menu, size: 20),
                      label: const Text('Cetak ulang tiket dapur'),
                    ),
                  ),
                ],
                if (!sudahVoid) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.dangerBorder),
                            foregroundColor: AppColors.dangerTextStrong,
                          ),
                          onPressed: _memvoid ? null : () => _voidTransaksi(detail),
                          child: _memvoid
                              ? const SizedBox(
                                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Void'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('transaksiDetail.refund'),
                          onPressed: sudahRefundPenuh ? null : () => _refund(detail),
                          child: const Text('Refund'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat transaksi: $error')),
      ),
    );
  }

  Widget _baris(String label, int jumlah, {bool tebal = false, bool muted = false}) {
    final style = tebal
        ? AppTypography.bodyEmphasis.copyWith(fontSize: 16)
        : muted
            ? AppTypography.secondary
            : AppTypography.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_formatRupiah.format(jumlah), style: style),
        ],
      ),
    );
  }
}

class _AlasanVoidSheet extends StatefulWidget {
  const _AlasanVoidSheet({required this.detail});

  final DetailTransaksi detail;

  @override
  State<_AlasanVoidSheet> createState() => _AlasanVoidSheetState();
}

class _AlasanVoidSheetState extends State<_AlasanVoidSheet> {
  static const _pilihan = ['Salah input', 'Pelanggan batal', 'Lainnya'];
  String? _alasanDipilih;
  final _lainnyaController = TextEditingController();

  @override
  void dispose() {
    _lainnyaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.lg,
        bottom: AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Void transaksi #${widget.detail.nomorStruk}', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_formatRupiah.format(widget.detail.total)} akan dibatalkan dan stok dikembalikan.',
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Alasan', style: AppTypography.bodyEmphasis.copyWith(fontSize: 13)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final pilihan in _pilihan)
                ChoiceChip(
                  label: Text(pilihan),
                  selected: _alasanDipilih == pilihan,
                  onSelected: (_) => setState(() => _alasanDipilih = pilihan),
                ),
            ],
          ),
          if (_alasanDipilih == 'Lainnya') ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _lainnyaController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Tulis alasan'),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _alasanDipilih == null
                  ? null
                  : () => Navigator.of(context).pop(
                        _alasanDipilih == 'Lainnya' ? _lainnyaController.text : _alasanDipilih,
                      ),
              child: const Text('Lanjutkan'),
            ),
          ),
        ],
      ),
    );
  }
}
