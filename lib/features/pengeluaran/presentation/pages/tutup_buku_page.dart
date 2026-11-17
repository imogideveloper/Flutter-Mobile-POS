import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import 'settlement_page.dart' show tanggalIso;

/// Tutup buku (IMOGI no. 78). Hanya Owner yang bisa menutup atau membuka kembali. Setelah ditutup, pengeluaran,
/// settlement, dan anggaran bertanggal pada/sebelum tanggal tutup tidak bisa diubah. Butuh internet.
class TutupBukuPage extends ConsumerStatefulWidget {
  const TutupBukuPage({super.key});

  @override
  ConsumerState<TutupBukuPage> createState() => _TutupBukuPageState();
}

class _TutupBukuPageState extends ConsumerState<TutupBukuPage> {
  String? _ditutupSampai;
  List<(String, String?)> _riwayat = const [];
  DateTime _pilihan = DateTime.now().subtract(const Duration(days: 1));
  final _catatan = TextEditingController();
  String? _error;
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _catatan.dispose();
    super.dispose();
  }

  Future<String> _token() async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
    return sesi.accessToken;
  }

  void _terapkan(dynamic json) {
    final m = json as Map;
    _ditutupSampai = m['ditutup_sampai'] as String?;
    _riwayat = [
      for (final r in m['riwayat'] as List) ((r as Map)['sampai'] as String, r['catatan'] as String?),
    ];
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      _terapkan(await ref.read(backendApiProvider).getJson(accessToken: await _token(), path: '/tutup-buku'));
    } on BackendException catch (e) {
      _error = e.tidakAdaKoneksi ? 'Butuh internet untuk melihat status tutup buku.' : e.message;
    } catch (e) {
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _tutup() async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tutup buku?'),
        content: Text(
          'Pembukuan sampai ${tanggalIso(_pilihan)} akan dikunci: pengeluaran, settlement, dan anggaran '
          'pada tanggal itu atau sebelumnya tidak bisa diubah. Hanya Owner yang bisa membukanya kembali.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(key: const Key('tutupBuku.konfirmasi'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Tutup buku')),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    await _panggil(
      () async => ref.read(backendApiProvider).postJson(
            accessToken: await _token(),
            path: '/tutup-buku',
            body: {
              'sampai': tanggalIso(_pilihan),
              if (_catatan.text.trim().isNotEmpty) 'catatan': _catatan.text.trim(),
            },
          ),
      'Buku ditutup',
    );
  }

  Future<void> _bukaKembali() async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buka kembali?'),
        content: Text('Penutupan sampai $_ditutupSampai dibatalkan. Periode itu bisa diubah lagi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(key: const Key('tutupBuku.konfirmasiBuka'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Buka kembali')),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    await _panggil(
      () async {
        final token = await _token();
        await ref.read(backendApiProvider).deleteJson(accessToken: token, path: '/tutup-buku/terakhir');
        return ref.read(backendApiProvider).getJson(accessToken: token, path: '/tutup-buku');
      },
      'Penutupan terakhir dibuka kembali',
    );
  }

  Future<void> _panggil(Future<dynamic> Function() aksi, String berhasil) async {
    try {
      _terapkan(await aksi());
      if (!mounted) return;
      setState(() {});
      showAppToast(context, message: berhasil, variant: ToastVariant.success);
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tutup buku')),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: Text(_error!)))
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status pembukuan', style: AppTypography.secondary),
                          Text(
                            _ditutupSampai == null ? 'Belum pernah ditutup' : 'Ditutup sampai $_ditutupSampai',
                            key: const Key('tutupBuku.status'),
                            style: AppTypography.cardTitle,
                          ),
                          if (_ditutupSampai != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                key: const Key('tutupBuku.bukaKembali'),
                                onPressed: _bukaKembali,
                                child: const Text('Buka kembali penutupan terakhir'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ListTile(
                      key: const Key('tutupBuku.tanggal'),
                      title: const Text('Tutup sampai tanggal'),
                      subtitle: Text(tanggalIso(_pilihan)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final t = await showDatePicker(
                          context: context,
                          initialDate: _pilihan,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (t != null) setState(() => _pilihan = t);
                      },
                    ),
                    TextField(
                      controller: _catatan,
                      decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(key: const Key('tutupBuku.tutup'), onPressed: _tutup, child: const Text('Tutup buku')),
                    const SizedBox(height: AppSpacing.lg),
                    if (_riwayat.isNotEmpty) Text('Riwayat penutupan', style: AppTypography.cardTitle),
                    for (final r in _riwayat) ListTile(title: Text(r.$1), subtitle: r.$2 == null ? null : Text(r.$2!)),
                  ],
                ),
    );
  }
}
