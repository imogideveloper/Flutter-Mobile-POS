import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/izin_provider.dart';
import '../widgets/app_bottom_nav_bar.dart';
import '../utils/platform_perangkat.dart';

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
    final tersembunyi = tabTersembunyi(izin);
    void pindahTab(int index) =>
        navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);

    // Layar lebar (Windows/tablet): navigasi samping + isi dibatasi lebarnya.
    // Ponsel tetap memakai navigasi bawah seperti sebelumnya.
    if (MediaQuery.sizeOf(context).width >= lebarMinimalDesktop) {
      return Scaffold(
        body: Row(
          children: [
            AppNavRail(
              currentIndex: navigationShell.currentIndex,
              tersembunyi: tersembunyi,
              onTap: pindahTab,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: lebarMaksimalIsi),
                  child: navigationShell,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: navigationShell.currentIndex,
        tersembunyi: tersembunyi,
        onTap: pindahTab,
      ),
    );
  }
}
