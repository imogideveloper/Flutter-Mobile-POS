import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';
import '../../../promo/presentation/providers/pajak_providers.dart';
import '../../../shift/presentation/providers/shift_providers.dart';
import '../../data/local/tables/metode_bayar_table.dart';
import '../../../dapur/presentation/providers/antrean_providers.dart';
import '../providers/harga_keranjang_provider.dart';
import '../providers/status_pesanan_providers.dart';
import '../providers/keranjang_provider.dart';
import '../providers/transaksi_providers.dart';

final _formatRupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
);
const _batasWaktuDetik = 5 * 60;

/// QRIS STATIS (cek manual) - tahap 4 bagian A.1: BELUM terhubung payment
/// gateway sungguhan (Midtrans/Xendit, lihat dokumen tech stack bagian
/// 3.2), jadi QR yang ditampilkan adalah kode QRIS statis milik toko (sama
/// utk semua transaksi), BUKAN kode dinamis per-transaksi. Server tidak
/// bisa tahu otomatis dana sudah masuk - kasir WAJIB membuka
/// aplikasi bank/e-wallet sendiri, cek dana masuk, baru menekan
/// konfirmasi "Saya sudah cek dana masuk" sebelum transaksi tersimpan.
/// Pembayaran ini ditandai manual lewat `pembayaran.payloadGateway`
/// (lihat _payloadKonfirmasiManual) - BUKAN webhook/polling sungguhan.
class BayarQrisPage extends ConsumerStatefulWidget {
  const BayarQrisPage({this.metodeBayarId, super.key});

  /// Id metode bayar QRIS asli (dari metode_bayar lokal, dioper lewat
  /// `extra` route - lihat bayar_page.dart) - F3.A: sebelumnya placeholder
  /// metodeBayarQrisIdProvider yang tidak match baris backend manapun.
  /// Null = fallback cari baris tipe qris sendiri (lihat initState).
  final String? metodeBayarId;

  @override
  ConsumerState<BayarQrisPage> createState() => _BayarQrisPageState();
}

const _payloadKonfirmasiManual =
    '{"metode":"qris_statis_manual","dikonfirmasi_kasir":true}';

class _BayarQrisPageState extends ConsumerState<BayarQrisPage> {
  Timer? _timer;
  int _detikSisa = _batasWaktuDetik;
  bool _memproses = false;
  bool _sudahCekDanaMasuk = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_detikSisa <= 1) {
        timer.cancel();
        setState(() => _detikSisa = 0);
        return;
      }
      setState(() => _detikSisa -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _mmss {
    final menit = _detikSisa ~/ 60;
    final detik = _detikSisa % 60;
    return '${menit.toString().padLeft(2, '0')}:${detik.toString().padLeft(2, '0')}';
  }

  Future<void> _cekStatus(int total) async {
    if (!_sudahCekDanaMasuk) return;

    final outletId = ref.read(currentOutletIdProvider);
    final tokoId = ref.read(currentTokoIdProvider);
    final penggunaId = ref.read(currentPenggunaIdProvider);
    if (penggunaId == null) return;

    final shift = await ref.read(shiftTerbukaProvider(outletId).future);
    if (shift == null) {
      if (mounted) {
        showAppToast(context, message: 'Shift tidak aktif', variant: ToastVariant.warning);
      }
      return;
    }

    setState(() => _memproses = true);
    try {
      // SATU mesin hitung yang sama dgn yang ditampilkan di layar ini
      // (lihat build() di bawah) - tahap 3a bagian A.
      final hasilHarga = ref.read(hasilHargaKeranjangProvider);
      final metodeBayarId = widget.metodeBayarId ??
          ref
              .read(metodeBayarAktifProvider)
              .value
              ?.where((m) => m.tipe == MetodeBayarTipe.qris)
              .firstOrNull
              ?.id;
      if (metodeBayarId == null) {
        if (mounted) {
          showAppToast(context, message: 'Metode QRIS belum diatur', variant: ToastVariant.warning);
        }
        return;
      }
      final pelangganId = ref.read(keranjangPelangganIdProvider);
      final poinDitukar = ref.read(keranjangPoinDitukarProvider);
      final diskonPoin = ref.read(diskonPoinKeranjangProvider);
      final hasil = await ref
          .read(transaksiRepositoryProvider)
          .checkout(
            buatNomorAntrean: await siapkanNomorAntrean(ref),
            statusAwal: await statusPesananAwal(ref),
            tokoId: tokoId,
            outletId: outletId,
            shiftId: shift.id,
            penggunaId: penggunaId,
            metodeBayarId: metodeBayarId,
            items: ref.read(keranjangProvider),
            hasil: hasilHarga,
            totalBayar: total,
            pelangganId: pelangganId,
            tipeOrderId: ref.read(keranjangTipeOrderIdProvider),
            catatan: ref.read(keranjangCatatanProvider),
            promo: ref.read(keranjangPromoProvider),
            payloadGateway: _payloadKonfirmasiManual,
            gantikanPesananTersimpanId: ref.read(draftPesananDibukaProvider),
            daftarPajakAktif: ref
                .read(pajakAktifProvider(tokoId))
                .maybeWhen(data: (v) => v, orElse: () => const []),
            poinDitukar: poinDitukar,
            diskonPoin: diskonPoin,
          );
      if (poinDitukar > 0 && pelangganId != null) {
        await ref.read(pelangganRepositoryProvider).catatPoin(
              pelangganId: pelangganId,
              transaksiId: hasil.id,
              delta: -poinDitukar,
              keterangan: 'Poin ditukar untuk diskon checkout',
            );
      }
      ref.read(keranjangProvider.notifier).kosongkan();
      if (mounted) context.pushReplacement('/kasir/struk', extra: hasil);
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(totalSetelahPoinProvider);
    final qrData =
        'POS-MOCK|total=$total|ts=${DateTime.now().millisecondsSinceEpoch}';

    return Scaffold(
      appBar: AppBar(title: const Text('QRIS statis (cek manual)')),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('bayarQrisPage.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Text('Total tagihan', style: AppTypography.secondary),
              Text(
                _formatRupiah.format(total),
                style: AppTypography.headerTitle.copyWith(fontSize: 32),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                child: Column(
                  children: [
                    Text(
                      'KASIR · OUTLET PUSAT',
                      style: AppTypography.bodyEmphasis.copyWith(
                        letterSpacing: 0.4,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    QrImageView(
                      data: qrData,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Bisa dibayar dari semua e-wallet dan m-banking',
                      style: AppTypography.secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD97A1E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      _detikSisa > 0
                          ? 'Menunggu pembayaran · berlaku $_mmss'
                          : 'Kode kedaluwarsa',
                      style: AppTypography.secondary.copyWith(
                        color: AppColors.warningTextStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'QR di atas statis (sama utk semua transaksi) - belum terhubung '
                'payment gateway sungguhan. Buka aplikasi bank/e-wallet Anda '
                'sendiri utk memastikan dana sudah masuk sebelum lanjut.',
                textAlign: TextAlign.center,
                style: AppTypography.secondary,
              ),
              const SizedBox(height: AppSpacing.md),
              CheckboxListTile(
                key: const Key('bayarQrisPage.konfirmasiCekDana'),
                controlAffinity: ListTileControlAffinity.leading,
                tileColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.borderDefault),
                ),
                value: _sudahCekDanaMasuk,
                onChanged: (value) =>
                    setState(() => _sudahCekDanaMasuk = value ?? false),
                title: const Text('Saya sudah cek dana masuk'),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Ganti metode'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _memproses || !_sudahCekDanaMasuk
                          ? null
                          : () => _cekStatus(total),
                      child: Text(_memproses ? 'Memeriksa...' : 'Cek status'),
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
