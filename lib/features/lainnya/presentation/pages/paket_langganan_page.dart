import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _formatTanggal = DateFormat('d MMM yyyy', 'id_ID');

class _Paket {
  const _Paket({
    required this.id,
    required this.nama,
    required this.urutan,
    required this.hargaBulanan,
    required this.maksOutlet,
    required this.maksPengguna,
    required this.maksProduk,
    required this.kodeFitur,
  });

  final String id;
  final String nama;
  final int urutan;
  final int hargaBulanan;
  final int? maksOutlet;
  final int? maksPengguna;
  final int? maksProduk;
  final List<String> kodeFitur;

  factory _Paket.fromJson(Map<String, dynamic> j) => _Paket(
        id: j['id'] as String,
        nama: j['nama'] as String,
        urutan: j['urutan'] as int,
        hargaBulanan: double.parse(j['harga_bulanan'].toString()).round(),
        maksOutlet: j['maks_outlet'] as int?,
        maksPengguna: j['maks_pengguna'] as int?,
        maksProduk: j['maks_produk'] as int?,
        kodeFitur: (j['kode_fitur'] as List).cast<String>(),
      );
}

/// F3.F - "Paket langganan": paket aktif+masa berlaku+pemakaian kuota,
/// tabel perbandingan fitur Gratis/Pro/Bisnis (dari backend sungguhan,
/// bukan hardcode).
///
/// Keputusan awal F3.F.2 ("TANPA pembayaran di dalam app", cuma catat
/// minat lalu admin follow-up manual) DIBALIK atas permintaan eksplisit
/// pemilik produk - sekarang "Bayar & upgrade sekarang" buka invoice
/// Xendit sungguhan (browser eksternal), paket aktif OTOMATIS begitu
/// lunas (lihat backend/app/services/xendit_service.py), tidak ada admin
/// di tengah lagi. SELALU online, sama pola dgn pengaturan_outlet_struk_page.
class PaketLanggananPage extends ConsumerStatefulWidget {
  const PaketLanggananPage({super.key});

  @override
  ConsumerState<PaketLanggananPage> createState() => _PaketLanggananPageState();
}

class _PaketLanggananPageState extends ConsumerState<PaketLanggananPage> {
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _langganan;
  List<_Paket> _daftarPaket = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) {
        setState(() {
          _error = 'Device belum pairing ke backend';
          _memuat = false;
        });
        return;
      }
      final api = ref.read(backendApiProvider);
      final langganan = await api.ambilLanggananSaya(accessToken: sesi.accessToken);
      final paketJson = await api.ambilDaftarPaket(accessToken: sesi.accessToken);
      if (!mounted) return;
      setState(() {
        _langganan = langganan;
        _daftarPaket = paketJson.map(_Paket.fromJson).toList()..sort((a, b) => a.urutan.compareTo(b.urutan));
        _memuat = false;
      });
    } on BackendException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _memuat = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat: $e';
          _memuat = false;
        });
      }
    }
  }

  bool _memprosesBayar = false;

  /// Modal pilih metode (QRIS/VA) LANGSUNG di app - dibalik dari jalur
  /// lama yang buka invoice Xendit di browser eksternal (atas permintaan
  /// eksplisit pemilik produk: "jangan keluar dari HP"). Lewat Xendit
  /// Payment Requests API (/v3/payment_requests, bukan Invoice API lama),
  /// lihat backend/app/services/xendit_service.py::buat_qris/buat_va.
  Future<void> _bayarUpgrade(_Paket tujuan) async {
    final pilihan = await _pilihMetodeBayar();
    if (pilihan == null || !mounted) return;

    setState(() => _memprosesBayar = true);
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) return;
      final api = ref.read(backendApiProvider);
      final Map<String, dynamic> hasil;
      if (pilihan.metode == _MetodePembayaran.qris) {
        hasil = await api.postJson(
          accessToken: sesi.accessToken,
          path: '/langganan/checkout-upgrade/qris',
          body: {'paket_tujuan_id': tujuan.id, 'periode': 'bulanan'},
        ) as Map<String, dynamic>;
      } else {
        hasil = await api.postJson(
          accessToken: sesi.accessToken,
          path: '/langganan/checkout-upgrade/va',
          body: {
            'paket_tujuan_id': tujuan.id,
            'periode': 'bulanan',
            'bank_code': pilihan.bankCode,
          },
        ) as Map<String, dynamic>;
      }
      if (mounted) await _tampilkanModalPembayaran(tujuan: tujuan, pilihan: pilihan, hasil: hasil);
    } on BackendException catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Gagal: ${e.message}', variant: ToastVariant.danger);
      }
    } finally {
      if (mounted) setState(() => _memprosesBayar = false);
    }
  }

  /// Bottom sheet pilih QRIS atau bank VA - TIDAK pernah keluar dari app
  /// (beda dari jalur lama yang redirect ke browser Xendit).
  Future<_PilihanBayar?> _pilihMetodeBayar() {
    return showModalBottomSheet<_PilihanBayar>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pilih metode pembayaran', style: AppTypography.cardTitle),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                key: const Key('paketLanggananForm.metode.qris'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.qr_code_2_outlined, color: AppColors.primary),
                title: const Text('QRIS'),
                subtitle: const Text('Scan dari e-wallet/m-banking apa pun'),
                onTap: () => Navigator.of(sheetContext).pop(const _PilihanBayar.qris()),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('Transfer bank (Virtual Account)', style: AppTypography.secondary),
              ),
              for (final entry in _bankVaDidukung.entries)
                ListTile(
                  key: Key('paketLanggananForm.metode.va.${entry.key}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_outlined, color: AppColors.primary),
                  title: Text(entry.value),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_PilihanBayar.va(bankCode: entry.key, namaBank: entry.value)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Modal hasil checkout - render QR/nomor VA LANGSUNG di app (QR via
  /// qr_flutter, pola sama dgn bayar_qris_page.dart), bukan link ke
  /// browser. Tidak bisa didismiss tanpa sadar (barrier) krn ada
  /// permintaan pembayaran yang sudah dibuat di Xendit.
  Future<void> _tampilkanModalPembayaran({
    required _Paket tujuan,
    required _PilihanBayar pilihan,
    required Map<String, dynamic> hasil,
  }) {
    final permintaanId = hasil['id'] as String;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => _ModalPembayaran(
        namaPaket: tujuan.nama,
        pilihan: pilihan,
        hasil: hasil,
        onCekStatus: () => _cekStatusCheckout(permintaanId),
        onSimulasikan: () => _simulasikanBayar(permintaanId),
      ),
    );
  }

  Future<_HasilCekStatus> _cekStatusCheckout(String permintaanId) async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return _HasilCekStatus('baru');
    try {
      final hasil = await ref.read(backendApiProvider).statusCheckoutUpgrade(
            accessToken: sesi.accessToken,
            permintaanId: permintaanId,
          );
      final status = hasil['status'] as String;
      if (status == 'selesai' && mounted) await _setelahLunas();
      return _HasilCekStatus(status);
    } on BackendException catch (e) {
      return _HasilCekStatus('error', pesanError: e.message);
    }
  }

  /// KHUSUS SANDBOX - QR/VA Xendit test mode tidak bisa benar2 discan/
  /// ditransfer (lihat catatan di xendit_service.py::buat_qris). Tombol
  /// ini memicu Xendit men-simulasikan pembayaran lunas lewat
  /// POST .../simulasi (aman tetap ada di produksi - Xendit sendiri yang
  /// menolak panggilan ini terhadap API key live).
  Future<_HasilCekStatus> _simulasikanBayar(String permintaanId) async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) return _HasilCekStatus('baru');
    try {
      final hasil = await ref.read(backendApiProvider).postJson(
            accessToken: sesi.accessToken,
            path: '/langganan/checkout-upgrade/$permintaanId/simulasi',
          ) as Map<String, dynamic>;
      final status = hasil['status'] as String;
      if (status == 'selesai' && mounted) await _setelahLunas();
      return _HasilCekStatus(status);
    } on BackendException catch (e) {
      return _HasilCekStatus('error', pesanError: e.message);
    }
  }

  /// Dipanggil begitu paket toko benar2 berubah (bukan cuma status tiket
  /// checkout-nya) - DUA hal wajib disegarkan, bukan cuma kartu "Langganan
  /// saya" di halaman ini:
  /// 1. `featureGateProvider` - cache LOKAL gating fitur (dipakai widget
  ///    `FiturTerkunci` di layar manapun, mis. Edit Produk > Bundling/Harga
  ///    grosir) cuma diperbarui lewat `/sync/pull`, BUKAN reaktif otomatis
  ///    (lihat catatan di feature_gate_provider.dart) - tanpa sync+invalidate
  ///    di sini, fitur paket baru tetap tampak terkunci sampai sync lain
  ///    kebetulan terjadi (laporan nyata: upgrade ke Bisnis tapi
  ///    bundling/harga grosir masih bergembok).
  /// 2. `SyncRepository.jalankan()` SEKALIAN membersihkan baris "hantu" di
  ///    tabel lain (lihat MetodeBayarDao.hapusSelainIdServer) - bukan cuma
  ///    utk gating, pola sama dgn tombol Sync manual di lainnya_page.dart.
  Future<void> _setelahLunas() async {
    await _muat();
    if (!mounted) return;
    try {
      await ref.read(syncRepositoryProvider).jalankan();
    } catch (_) {
      // Best-effort - paket toko SUDAH benar (dari _muat() di atas), gagal
      // sync di sini cuma menunda fitur baru tampak terbuka, bukan
      // menggagalkan aktivasi pembayarannya sendiri.
    }
    ref.invalidate(featureGateProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paket langganan')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muat,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: [
                      _kartuLanggananSaya(),
                      const SizedBox(height: AppSpacing.lg),
                      Text('Perbandingan paket', style: AppTypography.cardTitle),
                      const SizedBox(height: AppSpacing.sm),
                      for (final paket in _daftarPaket) _kartuPaket(paket),
                    ],
                  ),
                ),
    );
  }

  Widget _kartuLanggananSaya() {
    final l = _langganan!;
    final berakhir = l['berakhir'] as String?;
    final pemakaian = l['pemakaian'] as Map<String, dynamic>;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l['paket_nama'] as String, style: AppTypography.headerTitle),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  (l['status'] as String).toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            berakhir == null
                ? 'Tidak ada tanggal berakhir'
                : 'Berlaku sampai ${_formatTanggal.format(DateTime.parse(berakhir).toLocal())}',
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _pemakaianItem('Outlet', pemakaian['outlet'] as int),
              _pemakaianItem('Karyawan', pemakaian['pengguna'] as int),
              _pemakaianItem('Produk', pemakaian['produk'] as int),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pemakaianItem(String label, int jumlah) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$jumlah', style: AppTypography.headerTitle),
          Text(label, style: AppTypography.secondary),
        ],
      ),
    );
  }

  Widget _kartuPaket(_Paket paket) {
    final aktif = _langganan != null && _langganan!['paket_id'] == paket.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(paket.nama, style: AppTypography.cardTitle),
                Text(
                  paket.hargaBulanan == 0 ? 'Gratis' : '${_formatRupiah.format(paket.hargaBulanan)}/bln',
                  style: AppTypography.bodyEmphasis,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Outlet: ${paket.maksOutlet?.toString() ?? 'Tanpa batas'} · '
              'Karyawan: ${paket.maksPengguna?.toString() ?? 'Tanpa batas'} · '
              'Produk: ${paket.maksProduk?.toString() ?? 'Tanpa batas'}',
              style: AppTypography.secondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final kode in paket.kodeFitur)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.borderDefault),
                    ),
                    child: Text(kode, style: AppTypography.secondary.copyWith(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (aktif)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Paket aktif saat ini', style: AppTypography.secondary),
              )
            else
              OutlinedButton(
                key: Key('paketLanggananForm.upgrade.${paket.id}'),
                onPressed: _memprosesBayar ? null : () => _bayarUpgrade(paket),
                child: Text(_memprosesBayar ? 'Memproses...' : 'Bayar & upgrade sekarang'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HasilCekStatus {
  const _HasilCekStatus(this.status, {this.pesanError});

  final String status;
  final String? pesanError;
}

enum _MetodePembayaran { qris, va }

/// Bank VA yang didukung - SAMA PERSIS dgn `BANK_VA_DIDUKUNG` di
/// backend/app/services/xendit_service.py (key dikirim sbg `bank_code`).
const _bankVaDidukung = <String, String>{
  'bca': 'BCA',
  'bni': 'BNI',
  'bri': 'BRI',
  'mandiri': 'Mandiri',
  'permata': 'Permata',
};

class _PilihanBayar {
  const _PilihanBayar.qris()
      : metode = _MetodePembayaran.qris,
        bankCode = null,
        namaBank = null;

  const _PilihanBayar.va({required this.bankCode, required this.namaBank}) : metode = _MetodePembayaran.va;

  final _MetodePembayaran metode;
  final String? bankCode;
  final String? namaBank;
}

/// Modal bottom sheet hasil checkout - QR/nomor VA ditampilkan LANGSUNG
/// di app (lihat `_tampilkanModalPembayaran`), widget TERPISAH (bukan
/// builder inline) supaya punya State sendiri utk "Sudah bayar, cek
/// status"/"Simulasikan pembayaran" TANPA menutup modal kalau pembayaran
/// belum terdeteksi.
class _ModalPembayaran extends StatefulWidget {
  const _ModalPembayaran({
    required this.namaPaket,
    required this.pilihan,
    required this.hasil,
    required this.onCekStatus,
    required this.onSimulasikan,
  });

  final String namaPaket;
  final _PilihanBayar pilihan;
  final Map<String, dynamic> hasil;
  final Future<_HasilCekStatus> Function() onCekStatus;
  final Future<_HasilCekStatus> Function() onSimulasikan;

  @override
  State<_ModalPembayaran> createState() => _ModalPembayaranState();
}

class _ModalPembayaranState extends State<_ModalPembayaran> {
  bool _memproses = false;
  String? _pesan;

  Future<void> _tangani(Future<_HasilCekStatus> Function() aksi) async {
    setState(() {
      _memproses = true;
      _pesan = null;
    });
    final hasil = await aksi();
    if (!mounted) return;
    switch (hasil.status) {
      case 'selesai':
        Navigator.of(context).pop();
        showAppToast(
          context,
          title: 'Pembayaran berhasil',
          message: 'Paket ${widget.namaPaket} sudah aktif',
          variant: ToastVariant.success,
        );
        return;
      case 'batal':
        Navigator.of(context).pop();
        showAppToast(
          context,
          message: 'Pembayaran kedaluwarsa/dibatalkan - silakan coba checkout lagi',
          variant: ToastVariant.warning,
        );
        return;
      case 'error':
        setState(() => _pesan = 'Gagal: ${hasil.pesanError}');
      default:
        setState(() => _pesan = 'Pembayaran belum terdeteksi - kalau sudah bayar, tunggu sebentar lalu coba lagi.');
    }
    setState(() => _memproses = false);
  }

  @override
  Widget build(BuildContext context) {
    final jumlah = double.tryParse(widget.hasil['jumlah_bayar'].toString())?.round() ?? 0;
    final isQris = widget.pilihan.metode == _MetodePembayaran.qris;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          key: const Key('paketLanggananForm.modalPembayaran.scrollView'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isQris ? 'Bayar dengan QRIS' : 'Transfer Virtual Account ${widget.pilihan.namaBank}',
                style: AppTypography.cardTitle,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Upgrade ke paket ${widget.namaPaket} · ${_formatRupiah.format(jumlah)}',
                style: AppTypography.secondary,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (isQris)
                Center(
                  child: AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: QrImageView(
                        key: const Key('paketLanggananForm.qrImage'),
                        data: widget.hasil['qr_string'] as String,
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                )
              else
                AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Nomor Virtual Account', style: AppTypography.secondary),
                              Text(
                                widget.hasil['nomor_va'] as String,
                                key: const Key('paketLanggananForm.nomorVa'),
                                style: AppTypography.headerTitle.copyWith(letterSpacing: 1),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const Key('paketLanggananForm.salinVa'),
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: widget.hasil['nomor_va'] as String),
                            );
                            if (context.mounted) {
                              showAppToast(context, message: 'Nomor VA disalin', variant: ToastVariant.info);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                isQris
                    ? 'Buka aplikasi bank/e-wallet apa pun, scan QR di atas, lalu bayar sesuai nominal.'
                    : 'Transfer tepat sesuai nominal ke nomor VA ${widget.pilihan.namaBank} di atas lewat '
                        'm-banking/ATM.',
                style: AppTypography.secondary,
              ),
              if (_pesan != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_pesan!, style: const TextStyle(color: AppColors.warningTextStrong)),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('paketLanggananForm.cekStatus'),
                onPressed: _memproses ? null : () => _tangani(widget.onCekStatus),
                child: Text(_memproses ? 'Memeriksa...' : 'Sudah bayar, cek status'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                key: const Key('paketLanggananForm.simulasikan'),
                onPressed: _memproses ? null : () => _tangani(widget.onSimulasikan),
                child: Text(_memproses ? 'Memproses...' : 'Simulasikan pembayaran (mode testing)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
