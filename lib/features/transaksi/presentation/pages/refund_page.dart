import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/struk/cetak_struk_helper.dart';
import '../../../../core/struk/penyusun_struk.dart' as struk;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/detail_transaksi.dart';
import '../providers/transaksi_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

class _ItemRefundable {
  const _ItemRefundable({
    required this.itemTransaksiId,
    required this.namaProduk,
    required this.hargaSatuan,
    required this.sisaBisaDirefund,
  });

  final String itemTransaksiId;
  final String namaProduk;
  final int hargaSatuan;
  final num sisaBisaDirefund;
}

/// F3.D - refund sebagian/penuh, SELALU online (lihat docs/aturan_harga.md
/// bagian Refund utk alasan: butuh id item_transaksi SUNGGUHAN dari
/// server, bukan id lokal HP) - PIN approval ('transaksi.refund') sudah
/// divalidasi SEBELUM halaman ini dibuka (lihat transaksi_detail_page.dart,
/// pola sama dgn Void), [disetujuiOleh] dioper apa adanya.
class RefundPage extends ConsumerStatefulWidget {
  const RefundPage({required this.transaksi, required this.disetujuiOleh, super.key});

  final DetailTransaksi transaksi;
  final String disetujuiOleh;

  @override
  ConsumerState<RefundPage> createState() => _RefundPageState();
}

class _RefundPageState extends ConsumerState<RefundPage> {
  final _alasanController = TextEditingController();
  final Map<String, num> _qtyDipilih = {};
  bool _kembalikanStok = true;
  String? _metodeBayarId;
  bool _memproses = false;
  List<_ItemRefundable>? _items;
  String? _errorMuat;

  @override
  void initState() {
    super.initState();
    _muatItem();
  }

  @override
  void dispose() {
    _alasanController.dispose();
    super.dispose();
  }

  Future<void> _muatItem() async {
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) {
        setState(() => _errorMuat = 'Device belum pairing ke backend - refund butuh koneksi online');
        return;
      }
      final rows = await ref.read(backendApiProvider).ambilItemRefundable(
            accessToken: sesi.accessToken,
            transaksiId: widget.transaksi.id,
          );
      if (!mounted) return;
      setState(() {
        _items = [
          for (final r in rows)
            _ItemRefundable(
              itemTransaksiId: r['item_transaksi_id'] as String,
              namaProduk: r['nama_produk'] as String,
              hargaSatuan: double.parse(r['harga_satuan'].toString()).round(),
              sisaBisaDirefund: double.parse(r['sisa_bisa_direfund'].toString()),
            ),
        ];
      });
    } on BackendException catch (e) {
      // Temuan#4 - refund SELALU online (lihat docstring kelas ini); kalau
      // offline, tampilkan pesan netral "butuh koneksi" (bukan error
      // teknis) - lihat BackendException.tidakAdaKoneksi.
      if (mounted) {
        setState(() => _errorMuat = e.tidakAdaKoneksi
            ? 'Refund butuh koneksi internet'
            : e.statusCode == 404
                ? 'Transaksi ini belum ada di server. Sinkronkan dulu dari menu Lainnya, lalu coba lagi.'
                : e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _errorMuat = 'Gagal memuat item: $e');
    }
  }

  int get _totalRefundEstimasi {
    final items = _items;
    if (items == null) return 0;
    var total = 0;
    for (final item in items) {
      final qty = _qtyDipilih[item.itemTransaksiId] ?? 0;
      total += (qty * item.hargaSatuan).round();
    }
    return total;
  }

  Future<void> _submit() async {
    final items = _items;
    if (items == null) return;
    final dipilih = _qtyDipilih.entries.where((e) => e.value > 0).toList();
    if (dipilih.isEmpty) {
      showAppToast(context, message: 'Pilih minimal 1 item utk direfund', variant: ToastVariant.warning);
      return;
    }
    if (_alasanController.text.trim().isEmpty) {
      showAppToast(context, message: 'Alasan refund wajib diisi', variant: ToastVariant.warning);
      return;
    }

    setState(() => _memproses = true);
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) throw const BackendException(message: 'Device belum pairing ke backend');

      final hasil = await ref.read(backendApiProvider).buatRefund(
            accessToken: sesi.accessToken,
            transaksiId: widget.transaksi.id,
            body: {
              'alasan': _alasanController.text.trim(),
              'kembalikan_stok': _kembalikanStok,
              if (_metodeBayarId != null) 'metode_bayar_id': _metodeBayarId,
              'items': [
                for (final e in dipilih) {'item_transaksi_id': e.key, 'qty': e.value.toString()},
              ],
            },
          );

      if (!mounted) return;
      showAppToast(
        context,
        message: 'Refund berhasil - ${_formatRupiah.format(double.parse(hasil['total'].toString()))}',
        variant: ToastVariant.success,
      );

      await _tawarkanCetak(hasil, items, dipilih);
      if (mounted) Navigator.of(context).pop(true);
    } on BackendException catch (e) {
      final pesan = e.tidakAdaKoneksi ? 'Refund butuh koneksi internet' : 'Refund gagal: ${e.message}';
      if (mounted) showAppToast(context, message: pesan, variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  Future<void> _tawarkanCetak(
    Map<String, dynamic> hasilRefund,
    List<_ItemRefundable> items,
    List<MapEntry<String, num>> dipilih,
  ) async {
    final itemById = {for (final i in items) i.itemTransaksiId: i};
    final strukItems = [
      for (final e in dipilih)
        struk.ItemStruk(
          namaProduk: itemById[e.key]!.namaProduk,
          qty: e.value.toDouble(),
          hargaSatuan: itemById[e.key]!.hargaSatuan,
          subtotal: (e.value * itemById[e.key]!.hargaSatuan).round(),
        ),
    ];
    final baris = struk.susunStrukVoidRefund(
      namaOutlet: widget.transaksi.nomorStruk,
      nomorStruk: widget.transaksi.nomorStruk,
      adalahRefund: true,
      alasan: _alasanController.text.trim(),
      items: strukItems,
      jumlahDikembalikan: double.parse(hasilRefund['total'].toString()).round(),
      tanggalEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      pengaturan: const struk.PengaturanStrukData(lebarKertasMm: 58),
    );
    await cetakStruk(ref, baris);
  }

  @override
  Widget build(BuildContext context) {
    final metodeAktifAsync = ref.watch(metodeBayarAktifProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Refund #${widget.transaksi.nomorStruk}')),
      body: _errorMuat != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(_errorMuat!, textAlign: TextAlign.center),
              ),
            )
          : _items == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  key: const Key('refundForm.scrollView'),
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Pilih item yang direfund', style: AppTypography.cardTitle),
                      const SizedBox(height: AppSpacing.sm),
                      for (final item in _items!)
                        AppCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.namaProduk, style: AppTypography.bodyEmphasis),
                                    Text(
                                      '${_formatRupiah.format(item.hargaSatuan)} · sisa bisa direfund: ${item.sisaBisaDirefund.toStringAsFixed(0)}',
                                      style: AppTypography.secondary,
                                    ),
                                  ],
                                ),
                              ),
                              if (item.sisaBisaDirefund <= 0)
                                Text('Habis', style: AppTypography.secondary)
                              else
                                _QtyStepperRefund(
                                  key: Key('refundForm.qty.${item.itemTransaksiId}'),
                                  maksimal: item.sisaBisaDirefund,
                                  nilai: _qtyDipilih[item.itemTransaksiId] ?? 0,
                                  onChanged: (v) => setState(() => _qtyDipilih[item.itemTransaksiId] = v),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      Text('Alasan refund', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const Key('refundForm.alasan'),
                        controller: _alasanController,
                        decoration: const InputDecoration(hintText: 'Mis. barang cacat/salah pesan'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SwitchListTile(
                        key: const Key('refundForm.kembalikanStok'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Kembalikan ke stok'),
                        value: _kembalikanStok,
                        onChanged: (v) => setState(() => _kembalikanStok = v),
                      ),
                      metodeAktifAsync.maybeWhen(
                        data: (daftar) => daftar.isEmpty
                            ? const SizedBox.shrink()
                            : DropdownButtonFormField<String?>(
                                key: const Key('refundForm.metodeBayar'),
                                initialValue: _metodeBayarId,
                                decoration: const InputDecoration(labelText: 'Metode pengembalian uang (opsional)'),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('Sama seperti transaksi asal')),
                                  for (final m in daftar)
                                    DropdownMenuItem(value: m.id, child: Text(m.nama)),
                                ],
                                onChanged: (v) => setState(() => _metodeBayarId = v),
                              ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppCard(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Perkiraan refund', style: AppTypography.bodyEmphasis),
                            Text(
                              _formatRupiah.format(_totalRefundEstimasi),
                              style: AppTypography.headerTitle.copyWith(
                                fontSize: 20,
                                color: AppColors.dangerTextStrong,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Nominal akhir dihitung server (termasuk porsi diskon/pajak proporsional) '
                        '- angka di atas cuma perkiraan kasar qty×harga.',
                        style: AppTypography.secondary,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          key: const Key('refundForm.submit'),
                          onPressed: _memproses ? null : _submit,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.dangerTextStrong),
                          child: Text(_memproses ? 'Memproses...' : 'Proses refund'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _QtyStepperRefund extends StatelessWidget {
  const _QtyStepperRefund({super.key, required this.maksimal, required this.nilai, required this.onChanged});

  final num maksimal;
  final num nilai;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: nilai <= 0 ? null : () => onChanged(nilai - 1),
        ),
        SizedBox(width: 28, child: Text(nilai.toStringAsFixed(0), textAlign: TextAlign.center)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: nilai >= maksimal ? null : () => onChanged(nilai + 1),
        ),
      ],
    );
  }
}
