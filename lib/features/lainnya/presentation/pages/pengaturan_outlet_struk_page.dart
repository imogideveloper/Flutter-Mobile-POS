import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/struk/penyusun_struk.dart' as struk;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../../promo/domain/rincian_pajak.dart';
import '../../../transaksi/presentation/providers/harga_keranjang_provider.dart';

/// Pengaturan outlet & struk (tahap 4 bagian B) - header/footer/lebar
/// kertas/logo/struk ringkas/nomor antrean. BEDA dari pengaturan lain di
/// app ini (yang offline-first, tulis lokal lalu sync): baris ini
/// langsung baca+tulis ke BACKEND (lihat komentar di BackendApi.
/// ambilPengaturanOutlet) krn cuma relevan dibuka 1x, wajar perlu
/// koneksi, dan harus konsisten lintas-device di outlet yg sama. Setelah
/// simpan sukses, cache lokal (dibaca composer struk) diperbarui langsung
/// + sync ringan ditrigger di belakang.
class PengaturanOutletStrukPage extends ConsumerStatefulWidget {
  const PengaturanOutletStrukPage({super.key});

  @override
  ConsumerState<PengaturanOutletStrukPage> createState() => _PengaturanOutletStrukPageState();
}

class _PengaturanOutletStrukPageState extends ConsumerState<PengaturanOutletStrukPage> {
  final _headerController = TextEditingController();
  final _footerController = TextEditingController();
  int _lebarKertasMm = 58;
  bool _tampilLogo = false;
  bool _strukRingkas = false;
  bool _pakaiNomorAntrean = false;
  final _antreanAwalanController = TextEditingController(text: 'A');
  final _antreanMulaiController = TextEditingController(text: '1');
  final _estimasiController = TextEditingController(text: '0');
  final _batasMarginController = TextEditingController(text: '50');
  bool _izinkanStokMinus = true;
  int _pembulatan = 0;
  String? _logoUrl;

  int get _antreanMulai => (int.tryParse(_antreanMulaiController.text) ?? 1).clamp(1, 9999);
  int get _estimasiMenit => (int.tryParse(_estimasiController.text) ?? 0).clamp(0, 480);
  int get _batasMargin => (int.tryParse(_batasMarginController.text) ?? 50).clamp(0, 100);

  bool _memuat = true;
  bool _menyimpan = false;
  bool _mengunggahLogo = false;
  String? _errorMuat;
  SesiBackend? _sesi;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _headerController.dispose();
    _footerController.dispose();
    _antreanAwalanController.dispose();
    _antreanMulaiController.dispose();
    _estimasiController.dispose();
    _batasMarginController.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _errorMuat = null;
    });
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) {
        setState(() => _errorMuat = 'Device belum pairing ke backend - pairing dulu lewat halaman Masuk.');
        return;
      }
      _sesi = sesi;
      final data = await ref.read(backendApiProvider).ambilPengaturanOutlet(
            accessToken: sesi.accessToken,
            outletId: sesi.outletId,
          );
      _headerController.text = (data['header_struk'] as String?) ?? '';
      _footerController.text = (data['footer_struk'] as String?) ?? '';
      _lebarKertasMm = data['lebar_kertas_mm'] as int;
      _tampilLogo = data['tampil_logo'] as bool;
      _strukRingkas = data['struk_ringkas'] as bool;
      _pakaiNomorAntrean = data['pakai_nomor_antrean'] as bool;
      _antreanAwalanController.text = (data['antrean_awalan'] as String?) ?? 'A';
      _antreanMulaiController.text = '${(data['antrean_mulai'] as int?) ?? 1}';
      _estimasiController.text = '${(data['estimasi_menit'] as int?) ?? 0}';
      _batasMarginController.text = '${(data['batas_margin'] as int?) ?? 50}';
      _izinkanStokMinus = data['izinkan_stok_minus'] as bool;
      _pembulatan = (data['pembulatan'] as int?) ?? 0;
    } catch (e) {
      _errorMuat = 'Gagal memuat pengaturan: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _simpan() async {
    final sesi = _sesi;
    if (sesi == null) return;
    setState(() => _menyimpan = true);
    try {
      await ref.read(backendApiProvider).ubahPengaturanOutlet(
            accessToken: sesi.accessToken,
            outletId: sesi.outletId,
            body: {
              'header_struk': _headerController.text.trim().isEmpty ? null : _headerController.text.trim(),
              'footer_struk': _footerController.text.trim().isEmpty ? null : _footerController.text.trim(),
              'lebar_kertas_mm': _lebarKertasMm,
              'tampil_logo': _tampilLogo,
              'struk_ringkas': _strukRingkas,
              'pakai_nomor_antrean': _pakaiNomorAntrean,
              'antrean_awalan': _antreanAwalanController.text.trim(),
              'antrean_mulai': _antreanMulai,
              'estimasi_menit': _estimasiMenit,
              'batas_margin': _batasMargin,
              'pembulatan': _pembulatan,
              'izinkan_stok_minus': _izinkanStokMinus,
            },
          );

      // Perbarui cache lokal LANGSUNG (dibaca composer struk) - tidak perlu
      // menunggu sync penuh berikutnya, lihat dokumentasi kelas di atas.
      await ref.read(hargaDaoProvider).upsertPengaturanOutlet(
            PengaturanOutletCompanion.insert(
              outletId: sesi.outletId,
              headerStruk: Value(_headerController.text.trim().isEmpty ? null : _headerController.text.trim()),
              footerStruk: Value(_footerController.text.trim().isEmpty ? null : _footerController.text.trim()),
              lebarKertasMm: Value(_lebarKertasMm),
              tampilLogo: Value(_tampilLogo),
              strukRingkas: Value(_strukRingkas),
              pakaiNomorAntrean: Value(_pakaiNomorAntrean),
              antreanAwalan: Value(_antreanAwalanController.text.trim()),
              antreanMulai: Value(_antreanMulai),
              estimasiMenit: Value(_estimasiMenit),
              batasMargin: Value(_batasMargin),
              pembulatan: Value(_pembulatan),
              izinkanStokMinus: Value(_izinkanStokMinus),
              createdAt: DateTime.now().millisecondsSinceEpoch,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      ref.invalidate(pengaturanOutletProvider(sesi.outletId));

      if (mounted) {
        showAppToast(context, message: 'Pengaturan disimpan', variant: ToastVariant.success);
      }

      // Sync ringan di belakang - tidak di-await, kegagalannya tidak
      // menggagalkan "Simpan" (cache lokal di atas sudah cukup akurat).
      unawaited(ref.read(syncRepositoryProvider).jalankan());
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Gagal menyimpan: $e', variant: ToastVariant.danger);
      }
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  Future<void> _unggahLogo() async {
    final sesi = _sesi;
    if (sesi == null) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null) return;

    setState(() => _mengunggahLogo = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await ref.read(backendApiProvider).uploadLogoToko(
            accessToken: sesi.accessToken,
            bytes: bytes,
            namaFile: file.name,
          );
      setState(() => _logoUrl = url);
      if (mounted) {
        showAppToast(context, message: 'Logo berhasil diunggah', variant: ToastVariant.success);
      }
      unawaited(ref.read(syncRepositoryProvider).jalankan());
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Gagal unggah logo: $e', variant: ToastVariant.danger);
      }
    } finally {
      if (mounted) setState(() => _mengunggahLogo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outlet dan struk')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _errorMuat != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(_errorMuat!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    const OfflineNoticeBanner(),
                    Text('Header struk', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      key: const Key('pengaturanOutletForm.header'),
                      controller: _headerController,
                      maxLines: 2,
                      // Trigger rebuild pratinjau - lihat _pratinjauStruk().
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(hintText: 'Contoh: Toko Kopi Asik'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Footer struk', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      key: const Key('pengaturanOutletForm.footer'),
                      controller: _footerController,
                      maxLines: 2,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(hintText: 'Contoh: Terima kasih, sampai jumpa lagi!'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Lebar kertas', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            key: const Key('pengaturanOutletForm.lebar58'),
                            label: const Text('58 mm'),
                            selected: _lebarKertasMm == 58,
                            onSelected: (_) => setState(() => _lebarKertasMm = 58),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ChoiceChip(
                            key: const Key('pengaturanOutletForm.lebar80'),
                            label: const Text('80 mm'),
                            selected: _lebarKertasMm == 80,
                            onSelected: (_) => setState(() => _lebarKertasMm = 80),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Pembulatan total', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final opsi in const [0, 100, 500, 1000])
                          ChoiceChip(
                            key: Key('pengaturanOutletForm.pembulatan$opsi'),
                            label: Text(opsi == 0 ? 'Tidak dibulatkan' : 'Rp$opsi'),
                            selected: _pembulatan == opsi,
                            onSelected: (_) => setState(() => _pembulatan = opsi),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Stok', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      key: const Key('pengaturanOutletForm.izinkanStokMinus'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Izinkan jual walau stok habis'),
                      subtitle: const Text(
                        'Nyala: transaksi tetap jalan walau stok kurang/habis (stok bisa minus). '
                        'Mati: kasir tidak bisa menambah produk melebihi stok tersedia.',
                      ),
                      value: _izinkanStokMinus,
                      onChanged: (v) => setState(() => _izinkanStokMinus = v),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FiturTerkunci(
                      kode: 'logo_struk',
                      child: SwitchListTile(
                        key: const Key('pengaturanOutletForm.tampilLogo'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tampilkan logo di struk'),
                        value: _tampilLogo,
                        onChanged: (v) => setState(() => _tampilLogo = v),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FiturTerkunci(
                      kode: 'logo_struk',
                      child: SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          key: const Key('pengaturanOutletForm.unggahLogo'),
                          onPressed: _mengunggahLogo || !isOnlineSaat(ref) ? null : _unggahLogo,
                          icon: const Icon(Icons.image_outlined, size: 20),
                          label: Text(_mengunggahLogo
                              ? 'Mengunggah...'
                              : _logoUrl != null
                                  ? 'Ganti logo'
                                  : 'Unggah logo'),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FiturTerkunci(
                      kode: 'struk_ringkas',
                      child: SwitchListTile(
                        key: const Key('pengaturanOutletForm.strukRingkas'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Struk ringkas'),
                        subtitle: const Text('Hanya item, total, pembayaran, kembalian'),
                        value: _strukRingkas,
                        onChanged: (v) => setState(() => _strukRingkas = v),
                      ),
                    ),
                    FiturTerkunci(
                      kode: 'nomor_antrean',
                      child: SwitchListTile(
                        key: const Key('pengaturanOutletForm.nomorAntrean'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pakai nomor antrean'),
                        value: _pakaiNomorAntrean,
                        onChanged: (v) => setState(() => _pakaiNomorAntrean = v),
                      ),
                    ),
                    if (_pakaiNomorAntrean)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('pengaturanOutletForm.antreanAwalan'),
                              controller: _antreanAwalanController,
                              maxLength: 5,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
                              decoration: const InputDecoration(
                                labelText: 'Awalan nomor',
                                helperText: 'Contoh: A menjadi A-001',
                                counterText: '',
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: TextField(
                              key: const Key('pengaturanOutletForm.antreanMulai'),
                              controller: _antreanMulaiController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                labelText: 'Mulai dari angka',
                                helperText: 'Dipakai tiap hari baru',
                              ),
                            ),
                          ),
                        ],
                      ),
                    TextField(
                      key: const Key('pengaturanOutletForm.batasMargin'),
                      controller: _batasMarginController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Batas margin produk (%)',
                        helperText: 'Produk dengan margin di bawah angka ini ditandai. Bawaan 50 untuk makanan dan minuman.',
                      ),
                    ),
                    FiturTerkunci(
                      kode: 'status_pesanan',
                      child: TextField(
                        key: const Key('pengaturanOutletForm.estimasiMenit'),
                        controller: _estimasiController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Estimasi selesai pesanan (menit)',
                          helperText: '0 = tidak ditampilkan di Status pesanan',
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Pratinjau struk', style: AppTypography.cardTitle.copyWith(fontSize: 15)),
                    const SizedBox(height: AppSpacing.sm),
                    _pratinjauStruk(),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        key: const Key('pengaturanOutletForm.simpan'),
                        onPressed: _menyimpan || !isOnlineSaat(ref) ? null : _simpan,
                        child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan'),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// C.1 (tahap 5) - pratinjau LANGSUNG dari state form saat ini (BUKAN
  /// data tersimpan), pakai mesin penyusun struk SUNGGUHAN (bukan tiruan
  /// visual) - data contoh statis, cuma utk menunjukkan efek header/
  /// footer/lebar kertas/struk ringkas/pembulatan.
  Widget _pratinjauStruk() {
    final pengaturan = struk.PengaturanStrukData(
      headerStruk: _headerController.text.trim().isEmpty ? null : _headerController.text.trim(),
      footerStruk: _footerController.text.trim().isEmpty ? null : _footerController.text.trim(),
      lebarKertasMm: _lebarKertasMm,
      tampilLogo: _tampilLogo,
      strukRingkas: _strukRingkas,
      pakaiNomorAntrean: _pakaiNomorAntrean,
    );
    final data = struk.StrukData(
      namaOutlet: 'Toko Contoh',
      nomorStruk: 'OUT1-0001',
      tanggalEpochMs: DateTime.now().toUtc().millisecondsSinceEpoch,
      namaKasir: 'Kasir',
      nomorAntrean: _pakaiNomorAntrean ? 'A1' : null,
      items: const [
        struk.ItemStruk(namaProduk: 'Kopi Hitam', qty: 2, hargaSatuan: 15000, subtotal: 30000),
        struk.ItemStruk(namaProduk: 'Roti Bakar', qty: 1, hargaSatuan: 12000, subtotal: 12000),
      ],
      subtotal: 42000,
      rincianPajak: const [RincianPajak(nama: 'PPN', persen: 11, jumlah: 4620, termasukHarga: false)],
      pembulatan: _pembulatan == 0 ? 0 : -20,
      total: _pembulatan == 0 ? 46620 : 46600,
      pembayaran: const [struk.PembayaranStruk(labelMetode: 'Tunai', jumlah: 50000)],
      kembalian: _pembulatan == 0 ? 3380 : 3400,
    );
    final baris = struk.susunStrukTransaksi(data: data, pengaturan: pengaturan);
    final teks = struk.renderTeksStruk(baris, pengaturan.lebarKarakter);

    return AppCard(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
        child: Text(
          teks.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4),
        ),
      ),
    );
  }
}
