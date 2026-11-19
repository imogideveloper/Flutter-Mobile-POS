import 'package:apps_pos/features/laporan/data/laporan_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tren penjualan (IMOGI no. 65): total per tanggal lokal, hari kosong bernilai 0.
void main() {
  int ms(int tgl, int jam) => DateTime.utc(2026, 11, tgl, jam).millisecondsSinceEpoch;

  test('menjumlah per tanggal dan mengisi hari tanpa transaksi dengan 0', () {
    final hasil = susunPenjualanHarian(
      [(ms(10, 9), 10000), (ms(10, 20), 5000), (ms(12, 13), 7000)],
      ms(10, 0),
      ms(13, 0),
    );
    expect(hasil.map((d) => d.tanggal.day), [10, 11, 12]);
    expect(hasil.map((d) => d.total), [15000, 0, 7000]);
  });

  test('periode satu hari menghasilkan satu titik', () {
    final hasil = susunPenjualanHarian([(ms(10, 9), 3000)], ms(10, 0), ms(11, 0));
    expect(hasil, hasLength(1));
    expect(hasil.single.total, 3000);
  });

  test('dibatasi 92 hari', () {
    final hasil = susunPenjualanHarian(const [], DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
        DateTime.utc(2026, 12, 31).millisecondsSinceEpoch);
    expect(hasil, hasLength(92));
  });
}
