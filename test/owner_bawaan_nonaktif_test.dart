import 'package:apps_pos/core/auth/izin_service.dart';
import 'package:apps_pos/core/auth/pin_hash.dart';
import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/database/pengguna_dao.dart';
import 'package:apps_pos/core/database/seed.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Temuan S1: Owner bawaan seed lokal (PIN 000000) harus mati begitu perangkat
/// punya pengguna asli dari server, supaya PIN itu tidak bisa menyetujui
/// diskon/void/refund.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedRoleDanOwner(db);
  });
  tearDown(() => db.close());

  Future<void> penggunaServer({String? pin = '482913', bool aktif = true, bool hapus = false}) {
    return db.penggunaDao.upsertPenggunaDariSync(PenggunaCompanion.insert(
      id: 'u-server-1',
      tokoId: 'toko-default',
      roleId: 'role-owner',
      nama: 'Pemilik Asli',
      pinHash: Value(pin == null ? null : hashPin(pin)),
      aktif: Value(aktif),
      serverPenggunaId: const Value('u-server-1'),
      createdAt: 1,
      updatedAt: 1,
      deletedAt: Value(hapus ? 2 : null),
    ));
  }

  Future<PenggunaRow> bawaan() =>
      (db.select(db.pengguna)..where((t) => t.id.equals(PenggunaDao.idOwnerBawaan))).getSingle();

  test('seed membuat Owner bawaan ber-PIN 000000 (kondisi sebelum pairing)', () async {
    final row = await bawaan();
    expect(row.aktif, isTrue);
    expect(verifyPin('000000', row.pinHash), isTrue);
  });

  test('tanpa pengguna dari server: Owner bawaan dibiarkan agar perangkat tidak terkunci', () async {
    expect(await db.penggunaDao.nonaktifkanOwnerBawaanBilaAdaPenggunaServer(), isFalse);
    expect((await bawaan()).aktif, isTrue);
  });

  test('pengguna server tanpa PIN / nonaktif / terhapus tidak cukup untuk mematikan Owner bawaan', () async {
    await penggunaServer(pin: null);
    expect(await db.penggunaDao.nonaktifkanOwnerBawaanBilaAdaPenggunaServer(), isFalse);
    await penggunaServer(aktif: false);
    expect(await db.penggunaDao.nonaktifkanOwnerBawaanBilaAdaPenggunaServer(), isFalse);
    await penggunaServer(hapus: true);
    expect(await db.penggunaDao.nonaktifkanOwnerBawaanBilaAdaPenggunaServer(), isFalse);
    expect((await bawaan()).aktif, isTrue);
  });

  test('ada pengguna server ber-PIN: Owner bawaan nonaktif, PIN dihapus, PIN 000000 tidak bisa menyetujui', () async {
    await penggunaServer();
    expect(await db.penggunaDao.nonaktifkanOwnerBawaanBilaAdaPenggunaServer(), isTrue);

    final row = await bawaan();
    expect(row.aktif, isFalse);
    expect(row.pinHash, isNull);

    // Baris tetap ada (transaksi lama bisa merujuknya), tetapi tidak bisa jadi penyetuju.
    final izin = IzinService(db);
    expect(await izin.cariPenggunaUntukApproval(tokoId: 'toko-default', pin: '000000', kodeIzin: 'transaksi.diskon'), isNull, reason: 'PIN bawaan tidak boleh lagi menyetujui apa pun');
    expect((await izin.cariPenggunaUntukApproval(tokoId: 'toko-default', pin: '482913', kodeIzin: 'transaksi.diskon'))?.id, 'u-server-1', reason: 'PIN pemilik asli tetap berlaku');
  });

  test('idempoten: dijalankan lagi tidak mengubah apa pun', () async {
    await penggunaServer();
    expect(await db.penggunaDao.nonaktifkanOwnerBawaanBilaAdaPenggunaServer(), isTrue);
    expect(await db.penggunaDao.nonaktifkanOwnerBawaanBilaAdaPenggunaServer(), isFalse);
  });
}
