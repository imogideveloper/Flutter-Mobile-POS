import 'package:apps_pos/features/admin/domain/admin_data.dart';
import 'package:apps_pos/features/admin/presentation/pages/admin_dashboard_page.dart';
import 'package:apps_pos/features/admin/presentation/pages/admin_login_page.dart';
import 'package:apps_pos/features/admin/presentation/providers/admin_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

class _AdminLogin extends AdminSesiNotifier {
  @override
  AdminSesi? build() => const AdminSesi(token: 't', nama: 'Lead Imogi', email: 'lead@imogi.test');
}

class _AdminBelumLogin extends AdminSesiNotifier {
  String? emailTerakhir;

  @override
  AdminSesi? build() => null;

  @override
  Future<void> masuk({required String email, required String password}) async {
    emailTerakhir = email;
    state = AdminSesi(token: 't', nama: 'Lead Imogi', email: email);
  }
}

FiturAdmin _f(int no, String nama, String modul, StatusFitur s, {String? kebutuhan, String? catatan}) => FiturAdmin(
      nomor: no,
      nama: nama,
      modul: modul,
      status: s,
      kebutuhan: kebutuhan,
      ujiHp: false,
      catatan: catatan,
    );

const _pilihan = [
  PilihanJenisUsaha(kode: 'CAF', nama: 'Kafe & Kedai Kopi'),
  PilihanJenisUsaha(kode: 'CAT', nama: 'Katering'),
];

RingkasanAdmin _ringkasan({int usaha = 2}) => RingkasanAdmin(
      totalUsaha: usaha,
      usahaBaru30Hari: 1,
      totalPengguna: 5,
      perPaket: const [ItemJumlah(kode: 'Bisnis', nama: 'Bisnis', jumlah: 2)],
      perJenisUsaha: const [ItemJumlah(kode: 'CAF', nama: 'Kafe & Kedai Kopi', jumlah: 2)],
      trial: const RingkasanTrial(
        diatur: true,
        durasiBulan: 4,
        dalamTrial: 2,
        berakhir: 0,
        hampirBerakhir: 1,
        batasNotifikasiHari: 7,
      ),
      fitur: const RingkasanFitur(sudah: 15, sedang: 34, belum: 15, tidakRelevan: 23, ujiHp: 0, total: 87),
    );

Widget _app(List overrides, {Widget? home}) => ProviderScope(
      overrides: [...overrides],
      child: MaterialApp(home: home ?? const AdminDashboardPage()),
    );

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('model', () {
    test('persen selesai dihitung dari fitur relevan', () {
      final r = _ringkasan().fitur;
      expect(r.relevan, 64);
      expect(r.persenSelesai, 23); // 15/64
    });

    test('kelompokkanPerModul dan modul yang belum ada', () {
      final daftar = [
        _f(1, 'A', 'Kasir', StatusFitur.sudah),
        _f(2, 'B', 'Kasir', StatusFitur.belum),
        _f(3, 'C', 'Akuntansi', StatusFitur.belum),
        _f(4, 'D', 'Akuntansi', StatusFitur.tidakRelevan),
      ];
      final moduls = kelompokkanPerModul(daftar);
      expect(moduls.map((m) => m.modul), ['Kasir', 'Akuntansi']);
      expect(moduls[0].belumAda, isFalse);
      expect(moduls[0].hitung(StatusFitur.sudah), 1);
      expect(moduls[1].belumAda, isTrue, reason: 'semua fitur relevan belum ada');
    });

    test('status tak dikenal dianggap belum, bukan sudah', () {
      expect(StatusFitur.dari('aneh'), StatusFitur.belum);
      expect(StatusFitur.dari('tidak_relevan'), StatusFitur.tidakRelevan);
    });
  });

  testWidgets('dashboard: ringkasan, usaha, dan fitur tampil; filter jenis usaha menyaring fitur', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app([
      adminSesiProvider.overrideWith(_AdminLogin.new),
      adminJenisUsahaPilihanProvider.overrideWith((ref) async => _pilihan),
      adminRingkasanProvider.overrideWith((ref) async => _ringkasan()),
      adminUsahaProvider.overrideWith((ref) async => [
            UsahaAdmin(
              id: 'u1',
              nama: 'Kopi Senja',
              jenisUsahaNama: 'Kafe & Kedai Kopi',
              pemilikNama: 'Rina',
              email: 'rina@kopi.test',
              noHp: null,
              terdaftar: DateTime(2026, 11, 1),
              usiaHari: 14,
              paket: 'Bisnis',
              paketLangganan: 'Gratis',
              statusLangganan: 'gratis',
              trialAktif: true,
              trialBerakhir: DateTime(2027, 3, 1),
              trialHariTersisa: 106,
              jumlahPengguna: 3,
              jumlahOutlet: 1,
              terakhirSync: null,
            ),
          ]),
      adminFiturProvider.overrideWith((ref) async {
        final jenis = ref.watch(adminJenisUsahaFilterProvider);
        return jenis == 'CAT'
            ? [_f(1, 'Kasir (POS)', 'Kasir & Transaksi', StatusFitur.tidakRelevan, kebutuhan: 'na')]
            : [
                _f(1, 'Kasir (POS)', 'Kasir & Transaksi', StatusFitur.sudah, catatan: 'Printer belum teruji'),
                _f(2, 'Scan barcode', 'Kasir & Transaksi', StatusFitur.belum),
                _f(80, 'Akun dan jurnal', 'Akuntansi', StatusFitur.belum),
              ];
      }),
    ]));
    await tester.pumpAndSettle();

    // Ringkasan
    expect(find.text('Dashboard Administrator'), findsOneWidget);
    expect(find.text('Lead Imogi'), findsOneWidget);
    expect(find.byKey(const Key('adminDashboard.totalUsaha')), findsOneWidget);
    expect(find.text('2 usaha'), findsOneWidget); // paket Bisnis
    expect(find.textContaining('Batas trial 4 bulan'), findsOneWidget);
    expect(find.textContaining('15 dari 64 fitur relevan sudah terpasang (23%)'), findsOneWidget);
    expect(find.textContaining('Lulus uji di HP: 0'), findsOneWidget);

    // Filter jenis usaha F&B tersedia
    expect(find.byKey(const Key('adminDashboard.filter.CAF')), findsOneWidget);
    expect(find.byKey(const Key('adminDashboard.filter.CAT')), findsOneWidget);

    // Tab Usaha
    await tester.tap(find.text('Usaha'));
    await tester.pumpAndSettle();
    expect(find.text('Kopi Senja'), findsOneWidget);
    expect(find.textContaining('Trial sampai'), findsOneWidget);
    expect(find.textContaining('3 pengguna'), findsOneWidget);
    expect(find.text('Belum pernah sync'), findsOneWidget);

    // Tab Fitur: modul Akuntansi belum ada sama sekali
    await tester.tap(find.text('Fitur'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adminDashboard.modul.Akuntansi')), findsOneWidget);
    expect(find.text('Belum ada fitur yang terpasang'), findsOneWidget);
    expect(find.textContaining('1 sudah · 0 sedang · 1 belum (dari 2 relevan)'), findsOneWidget);

    // Saring status "Belum": modul Kasir tetap tampil (ada 1 belum)
    await tester.tap(find.byKey(const Key('adminDashboard.status.belum')));
    await tester.pumpAndSettle();
    expect(find.text('2. Scan barcode'), findsOneWidget);
    expect(find.text('1. Kasir (POS)'), findsNothing);

    // Filter Katering: fitur 1 jadi tidak relevan
    await tester.tap(find.byKey(const Key('adminDashboard.statusSemua')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adminDashboard.filter.CAT')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adminDashboard.modul.Akuntansi')), findsNothing);
    expect(find.textContaining('Kasir & Transaksi'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('dashboard tanpa sesi admin diarahkan ke login', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('beranda')),
      GoRoute(path: '/admin', builder: (_, _) => const AdminDashboardPage()),
      GoRoute(path: '/admin/login', builder: (_, _) => const AdminLoginPage()),
    ], initialLocation: '/admin');
    await tester.pumpWidget(ProviderScope(
      overrides: [adminSesiProvider.overrideWith(_AdminBelumLogin.new)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adminLogin.masuk')), findsOneWidget);
  });

  testWidgets('login admin: validasi lalu masuk ke dashboard', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('beranda')),
      GoRoute(path: '/admin', builder: (_, _) => const Text('halaman-dashboard')),
      GoRoute(path: '/admin/login', builder: (_, _) => const AdminLoginPage()),
    ], initialLocation: '/admin/login');
    final notifier = _AdminBelumLogin();
    await tester.pumpWidget(ProviderScope(
      overrides: [adminSesiProvider.overrideWith(() => notifier)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adminLogin.masuk')));
    await tester.pumpAndSettle();
    expect(find.text('Isi email yang valid'), findsOneWidget);
    expect(notifier.emailTerakhir, isNull);

    await tester.enterText(find.byKey(const Key('adminLogin.email')), 'lead@imogi.test');
    await tester.enterText(find.byKey(const Key('adminLogin.password')), 'sandi-uji-panjang');
    await tester.tap(find.byKey(const Key('adminLogin.masuk')));
    await tester.pumpAndSettle();

    expect(notifier.emailTerakhir, 'lead@imogi.test');
    expect(find.text('halaman-dashboard'), findsOneWidget);
  });
}
