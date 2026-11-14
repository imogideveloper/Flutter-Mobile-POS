import 'package:flutter_test/flutter_test.dart';
import 'package:apps_pos/features/pelanggan/domain/batas_kasbon.dart';

void main() {
  test('tanpa batas selalu boleh', () {
    final h = cekBatasKasbon(batas: null, utangSekarang: 900000, sisaTagihanBaru: 500000);
    expect(h.boleh, isTrue);
    expect(h.sisaKuota, isNull);
  });

  test('pas di batas masih boleh', () {
    final h = cekBatasKasbon(batas: 100000, utangSekarang: 60000, sisaTagihanBaru: 40000);
    expect(h.boleh, isTrue);
    expect(h.sisaKuota, 40000);
  });

  test('melebihi batas ditahan dan kuota dilaporkan', () {
    final h = cekBatasKasbon(batas: 100000, utangSekarang: 60000, sisaTagihanBaru: 40001);
    expect(h.boleh, isFalse);
    expect(h.sisaKuota, 40000);
  });

  test('utang sudah melebihi batas: kuota 0 dan bon baru ditahan', () {
    final h = cekBatasKasbon(batas: 100000, utangSekarang: 120000, sisaTagihanBaru: 1);
    expect(h.boleh, isFalse);
    expect(h.sisaKuota, 0);
  });
}
