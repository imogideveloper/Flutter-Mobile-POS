import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/database/seed.dart';
import 'package:apps_pos/core/auth/pin_hash.dart';
import 'package:apps_pos/features/auth/data/pengguna_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PenggunaRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedRoleDanOwner(db);
    repo = PenggunaRepository(db.penggunaDao);
  });

  tearDown(() => db.close());

  test('terapkanIdentitasBackend mengganti id+tokoId baris Owner seed, roleId lokal tidak berubah', () async {
    final sebelum = await db.penggunaDao.cariById('pengguna-default');
    expect(sebelum, isNotNull);
    final roleIdLokalSebelum = sebelum!.roleId;

    await repo.terapkanIdentitasBackend(
      tokoIdLama: 'toko-default',
      tokoIdBaru: 'toko-asli-999',
      penggunaIdBaru: 'pengguna-asli-999',
      namaDariBackend: 'Rina',
      pin: '1234',
    );

    final lama = await db.penggunaDao.cariById('pengguna-default');
    expect(lama, isNull);

    final baru = await db.penggunaDao.cariById('pengguna-asli-999');
    expect(baru, isNotNull);
    expect(baru!.tokoId, 'toko-asli-999');
    expect(baru.nama, 'Rina');
    expect(baru.roleId, roleIdLokalSebelum);
    // bcrypt menghasilkan salt acak tiap hashPin() dipanggil - tidak bisa
    // dibandingkan exact-match spt sha256 polos dulu, verifikasi lewat
    // verifyPin() (lihat pin_hash.dart).
    expect(verifyPin('1234', baru.pinHash), isTrue);
  });

  test('terapkanIdentitasBackend tanpa pin (mode Masuk) tidak mengubah PIN lokal', () async {
    final sebelum = await db.penggunaDao.cariById('pengguna-default');
    final pinHashSebelum = sebelum!.pinHash;

    await repo.terapkanIdentitasBackend(
      tokoIdLama: 'toko-default',
      tokoIdBaru: 'toko-asli-999',
      penggunaIdBaru: 'pengguna-asli-999',
      namaDariBackend: 'Rina',
    );

    final baru = await db.penggunaDao.cariById('pengguna-asli-999');
    expect(baru!.pinHash, pinHashSebelum);
  });

  // Tahap 5b (desain #3) - login PIN offline: benar/salah/terkunci/nonaktif.
  // PIN default seed (seed.dart) adalah '000000'.

  test('verifikasiPin - PIN benar menghasilkan berhasil', () async {
    final hasil = await repo.verifikasiPin('pengguna-default', '000000');
    expect(hasil, HasilVerifikasiPin.berhasil);
  });

  test('verifikasiPin - PIN salah menghasilkan pinSalah', () async {
    final hasil = await repo.verifikasiPin('pengguna-default', '999999');
    expect(hasil, HasilVerifikasiPin.pinSalah);
  });

  test('verifikasiPin - terkunci setelah 5x PIN salah berturut-turut, PIN benar pun ditolak', () async {
    for (var i = 0; i < kMaksPercobaanPinGagal - 1; i++) {
      final hasil = await repo.verifikasiPin('pengguna-default', '999999');
      expect(hasil, HasilVerifikasiPin.pinSalah);
    }
    // Percobaan ke-5 (gagal terakhir) memicu kunci.
    final hasilKunci = await repo.verifikasiPin('pengguna-default', '999999');
    expect(hasilKunci, HasilVerifikasiPin.terkunci);

    // Selama terkunci, PIN BENAR pun tetap ditolak (bukan cuma PIN salah).
    final hasilSetelahKunci = await repo.verifikasiPin('pengguna-default', '000000');
    expect(hasilSetelahKunci, HasilVerifikasiPin.terkunci);
  });

  test('verifikasiPin - percobaan gagal direset setelah PIN benar', () async {
    await repo.verifikasiPin('pengguna-default', '999999');
    await repo.verifikasiPin('pengguna-default', '999999');
    final hasilBenar = await repo.verifikasiPin('pengguna-default', '000000');
    expect(hasilBenar, HasilVerifikasiPin.berhasil);

    final pengguna = await db.penggunaDao.cariById('pengguna-default');
    expect(pengguna!.percobaanGagal, 0);
  });

  test('verifikasiPin - karyawan nonaktif (mis. hasil sync menandai nonaktif) tidak bisa login', () async {
    // Simulasikan hasil /sync/pull yang menandai karyawan ini nonaktif/
    // dihapus di server (desain #2 - server tetap mengirim baris nonaktif
    // supaya HP menolaknya, bukan membiarkan hash lama lolos selamanya).
    await db.penggunaDao.updatePengguna(
      'pengguna-default',
      const PenggunaCompanion(aktif: Value(false)),
    );

    final hasil = await repo.verifikasiPin('pengguna-default', '000000');
    expect(hasil, HasilVerifikasiPin.nonaktif);
  });

  test('verifikasiPin - id yang tidak dikenal menghasilkan tidakDitemukan', () async {
    final hasil = await repo.verifikasiPin('id-tidak-ada', '000000');
    expect(hasil, HasilVerifikasiPin.tidakDitemukan);
  });
}
