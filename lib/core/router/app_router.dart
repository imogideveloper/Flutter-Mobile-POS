import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/auth_gate_page.dart';
import '../../features/auth/presentation/pages/pengguna_form_page.dart';
import '../../features/auth/presentation/pages/pengguna_list_page.dart';
import '../../features/laporan/presentation/pages/laporan_page.dart';
import '../../features/pelanggan/presentation/pages/pelanggan_list_page.dart';
import '../../features/pelanggan/presentation/pages/pelunasan_page.dart';
import '../../features/pelanggan/presentation/pages/piutang_list_page.dart';
import '../../features/lainnya/presentation/pages/lainnya_page.dart';
import '../../features/lainnya/presentation/pages/paket_langganan_page.dart';
import '../../features/lainnya/presentation/pages/pengaturan_metode_bayar_page.dart';
import '../../features/lainnya/presentation/pages/pengaturan_outlet_struk_page.dart';
import '../../features/lainnya/presentation/pages/pengaturan_printer_page.dart';
import '../../features/produk/domain/kategori.dart';
import '../../features/produk/domain/produk.dart';
import '../../features/produk/presentation/pages/kategori_form_page.dart';
import '../../features/produk/presentation/pages/kategori_list_page.dart';
import '../../features/produk/presentation/pages/produk_form_page.dart';
import '../../features/produk/presentation/pages/produk_list_page.dart';
import '../../features/order/presentation/pages/tipe_order_meja_page.dart';
import '../../features/pelanggan/presentation/pages/level_member_aturan_poin_page.dart';
import '../../features/promo/domain/pajak.dart';
import '../../features/promo/domain/promo.dart';
import '../../features/promo/presentation/pages/pajak_form_page.dart';
import '../../features/promo/presentation/pages/pajak_list_page.dart';
import '../../features/promo/presentation/pages/promo_form_page.dart';
import '../../features/promo/presentation/pages/promo_list_page.dart';
import '../../features/shift/presentation/pages/buka_shift_form_page.dart';
import '../../features/shift/presentation/pages/catat_kas_form_page.dart';
import '../../features/shift/presentation/pages/shift_page.dart';
import '../../features/shift/presentation/pages/tutup_shift_form_page.dart';
import '../../features/stok/presentation/pages/stok_list_page.dart';
import '../../features/stok/presentation/pages/stok_mutasi_form_page.dart';
import '../../features/transaksi/domain/hasil_transaksi.dart';
import '../../features/transaksi/presentation/pages/bayar_kasbon_page.dart';
import '../../features/transaksi/presentation/pages/bayar_page.dart';
import '../../features/transaksi/presentation/pages/bayar_qris_page.dart';
import '../../features/transaksi/presentation/pages/kasir_page.dart';
import '../../features/transaksi/presentation/pages/keranjang_page.dart';
import '../../features/transaksi/presentation/pages/pesanan_tersimpan_list_page.dart';
import '../../features/transaksi/presentation/pages/riwayat_list_page.dart';
import '../../features/transaksi/presentation/pages/struk_page.dart';
import 'app_shell.dart';

/// Provider, bukan top-level singleton - GoRouter menyimpan lokasi
/// navigasi saat ini sebagai state internal. Kalau instance-nya dibagi
/// lintas ProviderScope (mis. antar widget test yang masing-masing bikin
/// AppsPosApp baru), lokasi dari test sebelumnya nyangkut ke test
/// berikutnya walau ProviderScope-nya sudah fresh.
final appRouterProvider = Provider<GoRouter>((ref) => _buildRouter());

GoRouter _buildRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const AuthGatePage(),
    ),

    // Bottom-nav shell: 5 tab. Sengaja TIDAK pakai StatefulShellRoute.indexedStack
    // bawaan - implementasi defaultnya membungkus tiap branch tidak aktif dengan
    // Offstage di dalam IndexedStack, dan kombinasi Offstage + ListView/Viewport
    // memicu bug null-check lama di semantics flush Flutter SDK
    // (flutter/flutter#192724, #189942 - masih belum rilis stabil di 3.44) yang
    // bikin widget test timeout/crash begitu ada ListView berisi data di branch
    // manapun. navigatorContainerBuilder custom ini hanya me-mount branch yang
    // sedang aktif (branch lain benar2 di-unmount, bukan di-offstage) - lebih
    // aman walau konsekuensinya state navigasi dalam satu tab (bukan state
    // Riverpod, itu tetap awet) reset saat pindah tab lalu balik lagi.
    StatefulShellRoute(
      builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
      navigatorContainerBuilder: (context, navigationShell, children) =>
          children[navigationShell.currentIndex],
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/kasir',
              builder: (context, state) => const KasirPage(),
              routes: [
                GoRoute(
                  path: 'keranjang',
                  builder: (context, state) => const KeranjangPage(),
                ),
                GoRoute(
                  path: 'bayar',
                  builder: (context, state) => const BayarPage(),
                  routes: [
                    GoRoute(
                      path: 'qris',
                      builder: (context, state) =>
                          BayarQrisPage(metodeBayarId: state.extra as String?),
                    ),
                    GoRoute(
                      path: 'kasbon',
                      builder: (context, state) => const BayarKasbonPage(),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'struk',
                  builder: (context, state) => StrukPage(hasil: state.extra as HasilTransaksi),
                ),
                GoRoute(
                  path: 'pesanan-tersimpan',
                  builder: (context, state) => const PesananTersimpanListPage(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/riwayat',
              builder: (context, state) => const RiwayatListPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/produk',
              builder: (context, state) => const ProdukListPage(),
              routes: [
                GoRoute(
                  path: 'tambah',
                  builder: (context, state) => ProdukFormPage(produk: state.extra as Produk?),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/laporan',
              builder: (context, state) => const LaporanPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/lainnya',
              builder: (context, state) => const LainnyaPage(),
              routes: [
                GoRoute(
                  path: 'printer',
                  builder: (context, state) => const PengaturanPrinterPage(),
                ),
                GoRoute(
                  path: 'outlet-struk',
                  builder: (context, state) => const PengaturanOutletStrukPage(),
                ),
                GoRoute(
                  path: 'metode-bayar',
                  builder: (context, state) => const PengaturanMetodeBayarPage(),
                ),
                GoRoute(
                  path: 'paket-langganan',
                  builder: (context, state) => const PaketLanggananPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),

    // Halaman full-screen di luar bottom nav.
    GoRoute(
      path: '/pengguna',
      builder: (context, state) => const PenggunaListPage(),
      routes: [
        GoRoute(
          path: 'tambah',
          builder: (context, state) => const PenggunaFormPage(),
        ),
        GoRoute(
          path: 'edit',
          builder: (context, state) =>
              PenggunaFormPage(penggunaEdit: state.extra as Map<String, dynamic>),
        ),
      ],
    ),
    GoRoute(
      path: '/stok',
      builder: (context, state) => const StokListPage(),
      routes: [
        GoRoute(
          path: 'catat',
          builder: (context, state) => const StokMutasiFormPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/shift',
      builder: (context, state) => const ShiftPage(),
      routes: [
        GoRoute(
          path: 'buka',
          builder: (context, state) => const BukaShiftFormPage(),
        ),
        GoRoute(
          path: 'tutup',
          builder: (context, state) => TutupShiftFormPage(shiftId: state.extra as String),
        ),
        GoRoute(
          path: 'kas',
          builder: (context, state) => CatatKasFormPage(shiftId: state.extra as String),
        ),
      ],
    ),
    GoRoute(
      path: '/tipe-order-meja',
      builder: (context, state) => const TipeOrderMejaPage(),
    ),
    GoRoute(
      path: '/level-member-poin',
      builder: (context, state) => const LevelMemberAturanPoinPage(),
    ),
    GoRoute(
      path: '/kategori',
      builder: (context, state) => const KategoriListPage(),
      routes: [
        GoRoute(
          path: 'tambah',
          builder: (context, state) => const KategoriFormPage(),
        ),
        GoRoute(
          path: 'edit',
          builder: (context, state) => KategoriFormPage(kategoriEdit: state.extra as Kategori),
        ),
      ],
    ),
    GoRoute(
      path: '/pajak',
      builder: (context, state) => const PajakListPage(),
      routes: [
        GoRoute(
          path: 'tambah',
          builder: (context, state) => const PajakFormPage(),
        ),
        GoRoute(
          path: 'edit',
          builder: (context, state) => PajakFormPage(pajakEdit: state.extra as Pajak),
        ),
      ],
    ),
    GoRoute(
      path: '/promo',
      builder: (context, state) => const PromoListPage(),
      routes: [
        GoRoute(
          path: 'tambah',
          builder: (context, state) => const PromoFormPage(),
        ),
        GoRoute(
          path: 'edit',
          builder: (context, state) => PromoFormPage(promoEdit: state.extra as Promo),
        ),
      ],
    ),
    GoRoute(
      path: '/pelanggan',
      builder: (context, state) => const PelangganListPage(),
    ),
    GoRoute(
      path: '/piutang',
      builder: (context, state) => const PiutangListPage(),
      routes: [
        GoRoute(
          path: 'pelunasan',
          builder: (context, state) => PelunasanPage(pelangganId: state.extra as String),
        ),
      ],
    ),
  ],
);
