import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class _NavTab {
  const _NavTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _tabs = [
  _NavTab('Kasir', Icons.point_of_sale_outlined),
  _NavTab('Riwayat', Icons.receipt_long_outlined),
  _NavTab('Produk', Icons.inventory_2_outlined),
  _NavTab('Laporan', Icons.bar_chart_outlined),
  _NavTab('Lainnya', Icons.more_horiz),
];

/// Bottom nav 5 tab sesuai layar "Lainnya" di mockup: height 66, bg putih,
/// border-top 1px, tab aktif warna primary bold.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.tersembunyi = const {},
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Indeks tab yang tidak ditampilkan (bukan hak role pengguna).
  final Set<int> tersembunyi;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderDefault)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              if (!tersembunyi.contains(i))
                Expanded(
                  child: _NavItem(
                    tab: _tabs[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(tab.icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(
            tab.label,
            style: AppTypography.secondary.copyWith(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
