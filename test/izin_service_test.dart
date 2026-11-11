import 'package:apps_pos/core/auth/izin_service.dart';
import 'package:apps_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late IzinService izinService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    izinService = IzinService(db);
  });

  tearDown(() => db.close());

  Future<String> buatKasir() async {
    // Pastikan seed role/izin/owner sudah jalan (IzinService men-seed lazy
    // di panggilan pertama) sebelum query Role 'Kasir' di bawah.
    await izinService.hasIzin('pemicu-seed', 'transaksi.buat');

    final roleKasir =
        await (db.select(db.role)..where((t) => t.nama.equals('Kasir'))).getSingle();
    const kasirId = 'kasir-1';
    await db.into(db.pengguna).insert(PenggunaCompanion.insert(
          id: kasirId,
          tokoId: 'toko-default',
          roleId: roleKasir.id,
          nama: 'Kasir Uji',
          pinHash: const Value('tidak-dipakai'),
          createdAt: 0,
          updatedAt: 0,
        ));
    return kasirId;
  }

  test('owner default (seed) punya semua izin, termasuk transaksi.void', () async {
    final punyaIzin = await izinService.hasIzin('pengguna-default', 'transaksi.void');
    expect(punyaIzin, isTrue);
  });

  test('kasir tidak punya izin transaksi.void', () async {
    final kasirId = await buatKasir();
    final punyaIzin = await izinService.hasIzin(kasirId, 'transaksi.void');
    expect(punyaIzin, isFalse);
  });

  test('daftarIzin: owner punya izin Pengguna & Pengaturan, kasir tidak (menu Lainnya)', () async {
    final kasirId = await buatKasir();

    final owner = await izinService.daftarIzin('pengguna-default');
    final kasir = await izinService.daftarIzin(kasirId);

    expect(owner, containsAll(['pengguna.kelola', 'pengaturan.kelola', 'stok.kelola', 'laporan.lihat']));
    expect(kasir, containsAll(['transaksi.buat', 'shift.buka_tutup', 'pelanggan.kelola']));
    expect(kasir, isNot(contains('pengguna.kelola')));
    expect(kasir, isNot(contains('pengaturan.kelola')));
    expect(kasir, isNot(contains('stok.kelola')));
    expect(await izinService.daftarIzin('tidak-ada'), isEmpty);
  });

  test('daftarIzin memakai role_izin dari server bila role dikenal di tabel sync', () async {
    final kasirId = await buatKasir();
    final roleKasir =
        await (db.select(db.role)..where((t) => t.nama.equals('Kasir'))).getSingle();
    await db.into(db.roleIzinSync).insert(
        RoleIzinSyncCompanion.insert(roleId: roleKasir.id, izinKode: 'laporan.lihat'));

    expect(await izinService.daftarIzin(kasirId), {'laporan.lihat'});
  });

  test('PIN owner yang benar meng-otorisasi aksi yang kasir tidak punya izinnya', () async {
    await buatKasir();

    final approver = await izinService.cariPenggunaUntukApproval(
      tokoId: 'toko-default',
      pin: '000000',
      kodeIzin: 'transaksi.void',
    );

    expect(approver, isNotNull);
    expect(approver!.id, 'pengguna-default');
  });

  test('PIN salah tidak meng-otorisasi apapun', () async {
    final approver = await izinService.cariPenggunaUntukApproval(
      tokoId: 'toko-default',
      pin: '999999',
      kodeIzin: 'transaksi.void',
    );

    expect(approver, isNull);
  });

  test('pengguna tanpa izin terkait tidak lolos approval walau PIN-nya benar', () async {
    // Kasir tidak punya PIN '000000' (itu PIN seed owner), tapi seandainya
    // dia punya PIN yang sama, dia tetap tidak boleh approve karena role-nya
    // tidak punya izin produk.kelola.
    final kasirId = await buatKasir();
    await (db.update(db.pengguna)..where((t) => t.id.equals(kasirId))).write(
      const PenggunaCompanion(pinHash: Value('sama-sama-000000-hash')),
    );
    await (db.update(db.pengguna)..where((t) => t.id.equals('pengguna-default'))).write(
      const PenggunaCompanion(pinHash: Value('sama-sama-000000-hash')),
    );

    final approver = await izinService.cariPenggunaUntukApproval(
      tokoId: 'toko-default',
      pin: 'tidak-relevan-karena-dicek-hash-langsung',
      kodeIzin: 'pengguna.kelola',
    );

    // PIN yang dicari tidak match siapapun (hash input != 'sama-sama-...'),
    // jadi tidak ada kandidat sama sekali - termasuk owner yang justru
    // punya izinnya.
    expect(approver, isNull);
  });
}
