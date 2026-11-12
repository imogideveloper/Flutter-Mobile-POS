import 'package:apps_pos/features/pelanggan/domain/pelanggan_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseTanggalLahir', () {
    test('format yang dikenali', () {
      expect(parseTanggalLahir('1995-04-12'), '1995-04-12');
      expect(parseTanggalLahir('12/04/1995'), '1995-04-12');
      expect(parseTanggalLahir('2-4-1995'), '1995-04-02');
      expect(parseTanggalLahir('12.04.1995'), '1995-04-12');
    });

    test('tidak terbaca, tanggal fiktif, dan tahun tak masuk akal ditolak', () {
      expect(parseTanggalLahir('abc'), isNull);
      expect(parseTanggalLahir('31/02/1995'), isNull);
      expect(parseTanggalLahir('1895-01-01'), isNull);
      expect(parseTanggalLahir('2999-01-01'), isNull);
      expect(parseTanggalLahir('12/04/95'), isNull);
    });
  });

  group('normalisasiHp', () {
    test('angka 0 yang hilang di Excel dipulihkan, awalan 0 dan 62 dibiarkan', () {
      expect(normalisasiHp('81234567890'), '081234567890');
      expect(normalisasiHp('081234567890'), '081234567890');
      expect(normalisasiHp('+62 812-3456-7890'), '6281234567890');
      expect(normalisasiHp('(0812) 345 6789'), '08123456789');
      expect(normalisasiHp('123'), '123', reason: 'terlalu pendek: biarkan, server yang menolak');
    });
  });

  group('bacaCsvPelanggan', () {
    test('template aplikasi terbaca utuh', () {
      final h = bacaCsvPelanggan(templatePelangganCsv());
      expect(h.galat, isNull);
      expect(h.siap.length, 2);
      final sari = h.baris.first;
      expect(sari.nama, 'Sari Contoh');
      expect(sari.noHp, '081200000001');
      expect(sari.tanggalLahir, '1995-04-12');
      expect(sari.catatan, 'Suka kopi hitam');
      expect(h.baris.last.email, isNull);
    });

    test('pemisah titik koma, alias judul, dan kolom hp yang kehilangan angka 0', () {
      const csv = 'Nama Pelanggan;Nomor HP;Tgl Lahir\nAni;81234567890;12/04/1995\n';
      final h = bacaCsvPelanggan(csv);
      expect(h.galat, isNull);
      expect(h.baris.single.noHp, '081234567890');
      expect(h.baris.single.tanggalLahir, '1995-04-12');
    });

    test('baris bermasalah ditandai, baris lain tetap siap', () {
      const csv = 'nama,no_hp,tanggal_lahir\nBagus,081200000001,\n,081200000002,\nRusak,081200000003,kemarin\n';
      final h = bacaCsvPelanggan(csv);
      expect(h.siap.map((b) => b.nama), ['Bagus']);
      expect(h.bermasalah.map((b) => b.nomorBaris), [3, 4]);
      expect(h.baris[1].masalah, contains('Nama pelanggan kosong'));
      expect(h.baris[2].masalah, contains('Tanggal lahir'));
    });

    test('kolom nama tidak ada, berkas kosong, dan terlalu banyak baris ditolak seluruhnya', () {
      expect(bacaCsvPelanggan('no_hp\n0812\n').galat, contains('nama'));
      expect(bacaCsvPelanggan('').galat, 'Berkas kosong');
      final besar = StringBuffer('nama\n');
      for (var i = 0; i <= maksBarisImporPelanggan; i++) {
        besar.writeln('P$i');
      }
      expect(bacaCsvPelanggan(besar.toString()).galat, contains('Maksimal'));
    });

    test('keJson hanya memuat isian yang ada', () {
      final b = bacaCsvPelanggan('nama,email\nAni,ani@x.id\n').baris.single;
      expect(b.keJson(), {'nama': 'Ani', 'email': 'ani@x.id'});
    });
  });
}
