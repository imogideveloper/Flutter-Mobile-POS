import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/device_pairing_provider.dart';
import '../providers/session_provider.dart';

const _kKunciLayarMenitKey = 'kunci_layar_menit';

/// Pilihan jeda kunci layar (menit). 0 = mati.
const pilihanKunciLayarMenit = [0, 2, 5, 10, 15, 30];

String labelKunciLayar(int menit) => menit <= 0 ? 'Mati' : '$menit menit';

/// Jeda tanpa sentuhan (menit) sebelum HP ini mengunci diri ke layar PIN. 0 = mati (bawaan). Disimpan per
/// perangkat; bukan rahasia sehingga cukup di penyimpanan aman yang sudah dipakai aplikasi.
class KunciLayarMenitNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    try {
      final v = await ref.read(secureStorageProvider).read(key: _kKunciLayarMenitKey);
      final menit = int.tryParse(v ?? '') ?? 0;
      return pilihanKunciLayarMenit.contains(menit) ? menit : 0;
    } catch (_) {
      return 0; // penyimpanan tidak tersedia (mis. tes): kunci otomatis mati
    }
  }

  Future<void> atur(int menit) async {
    state = AsyncData(menit);
    try {
      await ref.read(secureStorageProvider).write(key: _kKunciLayarMenitKey, value: '$menit');
    } catch (_) {}
  }
}

final kunciLayarMenitProvider = AsyncNotifierProvider<KunciLayarMenitNotifier, int>(KunciLayarMenitNotifier.new);

/// Pemantau di akar aplikasi: bila tidak ada sentuhan selama jeda yang dipilih (atau HP ditinggalkan di latar
/// belakang selama itu), pengguna dikeluarkan ke layar PIN lewat [kunci]. Data lokal dan antrean sync tidak
/// disentuh. Tanpa pengguna masuk atau jeda 0 tidak ada timer sama sekali.
class KunciLayarHost extends ConsumerStatefulWidget {
  const KunciLayarHost({super.key, required this.child, required this.kunci});

  final Widget child;

  /// Dipanggil saat waktunya mengunci (mengeluarkan pengguna dan membuka layar PIN).
  final void Function() kunci;

  @override
  ConsumerState<KunciLayarHost> createState() => _KunciLayarHostState();
}

class _KunciLayarHostState extends ConsumerState<KunciLayarHost> with WidgetsBindingObserver {
  Timer? _timer;
  DateTime? _ditinggalkan;

  Duration? get _jeda {
    final menit = ref.read(kunciLayarMenitProvider).value ?? 0;
    if (menit <= 0 || ref.read(currentPenggunaIdProvider) == null) return null;
    return Duration(minutes: menit);
  }

  void _jadwalkan() {
    _timer?.cancel();
    final jeda = _jeda;
    if (jeda != null) _timer = Timer(jeda, _kunciSekarang);
  }

  void _kunciSekarang() {
    _timer?.cancel();
    if (ref.read(currentPenggunaIdProvider) == null) return;
    widget.kunci();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _ditinggalkan ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final sejak = _ditinggalkan;
      _ditinggalkan = null;
      final jeda = _jeda;
      if (sejak != null && jeda != null && DateTime.now().difference(sejak) >= jeda) {
        _kunciSekarang();
      } else {
        _jadwalkan();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pengaturan atau status masuk berubah: pasang ulang (atau matikan) timer.
    ref.listen(kunciLayarMenitProvider, (_, _) => _jadwalkan());
    ref.listen(currentPenggunaIdProvider, (_, _) => _jadwalkan());
    ref.watch(kunciLayarMenitProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _jadwalkan(),
      onPointerMove: (_) => _jadwalkan(),
      child: widget.child,
    );
  }
}
