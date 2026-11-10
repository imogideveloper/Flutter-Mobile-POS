import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import '../../../transaksi/presentation/providers/harga_keranjang_provider.dart' show pengaturanOutletProvider;
import '../../data/antrean_repository.dart';

final antreanRepositoryProvider = Provider<AntreanRepository>((ref) {
  return AntreanRepository(ref.watch(appDatabaseProvider));
});

/// Pembuat nomor antrian untuk checkout, atau null bila antrian tidak aktif:
/// fitur `nomor_antrean` harus terbuka di paket DAN pengaturan outlet
/// "pakai nomor antrean" menyala. Dioper ke `TransaksiRepository.checkout`
/// sebagai `buatNomorAntrean` (dipanggil di dalam transaction checkout).
Future<Future<String?> Function()?> siapkanNomorAntrean(WidgetRef ref) async {
  final outletId = ref.read(currentOutletIdProvider);
  final gate = await ref.read(featureGateProvider.future);
  if (!gate.has('nomor_antrean')) return null;
  final pengaturan = await ref.read(pengaturanOutletProvider(outletId).future);
  if (pengaturan == null || !pengaturan.pakaiNomorAntrean) return null;
  final sesi = await ref.read(authSessionStoreProvider).muat();
  if (sesi == null) return null;

  final repo = ref.read(antreanRepositoryProvider);
  return () => repo.nomorBerikutnya(
        outletId: outletId,
        perangkatId: sesi.perangkatId,
        waktu: DateTime.now(),
        awalan: pengaturan.antreanAwalan,
        mulaiDari: pengaturan.antreanMulai < 1 ? 1 : pengaturan.antreanMulai,
      );
}
