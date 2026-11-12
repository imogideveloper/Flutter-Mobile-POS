import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../pengeluaran/domain/pengeluaran.dart' show RentangPengeluaran, RentangPengeluaranX, tanggalApi;
import '../../domain/absensi_data.dart';

/// Absensi karyawan (IMOGI no. 62): absen masuk/keluar diri sendiri dan rekap jam kerja.
/// Langsung ke server (butuh internet). Pemilik/manajer melihat rekap semua karyawan; peran lain
/// hanya melihat absensinya sendiri (dibatasi server).
class AbsensiPage extends ConsumerStatefulWidget {
  const AbsensiPage({super.key});

  @override
  ConsumerState<AbsensiPage> createState() => _AbsensiPageState();
}

class _AbsensiPageState extends ConsumerState<AbsensiPage> {
  CatatanAbsensi? _aktif;
  DaftarAbsensi? _daftar;
  RentangPengeluaran _rentang = RentangPengeluaran.hariIni;
  String? _error;
  bool _memuat = true;
  bool _sibuk = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<SesiBackend> _sesi() async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
    return sesi;
  }

  String _pesan(BackendException e) {
    if (e.tidakAdaKoneksi) return 'Butuh internet untuk absensi.';
    if (e.statusCode == 403) return 'Fitur absensi belum tersedia di paket Anda.';
    return e.message;
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final sesi = await _sesi();
      final api = ref.read(backendApiProvider);
      final saya = await api.absensiSaya(accessToken: sesi.accessToken);
      final (dari, sampai) = _rentang.tanggal(DateTime.now());
      final daftar = await api.daftarAbsensi(
        accessToken: sesi.accessToken,
        dari: tanggalApi(dari),
        sampai: tanggalApi(sampai),
        tzMenit: offsetZonaMenit(DateTime.now()),
      );
      _aktif = saya['aktif'] == null ? null : CatatanAbsensi.dariJson(saya['aktif'] as Map<String, dynamic>);
      _daftar = DaftarAbsensi.dariJson(daftar);
    } on BackendException catch (e) {
      _error = _pesan(e);
    } catch (e) {
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _ubahStatus() async {
    setState(() => _sibuk = true);
    try {
      final sesi = await _sesi();
      final api = ref.read(backendApiProvider);
      if (_aktif == null) {
        await api.absenMasuk(accessToken: sesi.accessToken, outletId: sesi.outletId);
        if (mounted) showAppToast(context, message: 'Absen masuk tercatat', variant: ToastVariant.success);
      } else {
        await api.absenKeluar(accessToken: sesi.accessToken);
        if (mounted) showAppToast(context, message: 'Absen keluar tercatat', variant: ToastVariant.success);
      }
      await _muat();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: _pesan(e), variant: ToastVariant.danger);
      // Status di layar mungkin basi (mis. sudah absen dari perangkat lain): muat ulang.
      if (e.statusCode == 409) await _muat();
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Absensi')),
      body: _memuat && _daftar == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, key: const Key('absensi.error'), textAlign: TextAlign.center),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton(onPressed: _muat, child: const Text('Coba lagi')),
                      ],
                    ),
                  ),
                )
              : _isi(),
    );
  }

  Widget _isi() {
    final aktif = _aktif;
    final daftar = _daftar;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                aktif == null ? 'Belum absen masuk' : 'Sedang masuk sejak ${formatJam(aktif.jamMasuk)}',
                key: const Key('absensi.status'),
                style: AppTypography.cardTitle,
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  key: const Key('absensi.tombol'),
                  onPressed: _sibuk ? null : _ubahStatus,
                  style: aktif == null ? null : FilledButton.styleFrom(backgroundColor: AppColors.dangerText),
                  child: Text(_sibuk ? 'Memproses...' : (aktif == null ? 'Absen masuk' : 'Absen keluar')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final r in RentangPengeluaran.values)
              ChoiceChip(
                key: Key('absensi.rentang.${r.name}'),
                label: Text(r.label),
                selected: _rentang == r,
                onSelected: (_) {
                  setState(() => _rentang = r);
                  _muat();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (daftar == null || daftar.item.isEmpty)
          Text('Belum ada absensi pada rentang ini.', style: AppTypography.secondary)
        else ...[
          Text('Rekap jam kerja', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.xs),
          for (final r in daftar.rekap)
            ListTile(
              key: Key('absensi.rekap.${r.penggunaNama}'),
              contentPadding: EdgeInsets.zero,
              title: Text(r.penggunaNama),
              subtitle: Text('${r.jumlahHari} hari${r.masihMasuk ? ' · masih masuk' : ''}'),
              trailing: Text(formatDurasi(r.totalMenit), style: AppTypography.bodyEmphasis),
            ),
          const Divider(),
          Text('Riwayat', style: AppTypography.cardTitle),
          for (final i in daftar.item)
            ListTile(
              key: Key('absensi.item.${i.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(i.penggunaNama),
              subtitle: Text(
                '${DateFormat('d MMM', 'id_ID').format(i.jamMasuk)} · ${formatJam(i.jamMasuk)} - '
                '${i.jamKeluar == null ? 'sekarang' : formatJam(i.jamKeluar!)}',
              ),
              trailing: Text(i.durasiMenit == null ? 'berjalan' : formatDurasi(i.durasiMenit!)),
            ),
        ],
      ],
    );
  }
}
