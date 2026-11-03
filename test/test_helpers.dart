import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/network/auth_session_store.dart';
import 'package:apps_pos/core/network/connectivity_provider.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/metode_bayar_table.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Beberapa halaman (mis. RiwayatListPage F3.B) kadang coba baca sesi
/// backend lewat authSessionStoreProvider (secure storage sungguhan) -
/// tanpa platform channel asli (lazim di widget test), pemanggilan itu
/// MENGGANTUNG (bukan langsung error) sampai pumpAndSettle timeout. Fake
/// ini balas null (device "belum pairing") seketika, dipakai default di
/// overridesSudahLogin supaya semua test flow tidak kena jebakan ini.
class _FakeAuthSessionStoreNull extends AuthSessionStore {
  _FakeAuthSessionStoreNull() : super(const FlutterSecureStorage());

  @override
  Future<SesiBackend?> muat() async => null;
}

/// Pakai di test fitur yang BUKAN tentang login - lewati LoginPage dengan
/// langsung menganggap 'pengguna-default' sudah login, supaya test fokus
/// ke fitur yang diuji.
class _LangsungLogin extends PenggunaSessionNotifier {
  @override
  String? build() => 'pengguna-default';
}

// Tanpa anotasi tipe return eksplisit (Override tidak diekspor publik dari
// flutter_riverpod) - cukup diinferensi dari isinya, dipakai langsung ke
// parameter `overrides` di ProviderScope.
overridesSudahLogin(AppDatabase db) => [
      appDatabaseProvider.overrideWith((ref) => db),
      currentPenggunaIdProvider.overrideWith(_LangsungLogin.new),
      authSessionStoreProvider.overrideWithValue(_FakeAuthSessionStoreNull()),
      // Temuan A.2 (tahap 5) - tokoProfileProvider jg baca secureStorageProvider
      // langsung (BUKAN lewat authSessionStoreProvider di atas) - StrukPage
      // (snapshot struk) adalah jalur PERTAMA yang benar2 memanggilnya tanpa
      // syarat di widget test, jadi jebakan hang yang sama baru ketahuan di
      // sini. null = "profil toko belum diisi", state valid & aman.
      tokoProfileProvider.overrideWith((ref) async => null),
      // Tahap 5 - layar kelola baru butuh isOnlineProvider (Prinsip 1,
      // tombol simpan nonaktif saat offline). connectivity_plus tidak
      // punya platform channel di widget test, jadi default-kan "online"
      // di sini supaya test yang BUKAN tentang kondisi offline tidak
      // perlu tahu soal ini - test yang justru menguji skenario offline
      // override ulang ke Stream.value(false) di test-nya sendiri.
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ];

/// Metode bayar dasar (F3.A - BayarPage dkk sekarang baca metode_bayar
/// lokal sungguhan, bukan grid hardcode lagi) - dipakai test flow yang
/// pakai overridesSudahLogin (lewat AuthGatePage, jadi tidak ikut
/// terpicu seedMetodeBayarDefault di seed_provider.dart). Panggil SETELAH
/// `AppDatabase(NativeDatabase.memory())` dibuat, sebelum pumpWidget.
Future<void> seedMetodeBayarUjiCoba(AppDatabase db) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db.metodeBayarDao.upsertMetodeBayar(MetodeBayarCompanion.insert(
    id: 'metode-tunai-uji',
    tokoId: 'toko-default',
    nama: 'Tunai',
    tipe: MetodeBayarTipe.tunai,
    masukLaci: const Value(true),
    urutan: const Value(0),
    createdAt: now,
    updatedAt: now,
  ));
  await db.metodeBayarDao.upsertMetodeBayar(MetodeBayarCompanion.insert(
    id: 'metode-qris-uji',
    tokoId: 'toko-default',
    nama: 'QRIS',
    tipe: MetodeBayarTipe.qris,
    masukLaci: const Value(false),
    urutan: const Value(1),
    createdAt: now,
    updatedAt: now,
  ));
  await db.metodeBayarDao.upsertMetodeBayar(MetodeBayarCompanion.insert(
    id: 'metode-kartu-uji',
    tokoId: 'toko-default',
    nama: 'Kartu',
    tipe: MetodeBayarTipe.kartu,
    masukLaci: const Value(false),
    urutan: const Value(2),
    createdAt: now,
    updatedAt: now,
  ));
}
