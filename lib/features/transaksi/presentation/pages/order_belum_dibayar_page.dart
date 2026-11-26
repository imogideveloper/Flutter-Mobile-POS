import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auto_sync.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../shift/presentation/providers/shift_providers.dart';
import '../../data/local/tables/metode_bayar_table.dart' show MetodeBayarTipe;
import '../../data/local/tables/transaksi_table.dart';
import '../providers/transaksi_providers.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _jam = DateFormat('d MMM HH:mm', 'id_ID');

/// Order yang sudah diterima tetapi belum (lunas) dibayar - hanya yang dibuat lewat
/// "Terima Order (bayar nanti)" (IMOGI no. 27), bukan kasbon. Terbaru lebih dulu.
List<TransaksiRow> filterOrderBelumDibayar(List<TransaksiRow> semua) => [
      for (final t in semua)
        if (t.bayarBelakangan && t.status == TransaksiStatus.selesai && t.statusBayar != StatusBayarTransaksi.lunas) t,
    ];

final orderBelumDibayarProvider = StreamProvider<List<TransaksiRow>>((ref) {
  final outletId = ref.watch(currentOutletIdProvider);
  return ref.watch(transaksiDaoProvider).watchTransaksiOutlet(outletId).map(filterOrderBelumDibayar);
});

/// Daftar order yang menunggu dibayar, dengan tombol Bayar untuk mencatat pelunasan
/// (penuh atau sebagian) - kas masuk ke shift yang sedang terbuka.
class OrderBelumDibayarPage extends ConsumerWidget {
  const OrderBelumDibayarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(orderBelumDibayarProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Order belum dibayar')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (daftar) {
          if (daftar.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'Tidak ada order yang menunggu pembayaran.',
            );
          }
          final total = daftar.fold<int>(0, (a, t) => a + t.sisaTagihan);
          return ListView(
            key: const Key('orderBelumDibayar.daftar'),
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Text('${daftar.length} order, total ${_rupiah.format(total)}', style: AppTypography.secondary),
              const SizedBox(height: AppSpacing.md),
              for (final t in daftar) ...[
                _KartuOrder(order: t),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _KartuOrder extends ConsumerWidget {
  const _KartuOrder({required this.order});

  final TransaksiRow order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tanggal = DateTime.fromMillisecondsSinceEpoch(order.tanggal, isUtc: true).toLocal();
    return AppCard(
      key: Key('orderBelumDibayar.kartu.${order.id}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      order.nomorAntrean != null ? 'Antrean ${order.nomorAntrean}' : order.nomorStruk,
                      style: AppTypography.bodyEmphasis,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (order.statusBayar == StatusBayarTransaksi.sebagian)
                      const AppBadge(label: 'Dibayar sebagian', variant: BadgeVariant.warning),
                  ],
                ),
                Text(_jam.format(tanggal), style: AppTypography.secondary),
                Text('Sisa ${_rupiah.format(order.sisaTagihan)} dari ${_rupiah.format(order.total)}',
                    style: AppTypography.body.copyWith(color: AppColors.warningTextStrong)),
              ],
            ),
          ),
          FilledButton(
            key: Key('orderBelumDibayar.bayar.${order.id}'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _SheetBayar(order: order),
            ),
            child: const Text('Bayar'),
          ),
        ],
      ),
    );
  }
}

class _SheetBayar extends ConsumerStatefulWidget {
  const _SheetBayar({required this.order});

  final TransaksiRow order;

  @override
  ConsumerState<_SheetBayar> createState() => _SheetBayarState();
}

class _SheetBayarState extends ConsumerState<_SheetBayar> {
  late final _jumlahController = TextEditingController(text: widget.order.sisaTagihan.toString());
  String? _metodeId;
  bool _menyimpan = false;

  @override
  void dispose() {
    _jumlahController.dispose();
    super.dispose();
  }

  Future<void> _catat(List<MetodeBayarRow> metode) async {
    final jumlah = parseRupiahInput(_jumlahController.text) ?? 0;
    if (_metodeId == null) {
      showAppToast(context, message: 'Pilih metode pembayaran', variant: ToastVariant.warning);
      return;
    }
    if (jumlah <= 0 || jumlah > widget.order.sisaTagihan) {
      showAppToast(
        context,
        message: 'Jumlah harus antara 1 dan sisa tagihan (${_rupiah.format(widget.order.sisaTagihan)})',
        variant: ToastVariant.warning,
      );
      return;
    }
    final outletId = ref.read(currentOutletIdProvider);
    final shift = await ref.read(shiftTerbukaProvider(outletId).future);
    if (shift == null) {
      if (mounted) showAppToast(context, message: 'Shift tidak aktif', variant: ToastVariant.warning);
      return;
    }
    setState(() => _menyimpan = true);
    try {
      await ref.read(transaksiRepositoryProvider).catatPembayaranKasbon(
            transaksiId: widget.order.id,
            metodeBayarId: _metodeId!,
            shiftId: shift.id,
            jumlah: jumlah,
          );
      // Pelunasan langsung dikirim ke server (dulu menunggu sync berkala sampai 5 menit; temuan uji kasbon).
      picuSyncSetelahTransaksi(ref);
      if (mounted) {
        Navigator.of(context).pop();
        showAppToast(
          context,
          message: jumlah == widget.order.sisaTagihan ? 'Order lunas' : 'Pembayaran sebagian dicatat',
          variant: ToastVariant.success,
        );
      }
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hanya metode manual (tanpa gateway): QRIS dinamis butuh alur sendiri dan belum tersedia di sini.
    final metode = (ref.watch(metodeBayarAktifProvider).value ?? const <MetodeBayarRow>[])
        .where((m) => !m.butuhGateway && m.tipe != MetodeBayarTipe.qris)
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          key: const Key('orderBelumDibayar.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bayar order', style: AppTypography.cardTitle),
            Text('Sisa ${_rupiah.format(widget.order.sisaTagihan)}', style: AppTypography.secondary),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final m in metode)
                  ChoiceChip(
                    key: Key('orderBelumDibayar.metode.${m.id}'),
                    label: Text(m.nama),
                    selected: _metodeId == m.id,
                    onSelected: (_) => setState(() => _metodeId = m.id),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('orderBelumDibayar.jumlah'),
              controller: _jumlahController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jumlah dibayar (Rp)'),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('orderBelumDibayar.catat'),
              onPressed: _menyimpan ? null : () => _catat(metode),
              child: Text(_menyimpan ? 'Menyimpan...' : 'Catat pembayaran'),
            ),
          ],
        ),
      ),
    );
  }
}
