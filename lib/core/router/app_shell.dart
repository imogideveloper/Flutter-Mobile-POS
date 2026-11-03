import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_bottom_nav_bar.dart';

/// Shell bottom-nav 5 tab (Kasir/Riwayat/Produk/Laporan/Lainnya). Dipakai
/// sebagai `builder` StatefulShellRoute.indexedStack di app_router.dart -
/// `navigationShell` mempertahankan state tiap tab (bukan rebuild dari nol
/// saat pindah tab).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
