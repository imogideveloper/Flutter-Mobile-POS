import 'dart:convert';

import 'package:apps_pos/core/struk/penyusun_label_produk.dart';
import 'package:apps_pos/core/struk/penyusun_tiket_dapur.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const epoch = 1768000000000;

  group('susunLabelProduk', () {
    test('satu stiker per porsi, urutan n/total berjalan lintas item', () {
      final labels = susunLabelProduk(
        items: const [
          ItemTiketDapur(namaProduk: 'Es Kopi Susu', qty: 2, tambahan: ['Less sugar']),
          ItemTiketDapur(namaProduk: 'Croissant', qty: 1),
        ],
        tanggalEpochMs: epoch,
        nomorAntrean: 'A-007',
        namaToko: 'Kopi Senja',
      );
      expect(labels.length, 3);
      expect(labels.map((l) => l.namaProduk), ['Es Kopi Susu', 'Es Kopi Susu', 'Croissant']);
      expect(labels.map((l) => '${l.urutan}/${l.total}'), ['1/3', '2/3', '3/3']);
      expect(labels.first.tambahan, ['Less sugar']);
      expect(labels.every((l) => l.nomorAntrean == 'A-007'), isTrue);
    });

    test('qty pecahan dibulatkan ke atas, qty nol tidak mencetak, batas per item', () {
      final labels = susunLabelProduk(
        items: const [
          ItemTiketDapur(namaProduk: 'Nasi', qty: 0.5),
          ItemTiketDapur(namaProduk: 'Kosong', qty: 0),
          ItemTiketDapur(namaProduk: 'Borongan', qty: 500),
        ],
        tanggalEpochMs: epoch,
      );
      expect(labels.where((l) => l.namaProduk == 'Nasi').length, 1);
      expect(labels.where((l) => l.namaProduk == 'Kosong'), isEmpty);
      expect(labels.where((l) => l.namaProduk == 'Borongan').length, batasLabelPerItem);
    });

    test('tanpa item tidak ada label', () {
      expect(susunLabelProduk(items: const [], tanggalEpochMs: epoch), isEmpty);
    });
  });

  group('barisTeksLabel', () {
    test('memuat nomor antrean, produk, tambahan, catatan, urutan, dan toko', () {
      final d = susunLabelProduk(
        items: const [
          ItemTiketDapur(namaProduk: 'Latte', qty: 1, tambahan: ['Oat milk'], catatan: 'Panas'),
        ],
        tanggalEpochMs: epoch,
        nomorAntrean: 'B-12',
        namaToko: 'Kopi Senja',
      ).single;
      final baris = barisTeksLabel(d);
      expect(baris.first, 'B-12');
      expect(baris, contains('Latte'));
      expect(baris, contains('+ Oat milk'));
      expect(baris, contains('* Panas'));
      expect(baris.any((b) => b.startsWith('1/1')), isTrue);
      expect(baris.last, 'Kopi Senja');
    });
  });

  group('susunTspl', () {
    LabelProdukData label({String nama = 'Es Kopi Susu', String? antrean = 'A-001', List<String> tambahan = const []}) =>
        LabelProdukData(
          namaProduk: nama,
          urutan: 2,
          total: 3,
          tanggalEpochMs: epoch,
          nomorAntrean: antrean,
          namaToko: 'Kopi Senja',
          tambahan: tambahan,
        );

    String tspl(LabelProdukData d, {int l = 40, int t = 30}) => ascii.decode(susunTspl(d, lebarMm: l, tinggiMm: t));

    test('perintah dasar TSPL: ukuran, gap, hapus, cetak satu salinan', () {
      final s = tspl(label());
      expect(s, startsWith('SIZE 40 mm,30 mm\r\n'));
      expect(s, contains('GAP 2 mm,0 mm\r\n'));
      expect(s, contains('CLS\r\n'));
      expect(s, endsWith('PRINT 1,1\r\n'));
      expect(s, contains('"A-001"'));
      expect(s, contains('"Es Kopi Susu"'));
      expect(s, contains('2/3'));
    });

    test('ukuran stiker mengikuti pilihan', () {
      expect(tspl(label(), l: 50, t: 40), startsWith('SIZE 50 mm,40 mm\r\n'));
    });

    test('tanda kutip dan karakter non-ASCII dibersihkan agar perintah tidak rusak', () {
      final s = tspl(label(nama: 'Kopi "Spesial" Café'));
      expect(s, isNot(contains('"Spesial"')));
      expect(s.codeUnits.every((c) => c < 128), isTrue);
    });

    test('baris yang tidak muat tinggi stiker dibuang, bukan melewati batas', () {
      final banyak = [for (var i = 0; i < 30; i++) 'Topping $i'];
      final s = tspl(label(tambahan: banyak));
      final ys = RegExp(r'TEXT \d+,(\d+),').allMatches(s).map((m) => int.parse(m.group(1)!));
      expect(ys.every((y) => y < 30 * 8), isTrue);
      expect(s, contains('"A-001"'), reason: 'nomor antrean tetap didahulukan');
      expect(s, contains('2/3'), reason: 'keterangan dasar tetap tercetak');
    });
  });
}
