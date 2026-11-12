import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_repository.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../domain/produk_csv.dart';
import '../providers/impor_produk_providers.dart';
import '../providers/kategori_providers.dart';
import '../providers/produk_providers.dart';

/// Impor produk via template CSV (IMOGI no. 38) dan ekspor daftar produk (no. 39).
/// Impor diperiksa dan disimpan di server (butuh internet), lalu data ditarik ke HP lewat sync.
class ImporEksporProdukPage extends ConsumerStatefulWidget {
  const ImporEksporProdukPage({super.key});

  @override
  ConsumerState<ImporEksporProdukPage> createState() => _ImporEksporProdukPageState();
}

class _ImporEksporProdukPageState extends ConsumerState<ImporEksporProdukPage> {
  HasilBacaCsv? _bacaan;
  String? _namaBerkas;
  Map<String, dynamic>? _hasilServer;
  bool _sibuk = false;
  String? _error;

  void _toast(String pesan, {ToastVariant variant = ToastVariant.info}) {
    if (mounted) showAppToast(context, message: pesan, variant: variant);
  }

  Future<void> _bagikanTemplate() async {
    try {
      await ref.read(pembagiBerkasProvider)('template_produk.csv', templateCsv());
    } catch (e) {
      _toast('Gagal membagikan template: $e', variant: ToastVariant.danger);
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
      final bacaan = bacaCsvProduk(isi);
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
      final hasil = await ref.read(backendApiProvider).imporProduk(
            accessToken: sesi.accessToken,
            baris: [for (final b in bacaan.siap) b.keJson()],
            simulasi: simulasi,
          );
      setState(() => _hasilServer = hasil);
      if (!simulasi && (hasil['diterima'] as num) > 0) {
        // Tarik produk baru ke HP; gagal sync tidak membatalkan impor (akan tersinkron berikutnya).
        unawaited(ref.read(syncRepositoryProvider).jalankan().then((_) {}, onError: (_) {}));
        _toast('${hasil['diterima']} produk diimpor', variant: ToastVariant.success);
      }
    } on BackendException catch (e) {
      setState(() => _error = e.tidakAdaKoneksi
          ? 'Butuh internet untuk mengimpor produk.'
          : (e.statusCode == 403 ? 'Paket atau peran Anda belum bisa mengimpor produk.' : e.message));
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _ekspor() async {
    try {
      final tokoId = ref.read(currentTokoIdProvider);
      final produk = await ref.read(produkRepositoryProvider).watchProdukSemua().first;
      final kategori = await ref.read(kategoriRepositoryProvider).watchKategoriAktif(tokoId).first;
      final namaKategori = {for (final k in kategori) k.id: k.nama};
      final csv = eksporProdukCsv([
        for (final p in produk)
          BarisEkspor(
            nama: p.nama,
            kategori: p.kategoriId == null ? null : namaKategori[p.kategoriId],
            hargaJual: p.hargaJual,
            hpp: p.hpp,
            sku: p.sku,
            barcode: p.barcode,
            deskripsi: p.deskripsi,
          ),
      ]);
      await ref.read(pembagiBerkasProvider)('produk.csv', csv);
    } catch (e) {
      _toast('Gagal mengekspor: $e', variant: ToastVariant.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bacaan = _bacaan;
    return Scaffold(
      appBar: AppBar(title: const Text('Impor & ekspor produk')),
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
                  'Isi template di Excel atau Google Sheets (simpan sebagai CSV). Kolom: nama, kategori, '
                  'harga_jual, hpp, sku, barcode, deskripsi. Maksimal $maksBarisImpor produk sekali impor.',
                  style: AppTypography.secondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('impor.template'),
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
                Text('2. Impor produk', style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  key: const Key('impor.pilih'),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Pilih berkas CSV'),
                  onPressed: _sibuk ? null : _pilihBerkas,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, key: const Key('impor.error'), style: const TextStyle(color: AppColors.dangerText)),
                ],
                if (bacaan != null && bacaan.galat == null) ..._pratinjau(bacaan),
                if (_hasilServer != null) ..._hasil(_hasilServer!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FiturTerkunci(
            kode: 'catalog_export',
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ekspor produk', style: AppTypography.cardTitle),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Bagikan seluruh daftar produk di HP ini sebagai CSV.', style: AppTypography.secondary),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const Key('impor.ekspor'),
                    icon: const Icon(Icons.ios_share_outlined, size: 18),
                    label: const Text('Ekspor produk (CSV)'),
                    onPressed: _ekspor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _pratinjau(HasilBacaCsv b) {
    final masalah = b.bermasalah.toList();
    return [
      const SizedBox(height: AppSpacing.sm),
      Text('${b.siap.length} produk siap diimpor, ${masalah.length} baris bermasalah',
          key: const Key('impor.ringkasan'), style: AppTypography.bodyEmphasis),
      for (final m in masalah.take(8))
        Text('Baris ${m.nomorBaris}: ${m.masalah}', style: AppTypography.secondary),
      if (masalah.length > 8) Text('dan ${masalah.length - 8} baris lainnya', style: AppTypography.secondary),
      const SizedBox(height: AppSpacing.sm),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('impor.periksa'),
              onPressed: _sibuk || b.siap.isEmpty ? null : () => _kirim(simulasi: true),
              child: const Text('Periksa dulu'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              key: const Key('impor.simpan'),
              onPressed: _sibuk || b.siap.isEmpty ? null : () => _kirim(simulasi: false),
              child: Text(_sibuk ? 'Memproses...' : 'Impor ${b.siap.length} produk'),
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
    final kategoriBaru = [for (final k in (h['kategori_baru'] as List? ?? const [])) '$k'];
    return [
      const Divider(),
      Text(
        simulasi
            ? 'Hasil pemeriksaan: ${h['diterima']} lolos, ${h['ditolak']} ditolak (belum disimpan)'
            : 'Hasil impor: ${h['diterima']} disimpan, ${h['ditolak']} ditolak',
        key: const Key('impor.hasil'),
        style: AppTypography.bodyEmphasis,
      ),
      if (kategoriBaru.isNotEmpty) Text('Kategori baru: ${kategoriBaru.join(', ')}', style: AppTypography.secondary),
      for (final x in ditolak.take(10)) Text('${x['nama']}: ${x['pesan']}', style: AppTypography.secondary),
      if (ditolak.length > 10) Text('dan ${ditolak.length - 10} lainnya', style: AppTypography.secondary),
    ];
  }
}
