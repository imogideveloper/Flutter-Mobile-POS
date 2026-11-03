import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/metode_bayar_label.dart';
import '../../domain/ringkasan_transaksi.dart';
import '../../data/local/tables/transaksi_table.dart' show TransaksiStatus, transaksiStatusPostgresValue;
import '../providers/transaksi_providers.dart';
import 'transaksi_detail_page.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _formatWaktu = DateFormat('HH.mm');
final _formatTanggalSingkat = DateFormat('d MMM', 'id_ID');

enum _RentangPreset { hariIni, kemarin, tujuhHari, tigaPuluhHari, custom }

const _labelPreset = {
  _RentangPreset.hariIni: 'Hari ini',
  _RentangPreset.kemarin: 'Kemarin',
  _RentangPreset.tujuhHari: '7 hari',
  _RentangPreset.tigaPuluhHari: '30 hari',
  _RentangPreset.custom: 'Atur rentang',
};

TransaksiStatus _statusDariString(String s) =>
    transaksiStatusPostgresValue.entries.firstWhere((e) => e.value == s, orElse: () => transaksiStatusPostgresValue.entries.first).key;

/// Sesuai mockup "Riwayat": header + ringkasan (penjualan/transaksi), search,
/// list transaksi. F3.B - filter rentang tanggal (preset + custom) dibaca
/// dari drift lokal; kalau rentang melewati data tersimpan di HP, coba
/// ambil tambahan dari server (GET /transaksi) - offline = kasih tahu
/// butuh internet, bukan diam-diam menampilkan data yang kepotong.
class RiwayatListPage extends ConsumerStatefulWidget {
  const RiwayatListPage({super.key});

  @override
  ConsumerState<RiwayatListPage> createState() => _RiwayatListPageState();
}

class _RiwayatListPageState extends ConsumerState<RiwayatListPage> {
  final _cariController = TextEditingController();
  String _kata = '';
  _RentangPreset _preset = _RentangPreset.hariIni;
  DateTimeRange? _rentangCustom;

  List<RingkasanTransaksi>? _remoteItems;
  bool _memuatRemote = false;
  String? _remoteError;
  (DateTime, DateTime)? _rentangTerakhirDicoba;

  @override
  void dispose() {
    _cariController.dispose();
    super.dispose();
  }

  (DateTime dari, DateTime sampai) _bounds() {
    final now = DateTime.now();
    final awalHariIni = DateTime(now.year, now.month, now.day);
    final akhirHariIni = awalHariIni.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    switch (_preset) {
      case _RentangPreset.hariIni:
        return (awalHariIni, akhirHariIni);
      case _RentangPreset.kemarin:
        final kemarin = awalHariIni.subtract(const Duration(days: 1));
        return (kemarin, awalHariIni.subtract(const Duration(milliseconds: 1)));
      case _RentangPreset.tujuhHari:
        return (awalHariIni.subtract(const Duration(days: 6)), akhirHariIni);
      case _RentangPreset.tigaPuluhHari:
        return (awalHariIni.subtract(const Duration(days: 29)), akhirHariIni);
      case _RentangPreset.custom:
        final r = _rentangCustom;
        if (r == null) return (awalHariIni, akhirHariIni);
        return (DateTime(r.start.year, r.start.month, r.start.day),
            DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59, 999));
    }
  }

  Future<void> _pilihRentangCustom() async {
    final now = DateTime.now();
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _rentangCustom ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (hasil == null) return;
    setState(() {
      _preset = _RentangPreset.custom;
      _rentangCustom = hasil;
      _remoteItems = null;
      _remoteError = null;
      _rentangTerakhirDicoba = null;
    });
  }

  void _pilihPreset(_RentangPreset preset) {
    if (preset == _RentangPreset.custom) {
      _pilihRentangCustom();
      return;
    }
    setState(() {
      _preset = preset;
      _remoteItems = null;
      _remoteError = null;
      _rentangTerakhirDicoba = null;
    });
  }

  /// Local drift cuma simpan apa yang pernah terjadi/tersync di HP ini -
  /// kalau baris LOKAL paling lama masih lebih baru drpd awal rentang yang
  /// diminta (atau lokal kosong sama sekali), ada kemungkinan data lebih
  /// lama belum pernah masuk ke HP ini, jadi dicoba ambil dari server.
  ///
  /// Bug nyata (laporan pengguna: transaksi yang baru saja dibuat tidak
  /// muncul sama sekali di Riwayat) - [palingAwal] dulu dibandingkan
  /// sbg DateTime PENUH (jam:menit:detik), bukan cuma tanggalnya. Utk
  /// preset "Hari ini", `dari` = tepat jam 00:00 - transaksi APAPUN yang
  /// dibuat siang/sore (hampir selalu) punya jam > 00:00, jadi kondisi ini
  /// SELALU true walau transaksi itu sendiri sudah mencakup seluruh hari
  /// ini, memicu _cobaAmbilDariServer() yang tidak perlu. Dibulatkan ke
  /// awal HARI dulu supaya "hari ini" tidak keliru dianggap "butuh data
  /// lebih lama dari server".
  bool _perluDataServer(List<RingkasanTransaksi> semuaLokal, DateTime dari) {
    if (semuaLokal.isEmpty) return true;
    final palingAwal = semuaLokal
        .map((r) => DateTime.fromMillisecondsSinceEpoch(r.tanggal, isUtc: true).toLocal())
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final palingAwalHari = DateTime(palingAwal.year, palingAwal.month, palingAwal.day);
    return dari.isBefore(palingAwalHari);
  }

  /// Bug nyata (lanjutan dari atas): SEBELUM INI, hasil fetch server
  /// (`_remoteItems`) MENGGANTIKAN TOTAL data lokal (`_remoteItems ??
  /// lokal...`) - kalau transaksi yang baru dibuat di HP ini BELUM sempat
  /// ter-push ke server (wajar, sync tidak instan), server balas list
  /// kosong/tidak lengkap utk rentang itu, dan transaksi yang SUNGGUHAN
  /// ADA di HP ini malah hilang dari layar. Sekarang digabung (dedupe by
  /// id, lokal menang kalau bentrok krn lebih baru/akurat utk device ini),
  /// bukan ditimpa - data lokal TIDAK PERNAH hilang hanya krn server belum
  /// sempat tahu soal itu.
  List<RingkasanTransaksi> _gabungkanLokalDanRemote(
    List<RingkasanTransaksi> lokal,
    List<RingkasanTransaksi> remote,
  ) {
    final idLokal = lokal.map((r) => r.id).toSet();
    final gabungan = [...lokal, ...remote.where((r) => !idLokal.contains(r.id))];
    gabungan.sort((a, b) => b.tanggal.compareTo(a.tanggal));
    return gabungan;
  }

  Future<void> _cobaAmbilDariServer(
    List<RingkasanTransaksi> semuaLokal,
    DateTime dari,
    DateTime sampai,
  ) async {
    if (!_perluDataServer(semuaLokal, dari)) {
      if (_remoteItems != null || _remoteError != null) {
        setState(() {
          _remoteItems = null;
          _remoteError = null;
        });
      }
      return;
    }
    if (_rentangTerakhirDicoba == (dari, sampai)) return; // sudah/sedang dicoba utk rentang persis ini
    _rentangTerakhirDicoba = (dari, sampai);

    setState(() => _memuatRemote = true);
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) {
        if (mounted) setState(() => _remoteError = 'Transaksi lebih lama butuh koneksi internet');
        return;
      }
      final resp = await ref.read(backendApiProvider).ambilTransaksi(
            accessToken: sesi.accessToken,
            outletId: sesi.outletId,
            dariTanggal: dari.toUtc().toIso8601String(),
            sampaiTanggal: sampai.toUtc().toIso8601String(),
          );
      final items = (resp['items'] as List).cast<Map<String, dynamic>>();
      final hasil = [
        for (final item in items)
          RingkasanTransaksi(
            id: item['id'] as String,
            nomorStruk: item['nomor_struk'] as String,
            tanggal: DateTime.parse(item['tanggal'] as String).toUtc().millisecondsSinceEpoch,
            status: _statusDariString(item['status'] as String),
            total: double.parse(item['total'].toString()).round(),
            jumlahItem: 0, // TransaksiOut server tidak kirim rincian item - lihat catatan di atas.
            pelangganId: item['pelanggan_id'] as String?,
          ),
      ];
      if (mounted) {
        setState(() {
          _remoteItems = hasil;
          _remoteError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _remoteError = 'Gagal mengambil data lama - periksa koneksi internet ($e)');
      }
    } finally {
      if (mounted) setState(() => _memuatRemote = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final riwayatAsync = ref.watch(riwayatTransaksiProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: PopupMenuButton<_RentangPreset>(
              key: const Key('riwayatForm.filterTanggal'),
              onSelected: _pilihPreset,
              itemBuilder: (context) => [
                for (final preset in _RentangPreset.values)
                  PopupMenuItem(value: preset, child: Text(_labelPreset[preset]!)),
              ],
              child: Chip(
                avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  _preset == _RentangPreset.custom && _rentangCustom != null
                      ? '${_formatTanggalSingkat.format(_rentangCustom!.start)} - ${_formatTanggalSingkat.format(_rentangCustom!.end)}'
                      : _labelPreset[_preset]!,
                ),
              ),
            ),
          ),
        ],
      ),
      body: riwayatAsync.when(
        data: (semuaLokal) {
          final (dari, sampai) = _bounds();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _cobaAmbilDariServer(semuaLokal, dari, sampai);
          });

          final lokalTerfilter = semuaLokal.where((r) {
            final t = DateTime.fromMillisecondsSinceEpoch(r.tanggal, isUtc: true).toLocal();
            return !t.isBefore(dari) && !t.isAfter(sampai);
          }).toList();
          final remote = _remoteItems;
          final sumber =
              remote == null ? lokalTerfilter : _gabungkanLokalDanRemote(lokalTerfilter, remote);

          final kata = _kata.trim().toLowerCase();
          final hasil = kata.isEmpty
              ? sumber
              : sumber
                  .where((r) =>
                      r.nomorStruk.toLowerCase().contains(kata) ||
                      _formatRupiah.format(r.total).toLowerCase().contains(kata))
                  .toList();

          final penjualan = sumber
              .where((r) => r.status != TransaksiStatus.dibatalkan)
              .fold<int>(0, (a, b) => a + b.total);

          return Column(
            children: [
              if (_memuatRemote)
                const LinearProgressIndicator(key: Key('riwayatForm.memuatServer'))
              else if (_remoteError != null)
                Container(
                  width: double.infinity,
                  color: AppColors.warningBg,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                  child: Text(
                    _remoteError!,
                    style: AppTypography.secondary.copyWith(color: AppColors.warningTextStrong),
                  ),
                )
              else if (_remoteItems != null)
                Container(
                  width: double.infinity,
                  color: AppColors.primaryTint,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                  child: Text(
                    'Menampilkan data historis dari server utk rentang ini',
                    style: AppTypography.secondary.copyWith(color: AppColors.primaryDark),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0),
                child: TextField(
                  controller: _cariController,
                  onChanged: (value) => setState(() => _kata = value),
                  decoration: const InputDecoration(
                    hintText: 'No. struk atau nominal',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Row(
                  children: [
                    _ringkasan('Penjualan', _formatRupiah.format(penjualan)),
                    _ringkasan('Transaksi', '${sumber.length}'),
                  ],
                ),
              ),
              Expanded(
                child: hasil.isEmpty
                    ? const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        message: 'Belum ada transaksi.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
                        itemCount: hasil.length,
                        separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) => _RiwayatRow(ringkasan: hasil[index]),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('Gagal memuat riwayat: $error')),
      ),
    );
  }

  Widget _ringkasan(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.secondary.copyWith(fontSize: 11)),
          Text(value, style: AppTypography.cardTitle.copyWith(fontSize: 15)),
        ],
      ),
    );
  }
}

class _RiwayatRow extends StatelessWidget {
  const _RiwayatRow({required this.ringkasan});

  final RingkasanTransaksi ringkasan;

  @override
  Widget build(BuildContext context) {
    final isVoid = ringkasan.status == TransaksiStatus.dibatalkan;
    final (label, bg, fg) = switch (ringkasan.status) {
      TransaksiStatus.dibatalkan => ('Void', AppColors.dangerBg, AppColors.dangerText),
      TransaksiStatus.refundSebagian => ('Refund sebagian', AppColors.indigoBg, AppColors.indigoText),
      TransaksiStatus.refund => ('Refund', AppColors.indigoBg, AppColors.indigoText),
      _ => ('Selesai', AppColors.primaryTint, AppColors.primaryDark),
    };
    final waktu = DateTime.fromMillisecondsSinceEpoch(ringkasan.tanggal, isUtc: true).toLocal();

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => TransaksiDetailPage(transaksiId: ringkasan.id)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('#${ringkasan.nomorStruk}', style: AppTypography.bodyEmphasis),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '${_formatWaktu.format(waktu)} · ${labelMetodeBayar(ringkasan.metodeBayarId, jumlahPembayaran: ringkasan.jumlahPembayaran)}',
                      style: AppTypography.secondary,
                    ),
                  ],
                ),
                Text('${ringkasan.jumlahItem} item', style: AppTypography.secondary),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatRupiah.format(ringkasan.total),
                style: AppTypography.bodyEmphasis.copyWith(
                  decoration: isVoid ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
