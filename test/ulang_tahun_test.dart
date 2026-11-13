import 'package:apps_pos/features/pelanggan/domain/ulang_tahun.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('konversi tanggal lahir', () {
    test('ISO ke bilangan yyyymmdd dan sebaliknya', () {
      expect(tanggalLahirDariIso('1995-04-12'), 19950412);
      expect(tanggalLahirDariIso('1995-04-12T00:00:00'), 19950412);
      expect(tanggalLahirKeIso(19950412), '1995-04-12');
      expect(tanggalLahirKeIso(19000101), '1900-01-01');
      expect(tanggalLahirKeIso(null), isNull);
    });

    test('tidak terbaca atau tanggal fiktif menghasilkan null', () {
      expect(tanggalLahirDariIso(null), isNull);
      expect(tanggalLahirDariIso('abc'), isNull);
      expect(tanggalLahirDariIso('1995-02-30'), isNull);
      expect(tanggalLahirDariIso('1995-13-01'), isNull);
    });

    test('ke DateTime', () {
      expect(tanggalLahirKeDateTime(19950412), DateTime(1995, 4, 12));
      expect(tanggalLahirKeDateTime(null), isNull);
    });
  });

  group('ulangTahunHariIni', () {
    test('cocok bulan dan tanggal, tahun lahir diabaikan', () {
      expect(ulangTahunHariIni(19950412, DateTime(2026, 4, 12, 23, 59)), isTrue);
      expect(ulangTahunHariIni(19950412, DateTime(2026, 4, 13)), isFalse);
      expect(ulangTahunHariIni(19950412, DateTime(2026, 5, 12)), isFalse);
      expect(ulangTahunHariIni(null, DateTime(2026, 4, 12)), isFalse);
    });

    test('lahir 29 Februari dirayakan 28 Februari di tahun bukan kabisat, 29 Februari di kabisat', () {
      expect(ulangTahunHariIni(20000229, DateTime(2026, 2, 28)), isTrue);
      expect(ulangTahunHariIni(20000229, DateTime(2026, 3, 1)), isFalse);
      expect(ulangTahunHariIni(20000229, DateTime(2028, 2, 29)), isTrue);
      expect(ulangTahunHariIni(20000229, DateTime(2028, 2, 28)), isFalse);
      expect(ulangTahunHariIni(20000229, DateTime(2100, 2, 28)), isTrue, reason: '2100 bukan kabisat');
    });
  });

  test('ulangTahunBulanIni dan usiaTahunIni', () {
    expect(ulangTahunBulanIni(19950412, DateTime(2026, 4, 1)), isTrue);
    expect(ulangTahunBulanIni(19950412, DateTime(2026, 5, 1)), isFalse);
    expect(ulangTahunBulanIni(null, DateTime(2026, 4, 1)), isFalse);
    expect(usiaTahunIni(19950412, DateTime(2026, 4, 12)), 31);
    expect(usiaTahunIni(null, DateTime(2026, 4, 12)), isNull);
  });
}
