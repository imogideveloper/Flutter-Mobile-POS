import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/order/data/local/tables/tipe_order_table.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// migrasikanTokoId mengganti toko_id lewat raw SQL di 20 tabel sekaligus
/// (lihat PairingDao) - test ini memverifikasi beberapa tabel wakil (bukan
/// seluruhnya) sungguhan berubah, dan baris milik toko LAIN tidak ikut
/// tersentuh.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('migrasikanTokoId mengganti toko_id lama -> baru lintas tabel, tidak sentuh toko lain', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    await db.into(db.tipeOrder).insert(TipeOrderCompanion.insert(
          id: 'tipe-1',
          tokoId: 'toko-default',
          nama: 'Makan di tempat',
          kanal: TipeOrderKanal.makanDiTempat,
          createdAt: now,
          updatedAt: now,
        ));
    await db.into(db.tipeOrder).insert(TipeOrderCompanion.insert(
          id: 'tipe-toko-lain',
          tokoId: 'toko-lain',
          nama: 'Delivery toko lain',
          kanal: TipeOrderKanal.antar,
          createdAt: now,
          updatedAt: now,
        ));

    await db.pairingDao.migrasikanTokoId(dari: 'toko-default', ke: 'toko-asli-123');

    final rows = await db.select(db.tipeOrder).get();
    final punyaKita = rows.firstWhere((r) => r.id == 'tipe-1');
    final punyaLain = rows.firstWhere((r) => r.id == 'tipe-toko-lain');

    expect(punyaKita.tokoId, 'toko-asli-123');
    expect(punyaLain.tokoId, 'toko-lain');
  });

  test('migrasikanTokoId no-op kalau dari == ke', () async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.into(db.tipeOrder).insert(TipeOrderCompanion.insert(
          id: 'tipe-1',
          tokoId: 'toko-x',
          nama: 'Delivery',
          kanal: TipeOrderKanal.antar,
          createdAt: now,
          updatedAt: now,
        ));

    await db.pairingDao.migrasikanTokoId(dari: 'toko-x', ke: 'toko-x');

    final row = await (db.select(db.tipeOrder)..where((t) => t.id.equals('tipe-1'))).getSingle();
    expect(row.tokoId, 'toko-x');
  });
}
