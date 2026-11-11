import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/izin_provider.dart';

/// Penjaga halaman: isi hanya tampil bila role pengguna punya [kodeIzin]. Menyembunyikan menu
/// saja tidak cukup (tautan langsung tetap bisa membuka halaman), jadi rute juga dijaga.
/// Selama izin dimuat tampil indikator; tanpa izin tampil pesan, bukan isi halaman.
class IzinGuard extends ConsumerWidget {
  const IzinGuard({super.key, required this.kodeIzin, required this.child});

  final String kodeIzin;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final izin = ref.watch(izinSayaProvider);
    return izin.when(
      data: (daftar) => daftar.contains(kodeIzin) ? child : const _TanpaAkses(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const _TanpaAkses(),
    );
  }
}

class _TanpaAkses extends StatelessWidget {
  const _TanpaAkses();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tidak ada akses')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Peran Anda tidak memiliki izin untuk membuka halaman ini. Hubungi pemilik toko.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
