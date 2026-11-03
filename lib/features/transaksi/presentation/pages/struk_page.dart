import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/providers/toko_profile_provider.dart';
import '../../../../core/struk/cetak_struk_helper.dart';
import '../../../../core/struk/kirim_whatsapp_helper.dart';
import '../../../../core/struk/penyusun_struk.dart' as struk;
import '../../../../core/struk/struk_snapshot.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/hasil_transaksi.dart';
import '../providers/harga_keranjang_provider.dart';
import '../providers/transaksi_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _formatWaktu = DateFormat('dd/MM/yyyy HH:mm');
final _formatTanggal = DateFormat('dd/MM/yyyy');

/// Layar sukses setelah bayar, sesuai mockup "Pembayaran berhasil" - gaya
/// struk monospace meniru hasil cetak thermal. Cetak struk & Kirim WhatsApp
/// SENGAJA distub (belum ada integrasi printer Bluetooth/WhatsApp API).
/// Void transaksi TIDAK ada di sini (per mockup) - itu ada di layar Riwayat
/// > detail transaksi, karena void dilakukan belakangan, bukan tepat
/// setelah transaksi dibuat.
class StrukPage extends ConsumerStatefulWidget {
  const StrukPage({required this.hasil, super.key});

  final HasilTransaksi hasil;

  @override
  ConsumerState<StrukPage> createState() => _StrukPageState();
}

class _StrukPageState extends ConsumerState<StrukPage> {
  bool _mencetak = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _simpanSnapshotStruk());
    WidgetsBinding.instance.addPostFrameCallback((_) => _cetakOtomatisJikaAktif());
    WidgetsBinding.instance.addPostFrameCallback((_) => _ingatkanStokMenipis());
  }

  /// Temuan A.2 (tahap 5) - simpan snapshot struk SEKALI di sini, TERLEPAS
  /// dari apakah kasir benar2 mencetak atau tidak - data+pengaturan yang
  /// membentuk struk SAAT transaksi dibuat harus terekam skr juga, bukan
  /// cuma saat tombol cetak ditekan (kasir mungkin tidak pernah cetak,
  /// tapi "cetak ulang" nanti tetap harus identik dgn apa yg SEHARUSNYA
  /// tercetak saat itu).
  Future<void> _simpanSnapshotStruk() async {
    final (data, pengaturan) = await _bangunStrukData();
    final json = strukSnapshotKeJson(data, pengaturan);
    await ref.read(transaksiRepositoryProvider).simpanSnapshotStruk(widget.hasil.id, jsonEncode(json));
  }

  /// Toast proaktif tepat setelah checkout utk produk yang saldonya jadi
  /// <= batas minimum GARA-GARA transaksi ini (lihat
  /// TransaksiRepository.checkout) - sebelumnya cuma ada badge pasif di
  /// halaman Stok/Lainnya/Produk yang baru kelihatan kalau kasir sempat
  /// buka halaman itu, jadi gampang kelewat.
  void _ingatkanStokMenipis() {
    final produk = widget.hasil.produkStokMenipis;
    if (produk.isEmpty || !mounted) return;
    final daftar = produk.length <= 3
        ? produk.join(', ')
        : '${produk.take(3).join(', ')}, +${produk.length - 3} lainnya';
    showAppToast(
      context,
      title: 'Stok menipis',
      message: daftar,
      variant: ToastVariant.warning,
    );
  }

  Future<(struk.StrukData, struk.PengaturanStrukData)> _bangunStrukData() async {
    final hasil = widget.hasil;
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
      nomorStruk: hasil.nomorStruk,
      tanggalEpochMs: hasil.tanggal,
      items: [
        for (final item in hasil.items)
          struk.ItemStruk(
            namaProduk: item.namaProduk,
            qty: item.qty,
            hargaSatuan: item.hargaSatuan,
            subtotal: item.subtotal,
          ),
      ],
      subtotal: hasil.subtotal,
      diskonPromo: hasil.totalDiskon,
      namaPromo: hasil.namaPromo,
      rincianPajak: hasil.rincianPajak,
      total: hasil.total,
      pembayaran: hasil.totalBayar > 0
          ? [struk.PembayaranStruk(labelMetode: 'Dibayar', jumlah: hasil.totalBayar)]
          : [],
      kembalian: hasil.kembalian,
      statusBayar: hasil.statusBayar,
      sisaTagihan: hasil.sisaTagihan,
      jatuhTempoEpochMs: hasil.jatuhTempo,
    );
    return (data, pengaturan);
  }

  Future<List<struk.BarisStruk>> _bangunBarisStruk() async {
    final (data, pengaturan) = await _bangunStrukData();
    return struk.susunStrukTransaksi(data: data, pengaturan: pengaturan);
  }

  Future<void> _cetakOtomatisJikaAktif() async {
    if (!await perluCetakOtomatis(ref)) return;
    await _cetak(diam: true);
  }

  Future<void> _cetak({bool diam = false}) async {
    if (_mencetak) return;
    setState(() => _mencetak = true);
    try {
      final outletId = ref.read(currentOutletIdProvider);
      final pengaturanOutlet = await ref.read(pengaturanOutletProvider(outletId).future);
      final baris = await _bangunBarisStruk();
      final status = await cetakStruk(ref, baris, tampilkanLogo: pengaturanOutlet?.tampilLogo ?? false);
      if (!mounted) return;
      if (diam && status == StatusCetak.printerBelumDiatur) return; // auto-print diam2 - tidak perlu ganggu kalau memang belum diatur
      showAppToast(context, message: labelStatusCetak(status), variant: variantStatusCetak(status));
    } finally {
      if (mounted) setState(() => _mencetak = false);
    }
  }

  Future<void> _kirimWhatsApp() async {
    final outletId = ref.read(currentOutletIdProvider);
    final pengaturanOutlet = await ref.read(pengaturanOutletProvider(outletId).future);
    final baris = await _bangunBarisStruk();
    final lebar = (pengaturanOutlet?.lebarKertasMm ?? 58) == 80 ? 48 : 32;
    final teks = struk.renderTeksStruk(baris, lebar).join('\n');
    await kirimStrukWhatsApp(teks: teks);
  }

  @override
  Widget build(BuildContext context) {
    final hasil = widget.hasil;
    final tanggal = DateTime.fromMillisecondsSinceEpoch(hasil.tanggal, isUtc: true).toLocal();
    final kasbon = hasil.statusBayar != 'lunas';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.lg),
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 30),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                kasbon ? 'Transaksi tercatat (kasbon)' : 'Pembayaran berhasil',
                style: AppTypography.cardTitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(kasbon ? 'Sisa tagihan  ' : 'Kembalian  ', style: AppTypography.secondary),
                  Text(
                    _formatRupiah.format(kasbon ? hasil.sisaTagihan : hasil.kembalian),
                    style: AppTypography.headerTitle.copyWith(
                      fontSize: 26,
                      color: kasbon ? AppColors.warningTextStrong : AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.borderDefault),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.55,
                        color: AppColors.textPrimary,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(hasil.nomorStruk, textAlign: TextAlign.center),
                          const SizedBox(height: AppSpacing.sm),
                          _garisPutus(),
                          const SizedBox(height: AppSpacing.sm),
                          Text(_formatWaktu.format(tanggal)),
                          const SizedBox(height: AppSpacing.sm),
                          _garisPutus(),
                          const SizedBox(height: AppSpacing.sm),
                          for (final item in hasil.items) ...[
                            Text(item.namaProduk),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('  ${item.qty.toStringAsFixed(0)} x ${_formatRupiah.format(item.hargaSatuan)}'),
                                Text(_formatRupiah.format(item.subtotal)),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          _garisPutus(),
                          const SizedBox(height: AppSpacing.sm),
                          _baris('Subtotal', hasil.subtotal),
                          if (hasil.totalDiskon > 0)
                            _baris(hasil.namaPromo ?? 'Promo', -hasil.totalDiskon),
                          for (final rincian in hasil.rincianPajak) _baris(rincian.nama, rincian.jumlah),
                          _baris('TOTAL', hasil.total, tebal: true),
                          _baris('Dibayar', hasil.totalBayar),
                          if (kasbon) ...[
                            _baris('Sisa tagihan', hasil.sisaTagihan),
                            if (hasil.jatuhTempo != null)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Jatuh tempo'),
                                  Text(
                                    _formatTanggal.format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        hasil.jatuhTempo!,
                                        isUtc: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ] else
                            _baris('Kembali', hasil.kembalian),
                          const SizedBox(height: AppSpacing.sm),
                          _garisPutus(),
                          const SizedBox(height: AppSpacing.sm),
                          const Text('Terima kasih, sampai jumpa lagi!', textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('strukPage.cetakStruk'),
                      onPressed: _mencetak ? null : () => _cetak(),
                      icon: const Icon(Icons.print_outlined, size: 20),
                      label: Text(_mencetak ? 'Mencetak...' : 'Cetak struk'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('strukPage.kirimWhatsApp'),
                      onPressed: _kirimWhatsApp,
                      icon: const Icon(Icons.chat_outlined, size: 20),
                      label: const Text('Kirim WhatsApp'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => context.go('/kasir'),
                  child: const Text('Transaksi baru'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _garisPutus() => const SizedBox(
        height: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.textTertiary, width: 1)),
          ),
        ),
      );

  Widget _baris(String label, int jumlah, {bool tebal = false}) {
    final style = tebal ? const TextStyle(fontWeight: FontWeight.w600, fontSize: 13) : null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(_formatRupiah.format(jumlah), style: style),
      ],
    );
  }
}
