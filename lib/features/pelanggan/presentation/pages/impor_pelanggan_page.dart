import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../produk/presentation/providers/impor_produk_providers.dart';
import '../../domain/pelanggan_csv.dart';

/// Impor pelanggan via template CSV (IMOGI no. 53). Diperiksa dan disimpan di server (butuh
/// internet), lalu data ditarik ke HP lewat sync.
class ImporPelangganPage extends ConsumerStatefulWidget {
  const ImporPelangganPage({super.key});

  @override
  ConsumerState<ImporPelangganPage> createState() => _ImporPelangganPageState();
}

class _ImporPelangganPageState extends ConsumerState<ImporPelangganPage> {
  HasilBacaCsvPelanggan? _bacaan;
  Map<String, dynamic>? _hasilServer;
  bool _sibuk = false;
  String? _error;

  Future<void> _bagikanTemplate() async {
    try {
      await ref.read(pembagiBerkasProvider)('template_pelanggan.csv', templatePelangganCsv());
    } catch (e) {
      if (mounted) showAppToast(context, message: 'Gagal membagikan template: $e', variant: ToastVariant.danger);
    }
  }

  Future<void> _pilihBerkas() async {
    setState(() {
      _error = null;
      _hasilServer = null;
    });
    try {
      final isi = await ref.read(pemilihCsvProvider)();
      if (isi == null) return;
      final bacaan = bacaCsvPelanggan(isi);
      setState(() {
        _bacaan = bacaan;
        _error = bacaan.galat;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Gagal membaca berkas: $e');
    }
  }

  Future<void> _kirim({required bool simulasi}) async {
    final bacaan = _bacaan;
    if (bacaan == null || bacaan.siap.isEmpty) return;
    setState(() {
      _sibuk = true;
      _error = null;
    });
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
      final hasil = await ref.read(backendApiProvider).imporPelanggan(
            accessToken: sesi.accessToken,
            baris: [for (final b in bacaan.siap) b.keJson()],
            simulasi: simulasi,
          );
      setState(() => _hasilServer = hasil);
      if (!simulasi && (hasil['diterima'] as num) > 0) {
        // Tarik pelanggan baru ke HP; gagal sync tidak membatalkan impor.
        unawaited(ref.read(syncRepositoryProvider).jalankan().then((_) {}, onError: (_) {}));
        if (mounted) {
          showAppToast(context, message: '${hasil['diterima']} pelanggan diimpor', variant: ToastVariant.success);
        }
      }
    } on BackendException catch (e) {
      setState(() => _error = e.tidakAdaKoneksi
          ? 'Butuh internet untuk mengimpor pelanggan.'
          : (e.statusCode == 403 ? 'Paket atau peran Anda belum bisa mengimpor pelanggan.' : e.message));
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bacaan = _bacaan;
    return Scaffold(
      appBar: AppBar(title: const Text('Impor pelanggan')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1. Unduh template', style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Kolom: nama, no_hp, email, tanggal_lahir (yyyy-mm-dd atau dd/mm/yyyy), catatan. '
                  'Di Excel, set kolom no_hp sebagai Teks agar angka 0 di depan tidak hilang. '
                  'Nomor HP yang sudah terdaftar ditolak. Maksimal $maksBarisImporPelanggan pelanggan sekali impor.',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('imporPelanggan.template'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Bagikan template CSV'),
                  onPressed: _bagikanTemplate,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('2. Impor pelanggan', style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  key: const Key('imporPelanggan.pilih'),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Pilih berkas CSV'),
                  onPressed: _sibuk ? null : _pilihBerkas,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!,
                      key: const Key('imporPelanggan.error'), style: const TextStyle(color: AppColors.dangerText)),
                ],
                if (bacaan != null && bacaan.galat == null) ..._pratinjau(bacaan),
                if (_hasilServer != null) ..._hasil(_hasilServer!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _pratinjau(HasilBacaCsvPelanggan b) {
    final masalah = b.bermasalah.toList();
    return [
      const SizedBox(height: AppSpacing.sm),
      Text('${b.siap.length} pelanggan siap diimpor, ${masalah.length} baris bermasalah',
          key: const Key('imporPelanggan.ringkasan'), style: AppTypography.bodyEmphasis),
      for (final m in masalah.take(8)) Text('Baris ${m.nomorBaris}: ${m.masalah}', style: AppTypography.secondary),
      if (masalah.length > 8) Text('dan ${masalah.length - 8} baris lainnya', style: AppTypography.secondary),
      const SizedBox(height: AppSpacing.sm),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('imporPelanggan.periksa'),
              onPressed: _sibuk || b.siap.isEmpty ? null : () => _kirim(simulasi: true),
              child: const Text('Periksa dulu'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              key: const Key('imporPelanggan.simpan'),
              onPressed: _sibuk || b.siap.isEmpty ? null : () => _kirim(simulasi: false),
              child: Text(_sibuk ? 'Memproses...' : 'Impor ${b.siap.length} pelanggan'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _hasil(Map<String, dynamic> h) {
    final simulasi = h['simulasi'] == true;
    final ditolak = [
      for (final x in (h['hasil'] as List? ?? const []))
        if ((x as Map<String, dynamic>)['status'] == 'ditolak') x,
    ];
    return [
      const Divider(),
      Text(
        simulasi
            ? 'Hasil pemeriksaan: ${h['diterima']} lolos, ${h['ditolak']} ditolak (belum disimpan)'
            : 'Hasil impor: ${h['diterima']} disimpan, ${h['ditolak']} ditolak',
        key: const Key('imporPelanggan.hasil'),
        style: AppTypography.bodyEmphasis,
      ),
      for (final x in ditolak.take(10)) Text('${x['nama']}: ${x['pesan']}', style: AppTypography.secondary),
      if (ditolak.length > 10) Text('dan ${ditolak.length - 10} lainnya', style: AppTypography.secondary),
    ];
  }
}
