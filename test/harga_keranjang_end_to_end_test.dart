/// Tahap 3a lanjutan - untuk 5 skenario (grosir, member, service per
/// tipe pesanan, pajak per produk, pembulatan 500): total "di keranjang"
/// (hasil k.hitung() - mesin yang SAMA dipakai hasilHargaKeranjangProvider,
/// lihat lib/features/transaksi/presentation/providers/harga_keranjang_provider.dart)
/// HARUS SAMA dengan total yang tersimpan di drift (TransaksiRepository.
/// checkout) HARUS SAMA dengan total di struk (HasilTransaksi.total) -
/// satu mesin hitung tunggal (tahap 3a bagian A), bukan tiga jalur hitung
/// yang kebetulan cocok.
///
/// Catatan: skenario ini dibangun lewat k.hitung() langsung (bukan lewat
/// ProviderContainer+StreamProvider hidup) krn kombinasi itu terbukti
/// macet (>30s, tidak pernah selesai) di lingkungan tes plain `test()`
/// tanpa widget pump - beda dgn testWidgets() yg sudah dipakai di tempat
/// lain utk StreamProvider serupa (fitur_terkunci_widget_test.dart).
/// Dilaporkan sbg temuan, bukan didiamkan - lihat laporan tahap 3a.
/// Kesetaraan "keranjang" di sini tetap sah krn hasilHargaKeranjangProvider
/// HANYA membungkus k.hitung() dgn input yg dibaca dari baris drift yang
/// SAMA - lihat providernya langsung utk konstruksi ItemInput/PromoInput/
/// dkk yang dicerminkan persis di helper tes ini.
library;

import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart';
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart'
    show TransaksiStatus;
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:apps_pos/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _verifikasiKeranjangDriftStrukSama(
  AppDatabase db,
  List<ItemKeranjang> items,
  k.HasilKalkulasi hasilKeranjang, {
  int poinDitukar = 0,
  int diskonPoin = 0,
}) async {
  final repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
  // Modul 10 (tukar poin) - diskonPoin DIPOTONG DARI hasilKeranjang.total
  // SETELAH pajak (lihat docstring checkout()), bukan ikut masuk hitungan
  // k.hitung() di atas - totalAkhir di sini mencerminkan itu.
  final totalAkhir = hasilKeranjang.total - diskonPoin;
  final hasilStruk = await repo.checkout(
    tokoId: 't1',
    outletId: 'o1',
    shiftId: 'shift-1',
    penggunaId: 'pengguna-1',
    metodeBayarId: 'metode-1',
    items: items,
    hasil: hasilKeranjang,
    totalBayar: totalAkhir,
    poinDitukar: poinDitukar,
    diskonPoin: diskonPoin,
  );

  final transaksiRow = await (db.select(
    db.transaksi,
  )..where((t) => t.id.equals(hasilStruk.id))).getSingle();

  expect(
    transaksiRow.total,
    totalAkhir,
    reason: 'total tersimpan di drift harus sama dgn total keranjang - diskonPoin',
  );
  expect(transaksiRow.status, TransaksiStatus.selesai);
  expect(
    hasilStruk.total,
    totalAkhir,
    reason: 'total di struk harus sama dgn total keranjang - diskonPoin',
  );
  if (diskonPoin > 0) {
    expect(transaksiRow.poinDitukar, poinDitukar);
    expect(transaksiRow.diskonPoin, diskonPoin);
    expect(
      transaksiRow.totalDiskon,
      hasilKeranjang.totalDiskon + diskonPoin,
      reason: 'totalDiskon tersimpan harus ikut termasuk diskonPoin',
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.produkDao.upsertProduk(
      ProdukCompanion.insert(
        id: 'p1',
        tokoId: 't1',
        nama: 'Produk',
        tipe: ProdukTipe.barang,
        lacakStok: const Value(false),
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  });

  tearDown(() => db.close());

  test(
    'skenario grosir: tier qty>=10 dipakai, keranjang=drift=struk',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Beras',
          hargaSatuan: 10000,
          qty: 10,
          lacakStok: false,
        ),
      ];
      final hasil = k.hitung(
        k.TransaksiInput(
          items: [
            k.ItemInput(
              produkId: 'p1',
              varianId: null,
              namaProduk: 'Beras',
              qty: 10,
              hargaJual: 10000,
              hargaGrosirTiers: const [
                k.HargaGrosirTier(minQty: 10, harga: 9000),
              ],
            ),
          ],
          fiturAktif: const {'harga_grosir'},
        ),
      );

      expect(hasil.subtotal, 90000);
      expect(hasil.total, 90000);
      await _verifikasiKeranjangDriftStrukSama(db, items, hasil);
    },
  );

  test(
    'skenario member: diskon_persen level diterapkan, keranjang=drift=struk',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Paket Hemat',
          hargaSatuan: 50000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      final hasil = k.hitung(
        k.TransaksiInput(
          items: [
            k.ItemInput(
              produkId: 'p1',
              varianId: null,
              namaProduk: 'Paket Hemat',
              qty: 1,
              hargaJual: 50000,
            ),
          ],
          fiturAktif: const {'diskon_member'},
          diskonMemberPersen: 20,
        ),
      );

      expect(hasil.subtotal, 50000);
      expect(hasil.diskonMember, 10000);
      expect(hasil.total, 40000);
      await _verifikasiKeranjangDriftStrukSama(db, items, hasil);
    },
  );

  test(
    'skenario service per tipe pesanan: hanya service tertaut dipakai, keranjang=drift=struk',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Paket Makan',
          hargaSatuan: 100000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      final hasil = k.hitung(
        k.TransaksiInput(
          items: [
            k.ItemInput(
              produkId: 'p1',
              varianId: null,
              namaProduk: 'Paket Makan',
              qty: 1,
              hargaJual: 100000,
            ),
          ],
          fiturAktif: const {'service_per_tipe_order'},
          tipeOrder: const k.TipeOrderInput(
            id: 'to-1',
            pajakIds: {'svc-tertaut'},
          ),
          serviceDefault: const [
            k.PajakInput(
              id: 'svc-tertaut',
              nama: 'Service',
              persen: 5,
              termasukHarga: false,
              urutan: 1,
            ),
            k.PajakInput(
              id: 'svc-tidak-tertaut',
              nama: 'Service Lain',
              persen: 3,
              termasukHarga: false,
              urutan: 1,
            ),
          ],
        ),
      );

      expect(hasil.subtotal, 100000);
      expect(hasil.service, 5000);
      expect(hasil.total, 105000);
      await _verifikasiKeranjangDriftStrukSama(db, items, hasil);
    },
  );

  test(
    'skenario pajak per produk: override produk dipakai, sisanya pajak default, keranjang=drift=struk',
    () async {
      await db.produkDao.upsertProduk(
        ProdukCompanion.insert(
          id: 'p2',
          tokoId: 't1',
          nama: 'Produk Biasa',
          tipe: ProdukTipe.barang,
          lacakStok: const Value(false),
          createdAt: 0,
          updatedAt: 0,
        ),
      );
      final items = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Produk Khusus',
          hargaSatuan: 60000,
          qty: 1,
          lacakStok: false,
        ),
        ItemKeranjang(
          produkId: 'p2',
          namaProduk: 'Produk Biasa',
          hargaSatuan: 40000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      final hasil = k.hitung(
        k.TransaksiInput(
          items: [
            k.ItemInput(
              produkId: 'p1',
              varianId: null,
              namaProduk: 'Produk Khusus',
              qty: 1,
              hargaJual: 60000,
              pajakProduk: const [
                k.PajakInput(
                  id: 'pb1',
                  nama: 'PB1',
                  persen: 5,
                  termasukHarga: false,
                  urutan: 1,
                ),
              ],
            ),
            k.ItemInput(
              produkId: 'p2',
              varianId: null,
              namaProduk: 'Produk Biasa',
              qty: 1,
              hargaJual: 40000,
            ),
          ],
          fiturAktif: const {'pajak_per_produk'},
          pajakDefault: const [
            k.PajakInput(
              id: 'ppn',
              nama: 'PPN',
              persen: 10,
              termasukHarga: false,
              urutan: 1,
            ),
          ],
        ),
      );

      expect(hasil.subtotal, 100000);
      // p1 (60% porsi) pakai PB1 5% = 3000; p2 (sisa) pakai PPN 10% = 4000.
      expect(hasil.pajak, 7000);
      expect(hasil.total, 107000);
      await _verifikasiKeranjangDriftStrukSama(db, items, hasil);
    },
  );

  test(
    'skenario pembulatan 500: total dibulatkan ke kelipatan terdekat, keranjang=drift=struk',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Barang',
          hargaSatuan: 10250,
          qty: 1,
          lacakStok: false,
        ),
      ];
      final hasil = k.hitung(
        k.TransaksiInput(
          items: [
            k.ItemInput(
              produkId: 'p1',
              varianId: null,
              namaProduk: 'Barang',
              qty: 1,
              hargaJual: 10250,
            ),
          ],
          pembulatan: 500,
        ),
      );

      expect(hasil.totalSebelumPembulatan, 10250);
      expect(hasil.pembulatan, 250);
      expect(hasil.total, 10500);
      await _verifikasiKeranjangDriftStrukSama(db, items, hasil);
    },
  );

  test(
    'skenario tukar poin: diskonPoin dipotong dari total SETELAH pajak, keranjang=drift=struk',
    () async {
      final items = const [
        ItemKeranjang(
          produkId: 'p1',
          namaProduk: 'Kopi Susu',
          hargaSatuan: 20000,
          qty: 1,
          lacakStok: false,
        ),
      ];
      final hasil = k.hitung(
        k.TransaksiInput(
          items: [
            k.ItemInput(
              produkId: 'p1',
              varianId: null,
              namaProduk: 'Kopi Susu',
              qty: 1,
              hargaJual: 20000,
            ),
          ],
        ),
      );

      expect(hasil.total, 20000);
      // 15 poin x Rp100 = Rp1.500 diskon.
      await _verifikasiKeranjangDriftStrukSama(db, items, hasil, poinDitukar: 15, diskonPoin: 1500);
    },
  );
}
