import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/avatar_initial.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../pelanggan/domain/pelanggan.dart';
import '../../../promo/presentation/providers/pajak_providers.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';
import '../../../pelanggan/presentation/widgets/pelanggan_picker_sheet.dart';
import '../../../shift/presentation/providers/shift_providers.dart';
import '../../data/local/tables/metode_bayar_table.dart';
import '../providers/harga_keranjang_provider.dart';
import '../providers/keranjang_provider.dart';
import '../providers/transaksi_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

/// Kasbon (tahap 3b-1) - bayar sebagian/tidak sama sekali di awal, sisanya
/// ditagih belakangan (lihat PiutangListPage/PelunasanPage). Wajib pilih
/// pelanggan (aturan #1) - DP (bayar sebagian > 0 di awal) butuh fitur
/// tambahan 'dp_kasbon' (aturan #2), tanpa itu field DP dikunci ke 0 lewat
/// FiturTerkunci di bawah.
class BayarKasbonPage extends ConsumerStatefulWidget {
  const BayarKasbonPage({super.key});

  @override
  ConsumerState<BayarKasbonPage> createState() => _BayarKasbonPageState();
}

class _BayarKasbonPageState extends ConsumerState<BayarKasbonPage> {
  final _formKey = GlobalKey<FormState>();
  final _dpController = TextEditingController();
  final _jatuhTempoHariController = TextEditingController(text: '7');
  bool _menyimpan = false;

  @override
  void dispose() {
    _dpController.dispose();
    _jatuhTempoHariController.dispose();
    super.dispose();
  }

  Future<void> _pilihPelanggan() async {
    final pelangganAktif = await ref.read(pelangganAktifProvider.future);
    if (!mounted) return;
    final dipilih = await showModalBottomSheet<Pelanggan?>(
      context: context,
      isScrollControlled: true,
      // wajibPilih: true - tidak ada opsi "Tanpa pelanggan" (aturan #1).
      builder: (context) => PelangganPickerSheet(daftar: pelangganAktif, wajibPilih: true),
    );
    if (dipilih != null) {
      ref.read(keranjangPelangganIdProvider.notifier).state = dipilih.id;
      setState(() {});
    }
  }

  Future<void> _simpan(int total) async {
    if (!_formKey.currentState!.validate()) return;

    final pelangganId = ref.read(keranjangPelangganIdProvider);
    if (pelangganId == null) {
      showAppToast(context, message: 'Kasbon wajib memilih pelanggan dulu', variant: ToastVariant.warning);
      return;
    }

    final outletId = ref.read(currentOutletIdProvider);
    final tokoId = ref.read(currentTokoIdProvider);
    final penggunaId = ref.read(currentPenggunaIdProvider);
    if (penggunaId == null) {
      showAppToast(context, message: 'Silakan login dulu', variant: ToastVariant.warning);
      return;
    }

    final shift = await ref.read(shiftTerbukaProvider(outletId).future);
    if (shift == null) {
      if (mounted) {
        showAppToast(context, message: 'Shift tidak aktif', variant: ToastVariant.warning);
      }
      return;
    }

    setState(() => _menyimpan = true);
    try {
      final hasilHarga = ref.read(hasilHargaKeranjangProvider);
      final dp = parseRupiahInput(_dpController.text) ?? 0;
      final hariJatuhTempo = int.tryParse(_jatuhTempoHariController.text) ?? 7;

      // DP kasbon (kalau diisi) dianggap selalu tunai - metode bayar
      // dinamis dari metode_bayar lokal (F3.A), bukan placeholder lagi.
      // metodeBayarId cuma dipakai checkout() kalau dp>0 (lihat
      // TransaksiRepository.checkout - totalBayar==0 tidak bikin baris
      // Pembayaran sama sekali), jadi null di sini aman utk kasbon murni.
      final metodeTunai = ref
          .read(metodeBayarAktifProvider)
          .value
          ?.where((m) => m.tipe == MetodeBayarTipe.tunai)
          .firstOrNull;
      if (dp > 0 && metodeTunai == null) {
        if (mounted) {
          showAppToast(context, message: 'Metode Tunai belum diatur', variant: ToastVariant.warning);
        }
        return;
      }

      final poinDitukar = ref.read(keranjangPoinDitukarProvider);
      final diskonPoin = ref.read(diskonPoinKeranjangProvider);
      final hasil = await ref.read(transaksiRepositoryProvider).checkout(
            tokoId: tokoId,
            outletId: outletId,
            shiftId: shift.id,
            penggunaId: penggunaId,
            metodeBayarId: metodeTunai?.id ?? '',
            items: ref.read(keranjangProvider),
            hasil: hasilHarga,
            totalBayar: dp,
            pelangganId: pelangganId,
            tipeOrderId: ref.read(keranjangTipeOrderIdProvider),
            catatan: ref.read(keranjangCatatanProvider),
            promo: ref.read(keranjangPromoProvider),
            jatuhTempoHari: hariJatuhTempo,
            gantikanPesananTersimpanId: ref.read(draftPesananDibukaProvider),
            daftarPajakAktif: ref
                .read(pajakAktifProvider(tokoId))
                .maybeWhen(data: (v) => v, orElse: () => const []),
            poinDitukar: poinDitukar,
            diskonPoin: diskonPoin,
          );
      if (poinDitukar > 0) {
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
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(totalSetelahPoinProvider);
    final pelangganId = ref.watch(keranjangPelangganIdProvider);
    final pelangganAktif = ref.watch(pelangganAktifProvider);
    final pelanggan = pelangganAktif.maybeWhen(
      data: (items) => items.where((p) => p.id == pelangganId).firstOrNull,
      orElse: () => null,
    );
    final dp = parseRupiahInput(_dpController.text) ?? 0;
    final sisa = total - dp;

    return Scaffold(
      appBar: AppBar(title: const Text('Kasbon')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('bayarKasbonForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Column(
                  children: [
                    Text('Total tagihan', style: AppTypography.secondary),
                    Text(
                      _formatRupiah.format(total),
                      style: AppTypography.headerTitle.copyWith(fontSize: 36),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                key: const Key('bayarKasbonForm.pelanggan'),
                onTap: _pilihPelanggan,
                child: Row(
                  children: [
                    AvatarInitial.fromName(pelanggan?.nama ?? '?'),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        pelanggan?.nama ?? 'Pilih pelanggan (wajib)',
                        style: AppTypography.bodyEmphasis.copyWith(
                          color: pelanggan == null ? AppColors.dangerText : null,
                        ),
                      ),
                    ),
                    Text(
                      pelanggan == null ? 'Pilih' : 'Ganti',
                      style: AppTypography.bodyEmphasis.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Bayar di muka (DP) - opsional', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
              const SizedBox(height: AppSpacing.sm),
              FiturTerkunci(
                kode: 'dp_kasbon',
                child: TextFormField(
                  key: const Key('bayarKasbonForm.dp'),
                  controller: _dpController,
                  decoration: const InputDecoration(prefixText: 'Rp ', hintText: '0'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final nilai = parseRupiahInput(value ?? '');
                    if (nilai != null && nilai >= total) {
                      return 'Kalau bayar penuh, pakai menu Tunai';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Jatuh tempo (hari)', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('bayarKasbonForm.jatuhTempoHari'),
                controller: _jatuhTempoHariController,
                decoration: const InputDecoration(suffixText: 'hari'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final hari = int.tryParse(value ?? '');
                  if (hari == null || hari <= 0) return 'Isi jumlah hari yang valid';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Dibayar sekarang', style: AppTypography.bodyEmphasis),
                        Text(_formatRupiah.format(dp)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sisa tagihan', style: AppTypography.bodyEmphasis),
                        Text(
                          _formatRupiah.format(sisa),
                          style: AppTypography.headerTitle.copyWith(
                            fontSize: 20,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                height: 54,
                child: FilledButton(
                  key: const Key('bayarKasbonForm.simpan'),
                  onPressed: _menyimpan ? null : () => _simpan(total),
                  child: Text(_menyimpan ? 'Memproses...' : 'Catat kasbon'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
