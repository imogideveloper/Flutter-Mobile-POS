import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/features/dapur/data/antrean_repository.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart' show TransaksiStatus;
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nomor antrian offline (dokumen IMOGI no. 34): urut per hari, per outlet,
/// per perangkat, mulai lagi tiap hari, dan atomik dengan checkout.
void main() {
  late AppDatabase db;
  late AntreanRepository repo;
  final senin = DateTime(2026, 11, 9, 10);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AntreanRepository(db);
  });

  tearDown(() => db.close());

  test('format: awalan + tiga digit, tanpa awalan hanya angka, lewat 999 terus bertambah', () {
    expect(AntreanRepository.format('A', 1), 'A-001');
    expect(AntreanRepository.format('A', 12), 'A-012');
    expect(AntreanRepository.format('', 7), '007');
    expect(AntreanRepository.format('B', 1000), 'B-1000');
  });

  test('nomor naik satu per transaksi dalam hari yang sama', () async {
    final a = await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin);
    final b = await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin.add(const Duration(hours: 2)));
    final c = await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin.add(const Duration(hours: 5)));
    expect([a, b, c], ['A-001', 'A-002', 'A-003']);
  });

  test('nomor mulai lagi dari awal saat hari berganti', () async {
    await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin);
    await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin);
    final besok = await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin.add(const Duration(days: 1)));
    expect(besok, 'A-001');
  });

  test('outlet dan perangkat berbeda punya hitungan sendiri', () async {
    await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin);
    await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin);
    expect(await repo.nomorBerikutnya(outletId: 'o2', perangkatId: 'p1', waktu: senin), 'A-001');
    expect(await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p2', waktu: senin), 'A-001');
    expect(await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin), 'A-003');
  });

  test('awalan dan angka awal dapat diatur', () async {
    final n = await repo.nomorBerikutnya(
      outletId: 'o1',
      perangkatId: 'p1',
      waktu: senin,
      awalan: 'KP',
      mulaiDari: 100,
    );
    expect(n, 'KP-100');
    expect(
      await repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin, awalan: 'KP', mulaiDari: 100),
      'KP-101',
    );
  });

  group('checkout', () {
    late TransaksiRepository transaksiRepo;
    const items = [
      ItemKeranjang(produkId: 'p-1', namaProduk: 'Kopi Susu', hargaSatuan: 18000, qty: 2, lacakStok: false),
    ];

    k.HasilKalkulasi hitung() => k.hitung(
          k.TransaksiInput(items: [
            k.ItemInput(produkId: 'p-1', varianId: null, namaProduk: 'Kopi Susu', qty: 2, hargaJual: 18000),
          ]),
        );

    Future<dynamic> bayar({Future<String?> Function()? buatNomor}) => transaksiRepo.checkout(
          tokoId: 't1',
          outletId: 'o1',
          shiftId: 's1',
          penggunaId: 'u1',
          metodeBayarId: 'm1',
          items: items,
          hasil: hitung(),
          totalBayar: 36000,
          buatNomorAntrean: buatNomor,
        );

    setUp(() {
      transaksiRepo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
    });

    test('checkout menyimpan nomor antrian di transaksi dan di hasil', () async {
      final hasil = await bayar(
        buatNomor: () => repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin),
      );
      expect(hasil.nomorAntrean, 'A-001');
      final row = await (db.select(db.transaksi)..where((t) => t.id.equals(hasil.id as String))).getSingle();
      expect(row.nomorAntrean, 'A-001');
      expect(row.status, TransaksiStatus.selesai);
    });

    test('tanpa pembuat nomor (antrian mati) nomor tetap kosong', () async {
      final hasil = await bayar();
      expect(hasil.nomorAntrean, isNull);
      final row = await (db.select(db.transaksi)..where((t) => t.id.equals(hasil.id as String))).getSingle();
      expect(row.nomorAntrean, isNull);
    });

    test('dua checkout berurutan mendapat nomor berurutan', () async {
      Future<String?> buat() => repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin);
      final h1 = await bayar(buatNomor: buat);
      final h2 = await bayar(buatNomor: buat);
      expect([h1.nomorAntrean, h2.nomorAntrean], ['A-001', 'A-002']);
    });

    test('checkout gagal membatalkan nomor (tidak ada lubang nomor)', () async {
      // Pembuat nomor berhasil lalu checkout dipaksa gagal: transaction digulung,
      // sehingga nomor yang baru dibuat ikut dibatalkan.
      Future<String?> buat() => repo.nomorBerikutnya(outletId: 'o1', perangkatId: 'p1', waktu: senin);
      await expectLater(
        transaksiRepo.checkout(
          tokoId: 't1',
          outletId: 'o1',
          shiftId: 's1',
          penggunaId: 'u1',
          metodeBayarId: 'm1',
          items: items,
          // hasil sengaja tidak cocok dengan items agar simpanTransaksiLengkap gagal
          hasil: k.hitung(k.TransaksiInput(items: const [])),
          totalBayar: 36000,
          buatNomorAntrean: buat,
        ),
        throwsA(anything),
      );
      expect(await buat(), 'A-001', reason: 'nomor yang dibuat checkout gagal harus ikut digulung');
    });
  });
}
