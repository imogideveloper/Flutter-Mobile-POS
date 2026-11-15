import 'package:apps_pos/features/transaksi/domain/referensi_pembayaran.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? cek({bool wajib = false, bool kartu = false, String nomor = '', String digit = ''}) =>
      validasiReferensiPembayaran(wajibReferensi: wajib, kartu: kartu, nomorReferensi: nomor, empatDigit: digit);

  test('tidak wajib: kosong boleh', () => expect(cek(), isNull));

  test('tidak wajib: 4 digit yang diisi harus tepat 4 angka', () {
    expect(cek(digit: '12'), isNotNull);
    expect(cek(digit: '12ab'), isNotNull);
    expect(cek(digit: '1234'), isNull);
  });

  test('wajib: no. referensi harus diisi', () {
    expect(cek(wajib: true), contains('referensi'));
    expect(cek(wajib: true, nomor: '  '), isNotNull, reason: 'spasi saja dianggap kosong');
    expect(cek(wajib: true, nomor: 'APP-778'), isNull);
  });

  test('wajib pada kartu: 4 digit akhir juga wajib', () {
    expect(cek(wajib: true, kartu: true, nomor: 'APP-778'), contains('4 digit'));
    expect(cek(wajib: true, kartu: true, nomor: 'APP-778', digit: '9876'), isNull);
  });

  test('wajib pada transfer/e-wallet: 4 digit tidak diminta', () {
    expect(cek(wajib: true, kartu: false, nomor: 'TRX-1'), isNull);
  });
}
