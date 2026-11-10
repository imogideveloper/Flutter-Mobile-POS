import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/fitur/presentation/providers/feature_gate_provider.dart';
import '../../features/transaksi/presentation/providers/transaksi_providers.dart';
import 'auth_session_store.dart';
import 'connectivity_provider.dart';
import 'sync_repository.dart';

/// Sync otomatis (TASK-111, BUG-004): sebelumnya sync HANYA jalan bila tombol Sync diketuk,
/// sehingga transaksi tertahan di HP sampai ada yang ingat mengetuknya.
///
/// Pemicu: aplikasi dibuka/kembali aktif, koneksi pulih, berkala selama aplikasi terbuka, dan
/// setelah pembayaran selesai. Sync berjalan di latar depan saja (tanpa workmanager); aplikasi
/// yang tertutup penuh tidak menyinkronkan sendiri.
///
/// Aturan: jeda minimum antar sync otomatis supaya tidak membanjiri server, dan jeda diperlebar
/// (maksimal 15 menit) tiap kali gagal supaya server yang sedang bermasalah tidak dihajar terus.
/// Kegagalan tidak pernah menampilkan error ke kasir; transaksi tetap menunggu dan dicoba lagi.
class AutoSync {
  AutoSync({
    required this.jalankan,
    required this.siap,
    this.setelahSelesai,
    this.jedaMinimum = const Duration(seconds: 30),
    this.jedaMaksimum = const Duration(minutes: 15),
    DateTime Function()? sekarang,
  }) : _sekarang = sekarang ?? DateTime.now;

  final Future<void> Function() jalankan;

  /// false = perangkat belum dipasangkan (belum ada yang bisa disinkronkan).
  final Future<bool> Function() siap;

  /// Dipanggil setelah sync sukses (mis. memuat ulang penghitung "menunggu sync").
  final void Function()? setelahSelesai;
  final Duration jedaMinimum;
  final Duration jedaMaksimum;
  final DateTime Function() _sekarang;

  bool _berjalan = false;
  DateTime? _terakhirMulai;
  int _gagalBerturut = 0;

  bool get sedangBerjalan => _berjalan;
  int get gagalBerturut => _gagalBerturut;

  /// Jeda yang berlaku sekarang: [jedaMinimum] dilipatgandakan tiap kegagalan berturut-turut.
  Duration get jedaSaatIni {
    var jeda = jedaMinimum;
    for (var i = 0; i < _gagalBerturut && jeda < jedaMaksimum; i++) {
      jeda *= 2;
    }
    return jeda > jedaMaksimum ? jedaMaksimum : jeda;
  }

  /// Menjalankan sync bila memungkinkan. [paksa] melewati jeda (mis. setelah pembayaran), tetapi
  /// tidak pernah menjalankan dua sync bersamaan. Mengembalikan true bila sync sukses.
  Future<bool> picu({bool paksa = false}) async {
    if (_berjalan) return false;
    final terakhir = _terakhirMulai;
    if (!paksa && terakhir != null && _sekarang().difference(terakhir) < jedaSaatIni) return false;

    _berjalan = true;
    try {
      if (!await siap()) return false;
      _terakhirMulai = _sekarang();
      await jalankan();
      _gagalBerturut = 0;
      setelahSelesai?.call();
      return true;
    } catch (_) {
      _gagalBerturut++;
      return false;
    } finally {
      _berjalan = false;
    }
  }
}

final autoSyncProvider = Provider<AutoSync>((ref) {
  return AutoSync(
    jalankan: () async {
      await ref.read(syncRepositoryProvider).jalankan();
    },
    siap: () async => (await ref.read(authSessionStoreProvider).muat()) != null,
    setelahSelesai: () {
      // Provider satu-shot: tanpa ini angka "menunggu sync" dan status paket tertinggal basi.
      ref.invalidate(transaksiBelumSyncCountProvider);
      ref.invalidate(featureGateProvider);
    },
  );
});

/// Dipanggil setelah pembayaran selesai: kirim transaksi baru tanpa menunggu pemicu berkala.
/// Tidak pernah melempar dan tidak menunggu hasilnya.
void picuSyncSetelahTransaksi(WidgetRef ref) {
  unawaited(ref.read(autoSyncProvider).picu(paksa: true));
}

/// Pemasang pemicu sync otomatis di akar aplikasi. Dipasang di `main()` (bukan di AppsPosApp)
/// supaya tes widget yang memakai AppsPosApp tidak ikut menjalankan timer.
class AutoSyncHost extends ConsumerStatefulWidget {
  const AutoSyncHost({super.key, required this.child, this.interval = const Duration(minutes: 5)});

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<AutoSyncHost> createState() => _AutoSyncHostState();
}

class _AutoSyncHostState extends ConsumerState<AutoSyncHost> with WidgetsBindingObserver {
  Timer? _timer;

  void _picu() => unawaited(ref.read(autoSyncProvider).picu());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _picu());
    // Sync pertama setelah aplikasi tampil.
    WidgetsBinding.instance.addPostFrameCallback((_) => _picu());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _picu();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Koneksi pulih (offline -> online): kirim yang tertahan.
    ref.listen(isOnlineProvider, (sebelum, sesudah) {
      if (sebelum?.value == false && sesudah.value == true) _picu();
    });
    return widget.child;
  }
}
