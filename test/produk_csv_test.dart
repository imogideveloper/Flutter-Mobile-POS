import 'package:apps_pos/features/produk/domain/produk_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRupiahCsv', () {
    test('format umum', () {
      expect(parseRupiahCsv('15000'), 15000);
      expect(parseRupiahCsv('15.000'), 15000);
      expect(parseRupiahCsv('Rp 15.000'), 15000);
      expect(parseRupiahCsv('Rp. 1.250.000'), 1250000);
      expect(parseRupiahCsv('15,5'), 16); // koma desimal dibulatkan
      expect(parseRupiahCsv('15,000'), 15000); // ribuan gaya Inggris
      expect(parseRupiahCsv('15000.50'), 15001);
      expect(parseRupiahCsv(''), 0);
      expect(parseRupiahCsv(null), 0);
      expect(parseRupiahCsv('-500'), -500);
    });

    test('tidak terbaca menghasilkan null', () {
      expect(parseRupiahCsv('abc'), isNull);
      expect(parseRupiahCsv('12x3'), isNull);
    });
  });

  group('bacaCsvProduk', () {
    test('template aplikasi terbaca utuh', () {
      final h = bacaCsvProduk(templateCsv());
      expect(h.galat, isNull);
      expect(h.baris.length, 2);
      expect(h.siap.length, 2);
      expect(h.baris.first.nama, 'Kopi Susu');
      expect(h.baris.first.kategori, 'Minuman');
      expect(h.baris.first.hargaJual, 18000);
      expect(h.baris.first.hpp, 7000);
      expect(h.baris.first.sku, 'KS-001');
      expect(h.baris.first.barcode, isNull);
      expect(h.baris.first.nomorBaris, 2);
    });

    test('pemisah titik koma (Excel Indonesia), BOM, CRLF, dan alias judul', () {
      const csv = '﻿Nama Produk;Harga;Modal;Kategori\r\nTeh Tarik;12.000;4.500;Minuman\r\n';
      final h = bacaCsvProduk(csv);
      expect(h.galat, isNull);
      expect(h.baris.single.nama, 'Teh Tarik');
      expect(h.baris.single.hargaJual, 12000);
      expect(h.baris.single.hpp, 4500);
    });

    test('sel bertanda petik memuat koma, petik, dan baris baru', () {
      const csv = 'nama,deskripsi,harga_jual\n"Nasi, Ayam","Pedas ""level 3""\nbaris dua",20000\n';
      final h = bacaCsvProduk(csv);
      expect(h.baris.single.nama, 'Nasi, Ayam');
      expect(h.baris.single.deskripsi, 'Pedas "level 3"\nbaris dua');
      expect(h.baris.single.hargaJual, 20000);
    });

    test('baris bermasalah ditandai dengan alasan, baris lain tetap siap', () {
      const csv = 'nama,harga_jual,hpp\nBagus,10000,4000\n,5000,1000\nRusak,abc,0\nMinus,-5,0\n\nOke Lagi,7000,\n';
      final h = bacaCsvProduk(csv);
      expect(h.baris.length, 5, reason: 'baris kosong dilewati');
      expect(h.siap.map((b) => b.nama), ['Bagus', 'Oke Lagi']);
      expect(h.bermasalah.map((b) => b.nomorBaris), [3, 4, 5]);
      expect(h.baris[1].masalah, contains('Nama produk kosong'));
      expect(h.baris[2].masalah, contains('tidak dapat dibaca'));
      expect(h.baris[3].masalah, contains('negatif'));
    });

    test('kolom nama tidak ada, berkas kosong, dan terlalu banyak baris ditolak seluruhnya', () {
      expect(bacaCsvProduk('harga,hpp\n1,2\n').galat, contains('nama'));
      expect(bacaCsvProduk('').galat, 'Berkas kosong');
      expect(bacaCsvProduk('\n\n').galat, 'Berkas kosong');
      final besar = StringBuffer('nama\n');
      for (var i = 0; i <= maksBarisImpor; i++) {
        besar.writeln('P$i');
      }
      expect(bacaCsvProduk(besar.toString()).galat, contains('Maksimal'));
    });

    test('keJson hanya memuat isian yang ada', () {
      final b = bacaCsvProduk('nama,harga_jual\nKopi,9000\n').baris.single;
      expect(b.keJson(), {'nama': 'Kopi', 'harga_jual': 9000, 'hpp': 0});
    });
  });

  group('eksporProdukCsv', () {
    test('ekspor lalu baca kembali memberi data yang sama', () {
      final csv = eksporProdukCsv(const [
        BarisEkspor(nama: 'Nasi, Ayam', kategori: 'Makanan', hargaJual: 20000, hpp: 8000, sku: 'NA-1', deskripsi: 'Pedas "level 3"'),
        BarisEkspor(nama: 'Air', hargaJual: 3000, hpp: 1000),
      ]);
      expect(csv.startsWith('﻿'), isTrue);
      final h = bacaCsvProduk(csv);
      expect(h.galat, isNull);
      expect(h.baris.map((b) => b.nama), ['Nasi, Ayam', 'Air']);
      expect(h.baris.first.deskripsi, 'Pedas "level 3"');
      expect(h.baris.first.hargaJual, 20000);
      expect(h.baris.last.kategori, isNull);
    });

    test('sel berawalan rumus diberi apostrof agar tidak dieksekusi Excel', () {
      final csv = eksporProdukCsv(const [BarisEkspor(nama: '=HYPERLINK("x")', hargaJual: 1, hpp: 0)]);
      expect(csv, contains('"\'=HYPERLINK(""x"")"'));
      final csv2 = eksporProdukCsv(const [BarisEkspor(nama: '+62 Cafe', hargaJual: 1, hpp: 0)]);
      expect(csv2, contains("'+62 Cafe"));
    });
  });
}
