import 'package:apps_pos/features/transaksi/domain/saran_uang_diterima.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('total 18.711 (kasus HP): uang pas lalu lembar 50.000 dan 100.000, bukan 43.711', () {
    expect(saranUangDiterima(18711), [18711, 50000, 100000]);
  });

  test('total tepat 50.000: duplikat dibuang', () {
    expect(saranUangDiterima(50000), [50000, 100000]);
  });

  test('total 20.790 dan 120.000', () {
    expect(saranUangDiterima(20790), [20790, 50000, 100000]);
    expect(saranUangDiterima(120000), [120000, 150000, 200000]);
  });

  test('total nol atau negatif tidak punya saran', () {
    expect(saranUangDiterima(0), isEmpty);
    expect(saranUangDiterima(-5), isEmpty);
  });

  test('tidak ada saran di bawah total', () {
    for (final total in [1, 49999, 50001, 99999, 100001, 1234567]) {
      expect(saranUangDiterima(total).every((n) => n >= total), isTrue, reason: '$total');
    }
  });
}
