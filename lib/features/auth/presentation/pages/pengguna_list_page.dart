import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/pin_approval.dart';
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/avatar_initial.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/offline_notice_banner.dart';

/// Tahap 5b (desain #1) - "karyawan = baris di tabel pengguna server;
/// semua CRUD karyawan lewat server". Layar ini DITULIS ULANG dari versi
/// Tahap 5 (LOKAL murni) - sejak identitas karyawan disatukan, data
/// kelola yang benar HARUS dari server (sama pola online-direct dgn
/// pajak/promo/pelanggan). Layar PIN harian (login_page.dart, baca cache
/// lokal hasil /sync/pull) TIDAK disentuh sama sekali oleh perubahan ini.
class PenggunaListPage extends ConsumerStatefulWidget {
  const PenggunaListPage({super.key});

  @override
  ConsumerState<PenggunaListPage> createState() => _PenggunaListPageState();
}

class _PenggunaListPageState extends ConsumerState<PenggunaListPage> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _daftar = [];
  Map<String, String> _namaRole = {};

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() => _memuat = true);
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) {
        setState(() => _error = 'Device belum pairing ke backend.');
        return;
      }
      final api = ref.read(backendApiProvider);
      final daftarRole = await api.getJson(accessToken: sesi.accessToken, path: '/roles') as List;
      final daftarPengguna = await api.getJson(accessToken: sesi.accessToken, path: '/pengguna') as List;
      _namaRole = {for (final r in daftarRole) r['id'] as String: r['nama'] as String};
      _daftar = daftarPengguna.cast<Map<String, dynamic>>();
    } catch (e) {
      _error = 'Gagal memuat karyawan: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _tambahPengguna() async {
    final disetujuiOleh = await mintaOtorisasi(
      context: context,
      ref: ref,
      kodeIzin: 'pengguna.kelola',
      aksiLabel: 'Tambah pengguna',
    );
    if (disetujuiOleh == null) {
      if (mounted) {
        showAppToast(context, message: 'Tidak diotorisasi', variant: ToastVariant.danger);
      }
      return;
    }
    if (mounted) {
      await context.push('/pengguna/tambah');
      _muat();
    }
  }

  Future<void> _editPengguna(Map<String, dynamic> pengguna) async {
    final disetujuiOleh = await mintaOtorisasi(
      context: context,
      ref: ref,
      kodeIzin: 'pengguna.kelola',
      aksiLabel: 'Ubah pengguna',
    );
    if (disetujuiOleh == null) {
      if (mounted) {
        showAppToast(context, message: 'Tidak diotorisasi', variant: ToastVariant.danger);
      }
      return;
    }
    if (mounted) {
      await context.push('/pengguna/edit', extra: pengguna);
      _muat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Karyawan dan Hak Akses')),
      floatingActionButton: FloatingActionButton(
        onPressed: _tambahPengguna,
        tooltip: 'Tambah pengguna',
        child: const Icon(Icons.add),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  children: [
                    const OfflineNoticeBanner(),
                    if (_daftar.isEmpty)
                      const EmptyState(icon: Icons.people_outline, message: 'Belum ada karyawan')
                    else
                      for (final pengguna in _daftar) ...[
                        AppCard(
                          onTap: () => _editPengguna(pengguna),
                          child: Row(
                            children: [
                              AvatarInitial.fromName(pengguna['nama'] as String),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(pengguna['nama'] as String),
                                    Text(
                                      _namaRole[pengguna['role_id']] ?? '-',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (pengguna['aktif'] != true)
                                const Padding(
                                  padding: EdgeInsets.only(left: AppSpacing.sm),
                                  child: Text('Nonaktif', style: TextStyle(color: Colors.red)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                  ],
                ),
    );
  }
}
