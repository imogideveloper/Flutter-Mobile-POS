import 'dart:convert';

import 'penyusun_struk.dart';
import 'penyusun_tiket_dapur.dart';

/// Label produk untuk ditempel di kemasan (F&B): SATU stiker per porsi, berisi nomor antrean, nama
/// produk, varian/tambahan, catatan, dan keterangan "n/total" supaya kasir dan dapur tahu semua porsi
/// sudah tertempel. FUNGSI MURNI seperti [susunTiketDapur]; pencetaknya (printer label, bahasa TSPL)
/// dipisah di cetak_label_helper.dart.

/// Batas label per baris item supaya qty tak wajar (mis. 500) tidak menghabiskan gulungan stiker.
const int batasLabelPerItem = 50;

class LabelProdukData {
  const LabelProdukData({
    required this.namaProduk,
    required this.urutan,
    required this.total,
    required this.tanggalEpochMs,
    this.nomorAntrean,
    this.nomorStruk,
    this.namaToko,
    this.namaTipeOrder,
    this.tambahan = const [],
    this.catatan,
  });

  final String namaProduk;

  /// Urutan stiker di pesanan ini (mulai 1) dan jumlah seluruh stiker pesanan.
  final int urutan;
  final int total;
  final int tanggalEpochMs;
  final String? nomorAntrean;
  final String? nomorStruk;
  final String? namaToko;
  final String? namaTipeOrder;
  final List<String> tambahan;
  final String? catatan;
}

/// Pecah [items] jadi satu label per porsi. qty pecahan dibulatkan ke atas (0,5 porsi tetap perlu satu
/// stiker); qty nol atau negatif tidak mencetak apa-apa.
List<LabelProdukData> susunLabelProduk({
  required List<ItemTiketDapur> items,
  required int tanggalEpochMs,
  String? nomorAntrean,
  String? nomorStruk,
  String? namaToko,
  String? namaTipeOrder,
}) {
  final porsi = <ItemTiketDapur>[];
  for (final item in items) {
    final n = item.qty.ceil().clamp(0, batasLabelPerItem);
    for (var i = 0; i < n; i++) {
      porsi.add(item);
    }
  }
  return [
    for (var i = 0; i < porsi.length; i++)
      LabelProdukData(
        namaProduk: porsi[i].namaProduk,
        urutan: i + 1,
        total: porsi.length,
        tanggalEpochMs: tanggalEpochMs,
        nomorAntrean: nomorAntrean,
        nomorStruk: nomorStruk,
        namaToko: namaToko,
        namaTipeOrder: namaTipeOrder,
        tambahan: porsi[i].tambahan,
        catatan: porsi[i].catatan,
      ),
  ];
}

/// Teks label sebagai baris, untuk pratinjau dan uji (isi sama dengan yang dikirim ke printer).
List<String> barisTeksLabel(
  LabelProdukData d, {
  int lebar = 24,
  String zonaWaktu = 'Asia/Jakarta',
}) {
  final baris = <String>[];
  if (d.nomorAntrean != null && d.nomorAntrean!.trim().isNotEmpty)
    baris.add(keAscii(d.nomorAntrean!));
  baris.addAll(bungkusTeks(keAscii(d.namaProduk), lebar));
  for (final t in d.tambahan) {
    baris.addAll(bungkusTeks('+ ${keAscii(t)}', lebar));
  }
  if (d.catatan != null && d.catatan!.trim().isNotEmpty) {
    baris.addAll(bungkusTeks('* ${keAscii(d.catatan!)}', lebar));
  }
  final waktu = formatTanggalWaktuStruk(d.tanggalEpochMs, zonaWaktu: zonaWaktu);
  baris.add('${d.urutan}/${d.total}  $waktu');
  if (d.namaToko != null && d.namaToko!.trim().isNotEmpty)
    baris.add(keAscii(d.namaToko!));
  return baris;
}

/// Perintah TSPL (bahasa standar printer label termal 203 dpi seperti Xprinter, TSC, Gprinter) untuk
/// SATU stiker berukuran [lebarMm] x [tinggiMm]. Satu titik = 1/8 mm. Tata letak: nomor antrean besar di
/// atas, nama produk, tambahan, catatan, lalu "n/total" dan waktu di bawah. Baris yang tidak muat di
/// tinggi stiker dibuang dari bawah (nomor antrean dan nama produk didahulukan).
List<int> susunTspl(
  LabelProdukData d, {
  required int lebarMm,
  required int tinggiMm,
  String zonaWaktu = 'Asia/Jakarta',
}) {
  const titikPerMm = 8;
  const margin = 12;
  final lebarTitik = lebarMm * titikPerMm;
  final tinggiTitik = tinggiMm * titikPerMm;
  final area = lebarTitik - margin * 2;

  String q(String s) => keAscii(s).replaceAll('"', "'");
  final out = StringBuffer()
    ..write('SIZE $lebarMm mm,$tinggiMm mm\r\n')
    ..write('GAP 2 mm,0 mm\r\n')
    ..write('DIRECTION 1\r\n')
    ..write('CLS\r\n');

  var y = 8;
  void teks(
    String isi, {
    required String font,
    int kali = 1,
    required int lebarKarakter,
    required int tinggiBaris,
  }) {
    for (final b in bungkusTeks(
      q(isi),
      (area ~/ (lebarKarakter * kali)).clamp(4, 80),
    )) {
      if (y + tinggiBaris > tinggiTitik - 8) return;
      out.write('TEXT $margin,$y,"$font",0,$kali,$kali,"$b"\r\n');
      y += tinggiBaris;
    }
  }

  if (d.nomorAntrean != null && d.nomorAntrean!.trim().isNotEmpty) {
    teks(
      d.nomorAntrean!,
      font: '4',
      kali: 2,
      lebarKarakter: 24,
      tinggiBaris: 68,
    );
  }
  teks(d.namaProduk, font: '3', lebarKarakter: 16, tinggiBaris: 28);
  for (final t in d.tambahan) {
    teks('+ $t', font: '2', lebarKarakter: 12, tinggiBaris: 24);
  }
  if (d.catatan != null && d.catatan!.trim().isNotEmpty) {
    teks('* ${d.catatan!}', font: '2', lebarKarakter: 12, tinggiBaris: 24);
  }
  // Keterangan bawah ditempel ke dasar stiker.
  final waktu = formatTanggalWaktuStruk(d.tanggalEpochMs, zonaWaktu: zonaWaktu);
  final bawah = <String>[
    '${d.urutan}/${d.total}  $waktu',
    if (d.namaToko != null && d.namaToko!.trim().isNotEmpty) q(d.namaToko!),
  ];
  var yb = tinggiTitik - 8 - bawah.length * 18;
  for (final b in bawah) {
    out.write('TEXT $margin,$yb,"1",0,1,1,"${q(b)}"\r\n');
    yb += 18;
  }
  out.write('PRINT 1,1\r\n');
  return ascii.encode(out.toString());
}
