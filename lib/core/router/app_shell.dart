import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/izin_provider.dart';
import '../widgets/app_bottom_nav_bar.dart';

/// Indeks tab bawah (urutan sama dengan branch di app_router.dart).
const tabProduk = 2;
const tabLaporan = 3;

/// Tab yang tidak boleh dilihat role ini. Izin belum termuat/belum login = tersembunyi (aman).
Set<int> tabTersembunyi(Set<String> izin) => {
  if (!izin.contains('produk.kelola')) tabProduk,
  if (!izin.contains('laporan.lihat')) tabLaporan,
};

/// Shell bottom-nav 5 tab (Kasir/Riwayat/Produk/Laporan/Lainnya). Dipakai
/// sebagai `builder` StatefulShellRoute di app_router.dart. Tab Produk dan Laporan
/// hanya tampil bila role punya izinnya.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final izin = ref.watch(izinSayaProvider).value ?? const <String>{};
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: navigationShell.currentIndex,
        tersembunyi: tabTersembunyi(izin),
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
