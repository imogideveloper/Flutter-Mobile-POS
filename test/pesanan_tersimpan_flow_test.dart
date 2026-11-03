import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart'
    hide Produk;
import 'package:apps_pos/features/stok/data/local/tables/mutasi_stok_table.dart'
    show MutasiJenis;
import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart';
import 'package:apps_pos/features/transaksi/data/transaksi_repository.dart';
import 'package:apps_pos/features/transaksi/domain/item_keranjang.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// F3.E - "Simpan pesanan" (open bill) di level UI (tap tombol, snackbar,
/// badge, navigasi) sudah dites widget-level di keranjang_page.dart/
/// kasir_page.dart secara terpisah (lihat navigasi_smoke_test.dart utk
/// bukti bottom-nav+kasir tidak error). Tes INI fokus ke alur
/// bisnisnya murni lewat TransaksiRepository langsung (simpan -> buka
/// lagi -> tambah item -> bayar -> draft hilang & stok terpotong) -
/// LEBIH STABIL drpd drive navigasi 3-halaman bersarang
/// (Kasir->PesananTersimpanList->Keranjang->Bayar) yang rapuh di widget
/// test (replikasi pola "satu mesin hitung yang sama" dari
/// transaksi_repository_test.dart, bukan testWidgets).
k.HasilKalkulasi _hitung(List<ItemKeranjang> items) {
  return k.hitung(
    k.TransaksiInput(
      items: [
        for (final item in items)
          k.ItemInput(
            produkId: item.produkId,
            varianId: null,
            namaProduk: item.namaProduk,
            qty: item.qty,
            hargaJual: item.hargaSatuan,
          ),
      ],
    ),
  );
}

void main() {
  late AppDatabase db;
  late TransaksiRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TransaksiRepository(db.transaksiDao, db.stokDao, db.produkDao);
  });

  tearDown(() => db.close());

  test('simpan pesanan -> tidak potong stok -> muncul di daftar draft', () async {
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 't1',
      nama: 'Kopi Hitam',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(15000),
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.stokDao.catatMutasi(
      tokoId: 't1',
      outletId: 'o1',
      produkId: 'p1',
      jenis: MutasiJenis.stokAwal,
      qty: 10,
    );

    const items = [
      ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi Hitam', hargaSatuan: 15000, qty: 2, lacakStok: true),
    ];
    final draftId = await repo.simpanPesanan(
      tokoId: 't1',
      outletId: 'o1',
      penggunaId: 'u1',
      items: items,
      hasil: _hitung(items),
    );

    final stok = await (db.select(db.stok)
          ..where((t) => t.outletId.equals('o1') & t.produkId.equals('p1')))
        .getSingle();
    expect(stok.jumlah, 10, reason: 'pesanan tersimpan tidak boleh memotong stok');

    final draftRows = await db.transaksiDao.watchPesananTersimpan('o1').first;
    expect(draftRows, hasLength(1));
    expect(draftRows.single.id, draftId);
    expect(draftRows.single.status, TransaksiStatus.tersimpan);
    expect(draftRows.single.total, 30000);
    expect(draftRows.single.nomorStruk, startsWith('DRAFT'));
  });

  test('buka lagi draft -> tambah item -> bayar -> draft hilang & stok terpotong', () async {
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 't1',
      nama: 'Kopi Hitam',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(15000),
      createdAt: 0,
      updatedAt: 0,
    ));
    await db.stokDao.catatMutasi(
      tokoId: 't1',
      outletId: 'o1',
      produkId: 'p1',
      jenis: MutasiJenis.stokAwal,
      qty: 10,
    );

    const itemAwal = [
      ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi Hitam', hargaSatuan: 15000, qty: 1, lacakStok: true),
    ];
    final draftId = await repo.simpanPesanan(
      tokoId: 't1',
      outletId: 'o1',
      penggunaId: 'u1',
      items: itemAwal,
      hasil: _hitung(itemAwal),
    );

    // "Buka lagi" - rekonstruksi item dari draft (F3.E.3).
    final itemDibuka = await repo.itemUntukResumePesanan(draftId);
    expect(itemDibuka, hasLength(1));
    expect(itemDibuka.single.namaProduk, 'Kopi Hitam');

    // "Tambah item" - kasir nambah 1 lagi sebelum bayar (qty jadi 2).
    final itemFinal = [itemDibuka.single.copyWith(qty: 2)];

    // "Bayar" - checkout() biasa, menggantikan draft lama (F3.E.2).
    final hasil = await repo.checkout(
      tokoId: 't1',
      outletId: 'o1',
      shiftId: 'shift1',
      penggunaId: 'u1',
      metodeBayarId: 'metode-tunai-default',
      items: itemFinal,
      hasil: _hitung(itemFinal),
      totalBayar: 30000,
      gantikanPesananTersimpanId: draftId,
    );

    expect(hasil.total, 30000);

    // Draft lama sudah hilang, digantikan transaksi final.
    final semuaTransaksi = await db.select(db.transaksi).get();
    expect(semuaTransaksi, hasLength(1));
    expect(semuaTransaksi.single.id, hasil.id);
    expect(semuaTransaksi.single.id, isNot(draftId));
    expect(semuaTransaksi.single.status, TransaksiStatus.selesai);

    final draftRows = await db.transaksiDao.watchPesananTersimpan('o1').first;
    expect(draftRows, isEmpty);

    final stok = await (db.select(db.stok)
          ..where((t) => t.outletId.equals('o1') & t.produkId.equals('p1')))
        .getSingle();
    expect(stok.jumlah, 10 - 2, reason: 'stok BARU terpotong setelah benar2 dibayar');
  });

  test('batalkan pesanan tersimpan - hilang dari daftar, tidak pernah potong stok', () async {
    await db.produkDao.upsertProduk(ProdukCompanion.insert(
      id: 'p1',
      tokoId: 't1',
      nama: 'Kopi Hitam',
      tipe: ProdukTipe.barang,
      hargaJual: const Value(15000),
      createdAt: 0,
      updatedAt: 0,
    ));

    const items = [
      ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi Hitam', hargaSatuan: 15000, qty: 1, lacakStok: true),
    ];
    final draftId = await repo.simpanPesanan(
      tokoId: 't1',
      outletId: 'o1',
      penggunaId: 'u1',
      items: items,
      hasil: _hitung(items),
    );

    await repo.batalkanPesanan(draftId, 'Pelanggan batal');

    final draftRows = await db.transaksiDao.watchPesananTersimpan('o1').first;
    expect(draftRows, isEmpty);
    final semuaTransaksi = await db.select(db.transaksi).get();
    expect(semuaTransaksi, isEmpty);
  });

  test(
    'temuan#2 - batalkan pesanan mencatat alasan ke antrean pesanan_batal (belum sync) utk dikirim server',
    () async {
      await db.produkDao.upsertProduk(ProdukCompanion.insert(
        id: 'p1',
        tokoId: 't1',
        nama: 'Kopi Hitam',
        tipe: ProdukTipe.barang,
        hargaJual: const Value(15000),
        createdAt: 0,
        updatedAt: 0,
      ));

      const items = [
        ItemKeranjang(produkId: 'p1', namaProduk: 'Kopi Hitam', hargaSatuan: 15000, qty: 2, lacakStok: true),
      ];
      final draftId = await repo.simpanPesanan(
        tokoId: 't1',
        outletId: 'o1',
        penggunaId: 'u1',
        items: items,
        hasil: _hitung(items),
      );

      final idAntrean = await repo.batalkanPesanan(
        draftId,
        'Pelanggan berubah pikiran',
        disetujuiOleh: 'owner-1',
      );
      expect(idAntrean, draftId);

      final antrean = await db.transaksiDao.pembatalanPesananBelumSync();
      expect(antrean, hasLength(1));
      expect(antrean.single.alasan, 'Pelanggan berubah pikiran');
      expect(antrean.single.disetujuiOleh, 'owner-1');
      expect(antrean.single.total, 30000);
      expect(antrean.single.isiPesanan, contains('Kopi Hitam'));

      await repo.tandaiPembatalanPesananSudahSync(idAntrean);
      final sisaAntrean = await db.transaksiDao.pembatalanPesananBelumSync();
      expect(sisaAntrean, isEmpty, reason: 'sudah ditandai sync, tidak boleh dikirim ulang');
    },
  );
}
