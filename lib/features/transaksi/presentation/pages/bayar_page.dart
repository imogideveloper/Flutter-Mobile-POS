import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';
import '../../../promo/presentation/providers/pajak_providers.dart';
import '../../../shift/presentation/providers/shift_providers.dart';
import '../../data/local/tables/metode_bayar_table.dart';
import '../../domain/split_pembayaran.dart';
import '../providers/harga_keranjang_provider.dart';
import '../providers/keranjang_provider.dart';
import '../providers/transaksi_providers.dart';

final _formatRupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
);

const _ikonMetode = {
  MetodeBayarTipe.tunai: Icons.payments_outlined,
  MetodeBayarTipe.qris: Icons.qr_code_2,
  MetodeBayarTipe.kartu: Icons.credit_card_outlined,
  MetodeBayarTipe.transfer: Icons.account_balance_outlined,
  MetodeBayarTipe.ewallet: Icons.account_balance_wallet_outlined,
  MetodeBayarTipe.lainnya: Icons.more_horiz,
};

/// Layar Pembayaran - grid metode dibaca DINAMIS dari metode_bayar lokal
/// (F3.A, bukan hardcode Tunai/QRIS lagi + Kartu/Transfer stub seperti
/// sebelumnya). QRIS tetap pindah ke BayarQrisPage (butuh QR code+timer
/// sendiri); Tunai/Kartu/Transfer dibayar langsung di sini. "Bayar campur"
/// mendukung split 2 metode sekaligus dlm satu transaksi.
class BayarPage extends ConsumerStatefulWidget {
  const BayarPage({super.key});

  @override
  ConsumerState<BayarPage> createState() => _BayarPageState();
}

class _BayarPageState extends ConsumerState<BayarPage> {
  final _formKey = GlobalKey<FormState>();
  final _uangDiterimaController = TextEditingController();
  final _nomorReferensiController = TextEditingController();
  final _empatDigitController = TextEditingController();
  final _splitJumlahAController = TextEditingController();
  final _splitJumlahBController = TextEditingController();
  bool _menyimpan = false;
  String? _metodeTerpilihId;
  bool _modeSplit = false;
  String? _splitMetodeAId;
  String? _splitMetodeBId;

  @override
  void dispose() {
    _uangDiterimaController.dispose();
    _nomorReferensiController.dispose();
    _empatDigitController.dispose();
    _splitJumlahAController.dispose();
    _splitJumlahBController.dispose();
    super.dispose();
  }

  void _pesan(String teks) {
    if (!mounted) return;
    showAppToast(context, message: teks, variant: ToastVariant.warning);
  }

  Future<void> _bayar(int total, List<MetodeBayarRow> daftar) async {
    List<SplitPembayaran>? splitPembayaran;
    String metodeBayarIdUtama;
    int totalBayar;

    if (_modeSplit) {
      final a = parseRupiahInput(_splitJumlahAController.text);
      final b = parseRupiahInput(_splitJumlahBController.text);
      if (_splitMetodeAId == null || _splitMetodeBId == null || a == null || b == null) {
        _pesan('Lengkapi kedua metode dan jumlahnya');
        return;
      }
      if (_splitMetodeAId == _splitMetodeBId) {
        _pesan('Pilih dua metode yang berbeda utk bayar campur');
        return;
      }
      if (a + b != total) {
        _pesan('Total split (${_formatRupiah.format(a + b)}) harus persis sama dgn total tagihan');
        return;
      }
      splitPembayaran = [
        SplitPembayaran(metodeBayarId: _splitMetodeAId!, jumlah: a),
        SplitPembayaran(metodeBayarId: _splitMetodeBId!, jumlah: b),
      ];
      metodeBayarIdUtama = _splitMetodeAId!;
      totalBayar = total;
    } else {
      if (!_formKey.currentState!.validate()) return;
      if (_metodeTerpilihId == null) {
        _pesan('Pilih metode pembayaran');
        return;
      }
      final metode = daftar.firstWhere((m) => m.id == _metodeTerpilihId);
      metodeBayarIdUtama = metode.id;
      if (metode.tipe == MetodeBayarTipe.tunai) {
        totalBayar = parseRupiahInput(_uangDiterimaController.text) ?? 0;
      } else {
        // Kartu/Transfer manual (F3.A) - tanpa gateway, bayar pas (tidak
        // ada kembalian) + nomor referensi/4 digit akhir kartu opsional.
        totalBayar = total;
        final nomorReferensi = _nomorReferensiController.text.trim();
        final empatDigit = _empatDigitController.text.trim();
        splitPembayaran = [
          SplitPembayaran(
            metodeBayarId: metode.id,
            jumlah: total,
            nomorReferensi: nomorReferensi.isEmpty ? null : nomorReferensi,
            empatDigitAkhirKartu: empatDigit.isEmpty ? null : empatDigit,
          ),
        ];
      }
    }

    final outletId = ref.read(currentOutletIdProvider);
    final tokoId = ref.read(currentTokoIdProvider);
    final penggunaId = ref.read(currentPenggunaIdProvider);
    if (penggunaId == null) {
      _pesan('Silakan login dulu');
      return;
    }

    final shift = await ref.read(shiftTerbukaProvider(outletId).future);
    if (shift == null) {
      _pesan('Shift tidak aktif');
      return;
    }

    setState(() => _menyimpan = true);
    try {
      // SATU mesin hitung yang sama dgn yang ditampilkan di layar ini
      // (lihat build() di bawah) - dibaca lagi di sini (bukan dioper dari
      // build) supaya tidak ada jendela balapan antara render terakhir
      // dan saat tombol ditekan (tahap 3a bagian A).
      final hasilHarga = ref.read(hasilHargaKeranjangProvider);
      final pelangganId = ref.read(keranjangPelangganIdProvider);
      final poinDitukar = ref.read(keranjangPoinDitukarProvider);
      final diskonPoin = ref.read(diskonPoinKeranjangProvider);
      final hasil = await ref
          .read(transaksiRepositoryProvider)
          .checkout(
            tokoId: tokoId,
            outletId: outletId,
            shiftId: shift.id,
            penggunaId: penggunaId,
            metodeBayarId: metodeBayarIdUtama,
            items: ref.read(keranjangProvider),
            hasil: hasilHarga,
            totalBayar: totalBayar,
            pelangganId: pelangganId,
            tipeOrderId: ref.read(keranjangTipeOrderIdProvider),
            catatan: ref.read(keranjangCatatanProvider),
            promo: ref.read(keranjangPromoProvider),
            splitPembayaran: splitPembayaran,
            gantikanPesananTersimpanId: ref.read(draftPesananDibukaProvider),
            daftarPajakAktif: ref
                .read(pajakAktifProvider(tokoId))
                .maybeWhen(data: (v) => v, orElse: () => const []),
            poinDitukar: poinDitukar,
            diskonPoin: diskonPoin,
          );
      // Modul 10 - TransaksiRepository.checkout() TIDAK kenal PelangganDao
      // (lihat docstring di sana), jadi pemanggil (di sini) yang wajib
      // mengurangi poin pelanggan setelah checkout sukses.
      if (poinDitukar > 0 && pelangganId != null) {
        await ref.read(pelangganRepositoryProvider).catatPoin(
              pelangganId: pelangganId,
              transaksiId: hasil.id,
              delta: -poinDitukar,
              keterangan: 'Poin ditukar untuk diskon checkout',
            );
      }
      ref.read(keranjangProvider.notifier).kosongkan();
      if (mounted) {
        context.pushReplacement('/kasir/struk', extra: hasil);
      }
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(totalSetelahPoinProvider);
    final metodeAsync = ref.watch(metodeBayarAktifProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: metodeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat metode bayar: $error')),
        data: (daftar) {
          // Default pilih Tunai begitu daftar sudah ada & belum ada pilihan -
          // addPostFrameCallback supaya tidak setState di tengah build().
          if (_metodeTerpilihId == null && !_modeSplit && daftar.isNotEmpty) {
            final tunai = daftar.where((m) => m.tipe == MetodeBayarTipe.tunai).firstOrNull;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _metodeTerpilihId == null) {
                setState(() => _metodeTerpilihId = (tunai ?? daftar.first).id);
              }
            });
          }

          final metodeTerpilih =
              daftar.where((m) => m.id == _metodeTerpilihId).firstOrNull;
          final uang = parseRupiahInput(_uangDiterimaController.text);
          final kembalian = uang == null ? null : uang - total;

          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              key: const Key('bayarForm.scrollView'),
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
                  if (daftar.isEmpty)
                    Text(
                      'Belum ada metode pembayaran - atur dulu di Lainnya > Metode pembayaran.',
                      style: AppTypography.secondary,
                    )
                  else
                    Row(
                      children: [
                        for (final metode in daftar) ...[
                          Expanded(
                            child: _MetodeTile(
                              label: metode.tipe == MetodeBayarTipe.qris
                                  ? '${metode.nama}\n(cek manual)'
                                  : metode.nama,
                              icon: _ikonMetode[metode.tipe] ?? Icons.payments_outlined,
                              selected: !_modeSplit && metode.id == _metodeTerpilihId,
                              onTap: () {
                                if (metode.tipe == MetodeBayarTipe.qris) {
                                  context.push('/kasir/bayar/qris', extra: metode.id);
                                  return;
                                }
                                setState(() {
                                  _modeSplit = false;
                                  _metodeTerpilihId = metode.id;
                                });
                              },
                            ),
                          ),
                          if (metode != daftar.last) const SizedBox(width: AppSpacing.sm),
                        ],
                      ],
                    ),
                  if (daftar.length >= 2) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('bayarForm.toggleSplit'),
                        onPressed: () => setState(() {
                          _modeSplit = !_modeSplit;
                          if (_modeSplit) _metodeTerpilihId = null;
                        }),
                        icon: Icon(_modeSplit ? Icons.close : Icons.call_split, size: 18),
                        label: Text(_modeSplit ? 'Batal bayar campur' : 'Bayar campur (2 metode)'),
                      ),
                    ),
                  ],
                  // Kasbon (tahap 3b-1) - baris terpisah drpd grid metode di
                  // atas (bukan metode pembayaran dalam arti gateway, tapi
                  // kesepakatan "bayar belakangan") - dibuka ke halaman
                  // sendiri (BayarKasbonPage), sama pola dgn QRIS.
                  const SizedBox(height: AppSpacing.sm),
                  FiturTerkunci(
                    kode: 'kasbon',
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const Key('bayarForm.kasbon'),
                        onPressed: () => context.push('/kasir/bayar/kasbon'),
                        icon: const Icon(Icons.schedule_outlined, size: 18),
                        label: const Text('Kasbon (bayar dengan utang)'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_modeSplit)
                    _SplitPembayaranForm(
                      daftar: daftar,
                      total: total,
                      metodeAId: _splitMetodeAId,
                      metodeBId: _splitMetodeBId,
                      jumlahAController: _splitJumlahAController,
                      jumlahBController: _splitJumlahBController,
                      onMetodeAChanged: (id) => setState(() => _splitMetodeAId = id),
                      onMetodeBChanged: (id) => setState(() => _splitMetodeBId = id),
                    )
                  else if (metodeTerpilih != null && metodeTerpilih.tipe == MetodeBayarTipe.tunai) ...[
                    Text('Uang diterima', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const Key('bayarForm.uangDiterima'),
                      controller: _uangDiterimaController,
                      decoration: const InputDecoration(prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final nilai = parseRupiahInput(value ?? '');
                        if (nilai == null) return 'Uang diterima wajib diisi angka';
                        if (nilai < total) return 'Uang diterima kurang dari total';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        for (final nominal in {total, total + 25000, _bulatkanAtas(total)})
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.xs),
                              child: OutlinedButton(
                                onPressed: () => setState(
                                  () => _uangDiterimaController.text = formatRupiahDigits(nominal),
                                ),
                                child: Text(
                                  nominal == total ? 'Uang pas' : formatRupiahDigits(nominal),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Kembalian', style: AppTypography.bodyEmphasis),
                          Text(
                            kembalian == null || kembalian < 0 ? '-' : _formatRupiah.format(kembalian),
                            style: AppTypography.headerTitle.copyWith(
                              fontSize: 22,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (metodeTerpilih != null) ...[
                    // Kartu/Transfer manual - bayar pas, tidak ada kembalian.
                    Text('Konfirmasi ${metodeTerpilih.nama}', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const Key('bayarForm.nomorReferensi'),
                      controller: _nomorReferensiController,
                      decoration: const InputDecoration(labelText: 'Nomor referensi (opsional)'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const Key('bayarForm.empatDigitAkhir'),
                      controller: _empatDigitController,
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '4 digit akhir kartu (opsional)',
                        counterText: '',
                        helperText: 'JANGAN masukkan nomor kartu lengkap',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Diterima pas', style: AppTypography.bodyEmphasis),
                          Text(
                            _formatRupiah.format(total),
                            style: AppTypography.headerTitle.copyWith(
                              fontSize: 22,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: const Key('bayarForm.selesaikan'),
                      onPressed: _menyimpan ? null : () => _bayar(total, daftar),
                      child: Text(_menyimpan ? 'Memproses...' : 'Selesaikan pembayaran'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  int _bulatkanAtas(int total) {
    const kelipatan = 50000;
    final hasil = ((total ~/ kelipatan) + 1) * kelipatan;
    return hasil;
  }
}

class _SplitPembayaranForm extends StatelessWidget {
  const _SplitPembayaranForm({
    required this.daftar,
    required this.total,
    required this.metodeAId,
    required this.metodeBId,
    required this.jumlahAController,
    required this.jumlahBController,
    required this.onMetodeAChanged,
    required this.onMetodeBChanged,
  });

  final List<MetodeBayarRow> daftar;
  final int total;
  final String? metodeAId;
  final String? metodeBId;
  final TextEditingController jumlahAController;
  final TextEditingController jumlahBController;
  final ValueChanged<String?> onMetodeAChanged;
  final ValueChanged<String?> onMetodeBChanged;

  @override
  Widget build(BuildContext context) {
    final a = parseRupiahInput(jumlahAController.text);
    final b = parseRupiahInput(jumlahBController.text);
    final sisa = (a ?? 0) + (b ?? 0) - total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Bayar campur - 2 metode', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
        const SizedBox(height: AppSpacing.sm),
        _BarisSplit(
          key: const Key('bayarForm.split.a'),
          daftar: daftar,
          metodeId: metodeAId,
          jumlahController: jumlahAController,
          onMetodeChanged: onMetodeAChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        _BarisSplit(
          key: const Key('bayarForm.split.b'),
          daftar: daftar,
          metodeId: metodeBId,
          jumlahController: jumlahBController,
          onMetodeChanged: onMetodeBChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Selisih dari total', style: AppTypography.bodyEmphasis),
              Text(
                NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0).format(sisa),
                style: AppTypography.headerTitle.copyWith(
                  fontSize: 18,
                  color: sisa == 0 ? AppColors.primaryDark : AppColors.dangerText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarisSplit extends StatelessWidget {
  const _BarisSplit({
    super.key,
    required this.daftar,
    required this.metodeId,
    required this.jumlahController,
    required this.onMetodeChanged,
  });

  final List<MetodeBayarRow> daftar;
  final String? metodeId;
  final TextEditingController jumlahController;
  final ValueChanged<String?> onMetodeChanged;

  @override
  Widget build(BuildContext context) {
    final labelKey = (key as ValueKey<String>).value;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            key: Key('$labelKey.metode'),
            initialValue: metodeId,
            decoration: const InputDecoration(labelText: 'Metode'),
            items: [
              for (final m in daftar.where((m) => m.tipe != MetodeBayarTipe.qris))
                DropdownMenuItem(value: m.id, child: Text(m.nama, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onMetodeChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: TextFormField(
            key: Key('$labelKey.jumlah'),
            controller: jumlahController,
            decoration: const InputDecoration(prefixText: 'Rp '),
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
          ),
        ),
      ],
    );
  }
}

class _MetodeTile extends StatelessWidget {
  const _MetodeTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryTint : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderDefault,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? AppColors.primaryDark : AppColors.textPrimary,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.primaryDark : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
