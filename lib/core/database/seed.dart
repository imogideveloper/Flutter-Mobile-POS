import 'package:drift/drift.dart';

import '../../features/order/data/local/tables/tipe_order_table.dart' show TipeOrderKanal;
import '../../features/transaksi/data/local/tables/metode_bayar_table.dart' show MetodeBayarTipe;
import '../auth/pin_hash.dart';
import '../utils/clock.dart';
import '../utils/id_generator.dart';
import 'app_database.dart';

const _izinBawaan = <(String kode, String modul, String deskripsi)>[
  ('transaksi.buat', 'penjualan', 'Membuat transaksi'),
  ('transaksi.diskon', 'penjualan', 'Memberi diskon manual'),
  ('transaksi.void', 'penjualan', 'Membatalkan transaksi'),
  ('transaksi.refund', 'penjualan', 'Melakukan refund'),
  ('transaksi.batal_pesanan', 'penjualan', 'Approval batalkan pesanan tersimpan'),
  ('shift.buka_tutup', 'penjualan', 'Membuka dan menutup shift'),
  ('kas.keluar_masuk', 'penjualan', 'Mencatat kas keluar/masuk'),
  ('produk.kelola', 'produk', 'Tambah/ubah/hapus produk'),
  ('stok.kelola', 'stok', 'Stok masuk, opname, transfer'),
  ('pembelian.kelola', 'stok', 'Mengelola pembelian supplier'),
  ('pelanggan.kelola', 'penjualan', 'Mengelola data pelanggan'),
  ('promo.kelola', 'penjualan', 'Mengelola promo dan pajak'),
  ('laporan.lihat', 'laporan', 'Melihat laporan'),
  ('pengguna.kelola', 'pengaturan', 'Mengelola karyawan dan role'),
  ('pengaturan.kelola', 'pengaturan', 'Mengubah pengaturan toko/outlet'),
];

const _izinKasir = {'transaksi.buat', 'shift.buka_tutup', 'kas.keluar_masuk', 'pelanggan.kelola'};
const _izinBukanManajer = {'pengguna.kelola', 'pengaturan.kelola'};

/// Tiruan dari seed role/izin/owner di schema_pos v2 (bagian seed data) -
/// dijalankan sekali di HP (bukan server) karena belum ada sync/login.
/// Pengguna Owner default di sini WAJIB diganti begitu modul login
/// sungguhan ada - PIN '000000' cuma supaya PIN-approval punya sesuatu
/// untuk divalidasi.
Future<void> seedRoleDanOwner(AppDatabase db) async {
  final sudahAda =
      await (db.select(db.role)..where((t) => t.isSystem.equals(true))).get();
  if (sudahAda.isNotEmpty) return;

  final now = nowEpochMs();
  const roleOwnerId = 'role-owner';
  const roleManajerId = 'role-manajer';
  const roleKasirId = 'role-kasir';

  await db.batch((batch) {
    batch.insertAll(db.role, [
      RoleCompanion.insert(
          id: roleOwnerId, nama: 'Owner', isSystem: const Value(true), createdAt: now, updatedAt: now),
      RoleCompanion.insert(
          id: roleManajerId, nama: 'Manajer', isSystem: const Value(true), createdAt: now, updatedAt: now),
      RoleCompanion.insert(
          id: roleKasirId, nama: 'Kasir', isSystem: const Value(true), createdAt: now, updatedAt: now),
    ]);
  });

  final izinIds = <String, String>{};
  await db.batch((batch) {
    for (final (kode, modul, deskripsi) in _izinBawaan) {
      final id = generateId();
      izinIds[kode] = id;
      batch.insert(
        db.izin,
        IzinCompanion.insert(
          id: id,
          kode: kode,
          modul: modul,
          deskripsi: Value(deskripsi),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  });

  await db.batch((batch) {
    for (final entry in izinIds.entries) {
      // Owner: semua izin.
      batch.insert(
        db.roleIzin,
        RoleIzinCompanion.insert(roleId: roleOwnerId, izinId: entry.value, createdAt: now),
      );
      // Manajer: semua kecuali kelola pengguna & pengaturan.
      if (!_izinBukanManajer.contains(entry.key)) {
        batch.insert(
          db.roleIzin,
          RoleIzinCompanion.insert(roleId: roleManajerId, izinId: entry.value, createdAt: now),
        );
      }
      // Kasir: hanya transaksi dasar.
      if (_izinKasir.contains(entry.key)) {
        batch.insert(
          db.roleIzin,
          RoleIzinCompanion.insert(roleId: roleKasirId, izinId: entry.value, createdAt: now),
        );
      }
    }
  });

  await db.into(db.pengguna).insert(PenggunaCompanion.insert(
        id: 'pengguna-default',
        tokoId: 'toko-default',
        roleId: roleOwnerId,
        nama: 'Owner (default)',
        pinHash: Value(hashPin('000000')),
        createdAt: now,
        updatedAt: now,
      ));
}

/// Tipe pesanan bawaan (Makan di tempat/Bawa pulang/Delivery) - dipilih di
/// header Keranjang, dibutuhkan terutama untuk usaha F&B. Owner bisa
/// menambah/menonaktifkan sendiri nanti lewat pengaturan.
Future<void> seedTipeOrderDefault(AppDatabase db) async {
  final sudahAda = await (db.select(db.tipeOrder)).get();
  if (sudahAda.isNotEmpty) return;

  final now = nowEpochMs();
  await db.batch((batch) {
    batch.insertAll(db.tipeOrder, [
      TipeOrderCompanion.insert(
        id: generateId(),
        tokoId: 'toko-default',
        nama: 'Makan di tempat',
        kanal: TipeOrderKanal.makanDiTempat,
        pakaiMeja: const Value(true),
        urutan: const Value(0),
        createdAt: now,
        updatedAt: now,
      ),
      TipeOrderCompanion.insert(
        id: generateId(),
        tokoId: 'toko-default',
        nama: 'Bawa pulang',
        kanal: TipeOrderKanal.bawaPulang,
        urutan: const Value(1),
        createdAt: now,
        updatedAt: now,
      ),
      TipeOrderCompanion.insert(
        id: generateId(),
        tokoId: 'toko-default',
        nama: 'Delivery',
        kanal: TipeOrderKanal.antar,
        urutan: const Value(2),
        createdAt: now,
        updatedAt: now,
      ),
    ]);
  });
}

/// Metode bayar dasar (F3.A) - device BARU (belum pernah sync) tetap butuh
/// metode bayar yang bisa dipilih di BayarPage sebelum sempat terhubung ke
/// backend sama sekali. Sama persis 4 baris + masuk_laci yang di-seed
/// server utk toko baru (lihat backend/app/routers/auth.py) - begitu
/// pairing+sync sukses, baris placeholder tokoId='toko-default' ini
/// dimigrasikan ke tokoId asli (lihat PairingDao.migrasikanTokoId), dan
/// pull berikutnya menimpa dgn id/nama asli dari server kalau beda.
Future<void> seedMetodeBayarDefault(AppDatabase db) async {
  final sudahAda = await (db.select(db.metodeBayar)).get();
  if (sudahAda.isNotEmpty) return;

  final now = nowEpochMs();
  await db.batch((batch) {
    batch.insertAll(db.metodeBayar, [
      MetodeBayarCompanion.insert(
        id: generateId(),
        tokoId: 'toko-default',
        nama: 'Tunai',
        tipe: MetodeBayarTipe.tunai,
        masukLaci: const Value(true),
        urutan: const Value(0),
        createdAt: now,
        updatedAt: now,
      ),
      MetodeBayarCompanion.insert(
        id: generateId(),
        tokoId: 'toko-default',
        nama: 'QRIS',
        tipe: MetodeBayarTipe.qris,
        butuhGateway: const Value(true),
        masukLaci: const Value(false),
        urutan: const Value(1),
        createdAt: now,
        updatedAt: now,
      ),
      MetodeBayarCompanion.insert(
        id: generateId(),
        tokoId: 'toko-default',
        nama: 'Kartu',
        tipe: MetodeBayarTipe.kartu,
        masukLaci: const Value(false),
        urutan: const Value(2),
        createdAt: now,
        updatedAt: now,
      ),
      MetodeBayarCompanion.insert(
        id: generateId(),
        tokoId: 'toko-default',
        nama: 'Transfer',
        tipe: MetodeBayarTipe.transfer,
        masukLaci: const Value(false),
        urutan: const Value(3),
        createdAt: now,
        updatedAt: now,
      ),
    ]);
  });
}
