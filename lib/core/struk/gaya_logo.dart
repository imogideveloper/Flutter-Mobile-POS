import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Gaya logo struk (IMOGI no. 24). [unggah] memakai gambar yang diunggah usaha; tiga gaya lain
/// dibuat otomatis dari inisial nama usaha sehingga usaha tanpa logo tetap punya identitas di struk.
/// "Tanpa logo" = saklar Tampilkan logo dimatikan.
enum GayaLogo {
  unggah('unggah', 'Logo unggahan'),
  lingkaran('lingkaran', 'Lingkaran'),
  cincin('cincin', 'Cincin'),
  inisial('inisial', 'Inisial');

  const GayaLogo(this.kode, this.label);

  final String kode;
  final String label;

  /// Gaya yang dibuat dari nama usaha (bukan gambar unggahan).
  bool get dibuatOtomatis => this != GayaLogo.unggah;

  static GayaLogo dari(String? kode) =>
      GayaLogo.values.firstWhere((g) => g.kode == kode, orElse: () => GayaLogo.unggah);
}

/// Satu atau dua huruf awal dari nama usaha, huruf besar. "Kopi Senja" -> "KS", "Warung" -> "W",
/// kosong -> "?". Hanya huruf dan angka yang dihitung.
String inisialUsaha(String nama) {
  final kata = nama.split(RegExp(r'\s+')).where((k) => k.isNotEmpty).toList();
  String huruf(String k) {
    for (final r in k.runes) {
      final c = String.fromCharCode(r);
      if (RegExp(r'[A-Za-z0-9]').hasMatch(c)) return c.toUpperCase();
    }
    return '';
  }

  final awal = [for (final k in kata) huruf(k)].where((h) => h.isNotEmpty).take(2).join();
  return awal.isEmpty ? '?' : awal;
}

/// PNG logo untuk gaya otomatis. Hitam-putih agar tegas di printer thermal. [ukuran] = sisi gambar
/// akhir (piksel). Gaya [GayaLogo.unggah] tidak dibuat di sini (kembali null).
Uint8List? buatLogoGaya(GayaLogo gaya, String namaUsaha, {int ukuran = 240}) {
  if (!gaya.dibuatOtomatis) return null;

  // Digambar pada kanvas kecil dengan huruf bitmap bawaan, lalu diperbesar tanpa penghalusan
  // supaya huruf tetap besar dan tajam.
  const basis = 120;
  final kanvas = img.Image(width: basis, height: basis, numChannels: 3);
  img.fill(kanvas, color: img.ColorRgb8(255, 255, 255));
  final hitam = img.ColorRgb8(0, 0, 0);
  final putih = img.ColorRgb8(255, 255, 255);
  const tengah = basis ~/ 2;

  switch (gaya) {
    case GayaLogo.lingkaran:
      img.fillCircle(kanvas, x: tengah, y: tengah, radius: 56, color: hitam);
    case GayaLogo.cincin:
      img.fillCircle(kanvas, x: tengah, y: tengah, radius: 56, color: hitam);
      img.fillCircle(kanvas, x: tengah, y: tengah, radius: 49, color: putih);
    case GayaLogo.inisial:
    case GayaLogo.unggah:
      break;
  }

  final teks = inisialUsaha(namaUsaha);
  final font = img.arial48;
  var lebarTeks = 0;
  for (final r in teks.runes) {
    lebarTeks += font.characters[r]?.xAdvance ?? 0;
  }
  final warnaTeks = gaya == GayaLogo.lingkaran ? putih : hitam;
  img.drawString(
    kanvas,
    teks,
    font: font,
    x: tengah - lebarTeks ~/ 2,
    y: tengah - font.lineHeight ~/ 2,
    color: warnaTeks,
  );

  // Huruf bitmap berpenghalusan menghasilkan abu-abu; tegaskan jadi hitam atau putih murni.
  for (final p in kanvas) {
    final nilai = p.r < 128 ? 0 : 255;
    p.setRgb(nilai, nilai, nilai);
  }

  final akhir = img.copyResize(kanvas, width: ukuran, height: ukuran, interpolation: img.Interpolation.nearest);
  return Uint8List.fromList(img.encodePng(akhir));
}
