import 'package:apps_pos/core/struk/gaya_logo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _png(GayaLogo g, String nama, {int ukuran = 240}) =>
    img.decodePng(buatLogoGaya(g, nama, ukuran: ukuran)!)!;

bool _hitam(img.Pixel p) => p.r < 128;

void main() {
  group('inisialUsaha', () {
    test('dua huruf awal dari dua kata pertama', () {
      expect(inisialUsaha('Kopi Senja'), 'KS');
      expect(inisialUsaha('warung makan sedap'), 'WM');
    });
    test('satu kata menghasilkan satu huruf', () => expect(inisialUsaha('Warung'), 'W'));
    test('mengabaikan tanda baca dan spasi berlebih', () {
      expect(inisialUsaha('  "Kedai" & Co  '), 'KC');
      expect(inisialUsaha('(1) Toko'), '1T');
    });
    test('kosong atau tanpa huruf menghasilkan tanda tanya', () {
      expect(inisialUsaha(''), '?');
      expect(inisialUsaha('   '), '?');
      expect(inisialUsaha('---'), '?');
    });
  });

  test('GayaLogo.dari: kode dikenal, selain itu kembali ke unggah', () {
    expect(GayaLogo.dari('cincin'), GayaLogo.cincin);
    expect(GayaLogo.dari('inisial'), GayaLogo.inisial);
    expect(GayaLogo.dari('bintang'), GayaLogo.unggah);
    expect(GayaLogo.dari(null), GayaLogo.unggah);
  });

  test('gaya unggah tidak dibuat otomatis', () {
    expect(buatLogoGaya(GayaLogo.unggah, 'Kopi'), isNull);
    expect(GayaLogo.unggah.dibuatOtomatis, isFalse);
    expect(GayaLogo.lingkaran.dibuatOtomatis, isTrue);
  });

  test('hasil berupa PNG persegi dengan ukuran yang diminta dan hanya hitam-putih', () {
    for (final g in [GayaLogo.lingkaran, GayaLogo.cincin, GayaLogo.inisial]) {
      final gambar = _png(g, 'Kopi Senja', ukuran: 200);
      expect(gambar.width, 200, reason: '$g');
      expect(gambar.height, 200, reason: '$g');
      var nonBw = 0;
      for (final p in gambar) {
        final r = p.r.toInt();
        if (r != 0 && r != 255) nonBw++;
      }
      expect(nonBw, 0, reason: '$g tidak boleh punya piksel abu-abu (printer thermal hitam-putih)');
    }
  });

  test('lingkaran: pinggir isi hitam dan sudut kanvas putih', () {
    final g = _png(GayaLogo.lingkaran, 'Kopi Senja');
    expect(_hitam(g.getPixel(120, 20)), isTrue, reason: 'bagian atas lingkaran terisi hitam');
    expect(_hitam(g.getPixel(2, 2)), isFalse, reason: 'sudut kanvas putih');
  }, skip: false);

  test('cincin: tepi hitam, tengah di luar huruf putih; inisial: tidak ada lingkaran', () {
    final cincin = _png(GayaLogo.cincin, 'Kopi Senja');
    expect(_hitam(cincin.getPixel(120, 10)), isTrue, reason: 'garis cincin');
    expect(_hitam(cincin.getPixel(120, 40)), isFalse, reason: 'bagian dalam cincin putih');

    final inisial = _png(GayaLogo.inisial, 'Kopi Senja');
    expect(_hitam(inisial.getPixel(120, 10)), isFalse, reason: 'gaya inisial tanpa lingkaran');
    var hitam = 0;
    for (final p in inisial) {
      if (_hitam(p)) hitam++;
    }
    expect(hitam, greaterThan(200), reason: 'huruf inisial tergambar');
  });

  test('inisial berbeda menghasilkan gambar berbeda', () {
    final a = buatLogoGaya(GayaLogo.inisial, 'Kopi Senja');
    final b = buatLogoGaya(GayaLogo.inisial, 'Warung Mawar');
    expect(a, isNot(equals(b)));
  });
}
