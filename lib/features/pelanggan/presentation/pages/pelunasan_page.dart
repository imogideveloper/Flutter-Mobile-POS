import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/providers/toko_profile_provider.dart';
import '../../../../core/struk/cetak_struk_helper.dart';
import '../../../../core/struk/penyusun_struk.dart' as struk;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../shift/presentation/providers/shift_providers.dart';
import '../../../transaksi/data/local/tables/metode_bayar_table.dart';
import '../../../transaksi/presentation/providers/harga_keranjang_provider.dart';
import '../../../transaksi/presentation/providers/transaksi_providers.dart';
import '../providers/pelanggan_providers.dart';
import '../providers/piutang_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _formatTanggal = DateFormat('dd/MM/yyyy');
const _payloadKonfirmasiManual =
    '{"metode":"qris_statis_manual","dikonfirmasi_kasir":true}';

/// Pelunasan/cicilan kasbon (tahap 3b-1) - pilih satu transaksi milik
/// pelanggan ini, isi jumlah + metode bayar, catat. Murni tulis lokal
/// (bisa offline) - disync belakangan lewat SyncRepository.
class PelunasanPage extends ConsumerStatefulWidget {
  const PelunasanPage({required this.pelangganId, super.key});

  final String pelangganId;

  @override
  ConsumerState<PelunasanPage> createState() => _PelunasanPageState();
}

class _PelunasanPageState extends ConsumerState<PelunasanPage> {
  final _formKey = GlobalKey<FormState>();
  final _jumlahController = TextEditingController();
  TransaksiRow? _dipilih;
  bool _menyimpan = false;
  bool _metodeTunai = true;
  bool _sudahCekDanaMasuk = false;

  @override
  void dispose() {
    _jumlahController.dispose();
    super.dispose();
  }

  Future<void> _cetakBukti({
    required String nomorStrukAsal,
    required int jumlahDibayar,
    required String labelMetode,
    required int sisaSetelahIni,
  }) async {
    final dialogContext = context;
    final outletId = ref.read(currentOutletIdProvider);
    final pengaturanOutlet = await ref.read(pengaturanOutletProvider(outletId).future);
    final tokoProfile = await ref.read(tokoProfileProvider.future);
    final namaPelanggan = await ref.read(pelangganByIdProvider(widget.pelangganId).future);

    final baris = struk.susunBuktiPelunasan(
      namaOutlet: tokoProfile?.namaToko ?? 'Toko',
      nomorStrukAsal: nomorStrukAsal,
      namaPelanggan: namaPelanggan ?? '-',
      jumlahDibayar: jumlahDibayar,
      labelMetode: labelMetode,
      sisaSetelahIni: sisaSetelahIni,
      tanggalEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      pengaturan: struk.PengaturanStrukData(lebarKertasMm: pengaturanOutlet?.lebarKertasMm ?? 58),
    );
    final status = await cetakStruk(ref, baris);
    if (!mounted) return;
    Navigator.of(dialogContext).pop();
    showAppToast(context, message: labelStatusCetak(status), variant: variantStatusCetak(status));
  }

  void _pilihTransaksi(TransaksiRow t) {
    setState(() {
      _dipilih = t;
      _jumlahController.text = formatRupiahDigits(t.sisaTagihan);
    });
  }

  Future<void> _simpan() async {
    final dipilih = _dipilih;
    if (dipilih == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_metodeTunai && !_sudahCekDanaMasuk) return;

    final outletId = ref.read(currentOutletIdProvider);
    final shift = await ref.read(shiftTerbukaProvider(outletId).future);
    if (shift == null) {
      if (mounted) {
        showAppToast(context, message: 'Shift tidak aktif', variant: ToastVariant.warning);
      }
      return;
    }

    setState(() => _menyimpan = true);
    try {
      final jumlah = parseRupiahInput(_jumlahController.text) ?? 0;
      // Metode bayar dinamis dari metode_bayar lokal (F3.A), bukan
      // placeholder metodeBayarTunaiIdProvider/metodeBayarQrisIdProvider
      // lagi - keduanya tidak pernah match baris backend sungguhan.
      final daftarMetode = ref.read(metodeBayarAktifProvider).value ?? [];
      final tipeDicari = _metodeTunai ? MetodeBayarTipe.tunai : MetodeBayarTipe.qris;
      final metode = daftarMetode.where((m) => m.tipe == tipeDicari).firstOrNull;
      if (metode == null) {
        if (mounted) {
          showAppToast(context,
              message: 'Metode ${_metodeTunai ? "Tunai" : "QRIS"} belum diatur', variant: ToastVariant.warning);
        }
        return;
      }
      await ref.read(transaksiRepositoryProvider).catatPembayaranKasbon(
            transaksiId: dipilih.id,
            metodeBayarId: metode.id,
            shiftId: shift.id,
            jumlah: jumlah,
            payloadGateway: _metodeTunai ? null : _payloadKonfirmasiManual,
          );
      if (!mounted) return;
      final labelMetode = _metodeTunai ? 'Tunai' : 'QRIS statis (cek manual)';
      final sisaSetelah = dipilih.sisaTagihan - jumlah < 0 ? 0 : dipilih.sisaTagihan - jumlah;
      setState(() {
        _dipilih = null;
        _jumlahController.clear();
        _metodeTunai = true;
        _sudahCekDanaMasuk = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pembayaran tercatat'),
          content: Text('Pembayaran ${_formatRupiah.format(jumlah)} utk ${dipilih.nomorStruk} tersimpan.'),
          actions: [
            TextButton(
              onPressed: () => _cetakBukti(
                nomorStrukAsal: dipilih.nomorStruk,
                jumlahDibayar: jumlah,
                labelMetode: labelMetode,
                sisaSetelahIni: sisaSetelah,
              ),
              child: const Text('Cetak bukti bayar'),
            ),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Selesai')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaksiAsync = ref.watch(transaksiKasbonPelangganProvider(widget.pelangganId));

    return Scaffold(
      appBar: AppBar(title: const Text('Catat pembayaran')),
      body: transaksiAsync.when(
        data: (daftar) {
          if (daftar.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              message: 'Semua transaksi pelanggan ini sudah lunas.',
            );
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text('Pilih transaksi', style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.sm),
                for (final t in daftar) ...[
                  AppCard(
                    onTap: () => _pilihTransaksi(t),
                    child: Row(
                      children: [
                        Icon(
                          t.id == _dipilih?.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: t.id == _dipilih?.id ? AppColors.primary : AppColors.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.nomorStruk, style: AppTypography.bodyEmphasis),
                              Text(
                                t.jatuhTempo != null
                                    ? 'Jatuh tempo ${_formatTanggal.format(DateTime.fromMillisecondsSinceEpoch(t.jatuhTempo!, isUtc: true))}'
                                    : '-',
                                style: AppTypography.secondary,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _formatRupiah.format(t.sisaTagihan),
                          style: AppTypography.bodyEmphasis.copyWith(color: AppColors.primaryDark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_dipilih != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Metode bayar', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          key: const Key('pelunasanForm.metodeTunai'),
                          label: const Text('Tunai'),
                          selected: _metodeTunai,
                          onSelected: (_) => setState(() {
                            _metodeTunai = true;
                            _sudahCekDanaMasuk = false;
                          }),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: ChoiceChip(
                          key: const Key('pelunasanForm.metodeQris'),
                          label: const Text('QRIS statis (cek manual)'),
                          selected: !_metodeTunai,
                          onSelected: (_) => setState(() => _metodeTunai = false),
                        ),
                      ),
                    ],
                  ),
                  if (!_metodeTunai) ...[
                    const SizedBox(height: AppSpacing.sm),
                    CheckboxListTile(
                      key: const Key('pelunasanForm.konfirmasiCekDana'),
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
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text('Jumlah dibayar', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const Key('pelunasanForm.jumlah'),
                    controller: _jumlahController,
                    decoration: const InputDecoration(prefixText: 'Rp '),
                    keyboardType: TextInputType.number,
                    inputFormatters: [RupiahInputFormatter()],
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    validator: (value) {
                      final nilai = parseRupiahInput(value ?? '');
                      if (nilai == null || nilai <= 0) return 'Jumlah wajib diisi, lebih dari 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: const Key('pelunasanForm.simpan'),
                      onPressed: _menyimpan || (!_metodeTunai && !_sudahCekDanaMasuk)
                          ? null
                          : _simpan,
                      child: Text(_menyimpan ? 'Menyimpan...' : 'Catat pembayaran'),
                    ),
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
}
