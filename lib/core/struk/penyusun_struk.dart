import 'package:intl/intl.dart';

import '../../features/promo/domain/rincian_pajak.dart';

/// Penyusun struk (tahap 4 bagian C) - FUNGSI MURNI: dari data
/// transaksi/pengaturan menjadi daftar [BarisStruk] siap render (plain
/// text utk preview/tes, atau dikonversi ke ESC/POS - lihat
/// lib/core/struk/esc_pos_converter.dart). TIDAK ada I/O, TIDAK ada
/// dependency ke drift/riverpod/printer - pemanggil (repository/provider)
/// yang bertanggung jawab merakit [StrukData]/[PengaturanStrukData] dari
/// sumber manapun (checkout baru, riwayat lama, dll), supaya modul ini
/// bisa dites langsung lewat `flutter test` tanpa widget/DB sama sekali.
///
/// Lebar kertas: 58 mm = 32 karakter, 80 mm = 48 karakter (aturan #1) -
/// SEMUA baris yang dihasilkan dijamin <= lebar itu (dipotong/di-wrap kalau
/// perlu), tidak pernah melebihi.

enum RataStruk { kiri, tengah, kanan }

/// Satu baris struk - [teks] adalah ISI MENTAH (sudah di-ASCII-fold +
/// dipastikan <= lebar kertas), BUKAN string yang sudah dipadding spasi
/// utk [RataStruk.tengah]/[RataStruk.kanan] (itu baru dihitung saat
/// render - lihat [renderTeksStruk]) - KECUALI baris yang sudah 2 kolom
/// (lihat [BarisStruk.duaKolom]), yang memang sudah full-width sejak
/// dibuat sehingga [rata]-nya selalu [RataStruk.kiri].
class BarisStruk {
  const BarisStruk(
    this.teks, {
    this.rata = RataStruk.kiri,
    this.tebal = false,
    this.besar = false,
  });

  /// Baris 2 kolom (label kiri + nilai kanan, mis. "Subtotal" & "Rp30.000")
  /// - dipisah spasi secukupnya supaya totalnya PAS [lebar] karakter. Label
  /// dipotong dulu kalau kepanjangan (nilai rupiah/tanggal praktis tidak
  /// pernah perlu dipotong).
  factory BarisStruk.duaKolom(
    String kiri,
    String kanan,
    int lebar, {
    bool tebal = false,
  }) {
    final k1Mentah = keAscii(kiri);
    final k2 = keAscii(kanan);
    final ruangKiri = lebar - k2.length - 1; // sisakan >= 1 spasi pemisah
    if (ruangKiri < 0) {
      // Kasus ekstrem: nilai kanan sendiri >= lebar kertas - potong nilai
      // kanan (praktis tidak pernah terjadi utk rupiah/tanggal wajar).
      return BarisStruk(k2.substring(0, lebar), tebal: tebal);
    }
    final k1 = k1Mentah.length > ruangKiri ? k1Mentah.substring(0, ruangKiri) : k1Mentah;
    final spasi = lebar - k1.length - k2.length;
    return BarisStruk('$k1${' ' * spasi}$k2', tebal: tebal);
  }

  final String teks;
  final RataStruk rata;
  final bool tebal;
  final bool besar;

  @override
  bool operator ==(Object other) =>
      other is BarisStruk &&
      other.teks == teks &&
      other.rata == rata &&
      other.tebal == tebal &&
      other.besar == besar;

  @override
  int get hashCode => Object.hash(teks, rata, tebal, besar);

  @override
  String toString() =>
      'BarisStruk("$teks", rata: $rata, tebal: $tebal, besar: $besar)';
}

/// Hasil penyusunan - [tampilkanLogo] dipisah dari [baris] krn logo adalah
/// GAMBAR (bitmap), bukan teks - konverter ESC/POS (atau renderer plain
/// text) yang memutuskan cara menampilkannya.
class HasilStruk {
  const HasilStruk({required this.tampilkanLogo, required this.baris});

  final bool tampilkanLogo;
  final List<BarisStruk> baris;
}

class PengaturanStrukData {
  const PengaturanStrukData({
    this.headerStruk,
    this.footerStruk,
    this.lebarKertasMm = 58,
    this.tampilLogo = false,
    this.strukRingkas = false,
    this.pakaiNomorAntrean = false,
    this.zonaWaktu = 'Asia/Jakarta',
  });

  final String? headerStruk;
  final String? footerStruk;
  final int lebarKertasMm; // 58 atau 80
  final bool tampilLogo;
  final bool strukRingkas;
  final bool pakaiNomorAntrean;
  // Zona waktu TOKO (aturan #2 - tanggal struk pakai zona waktu toko, bukan
  // device) - cuma dipakai utk label, konversi epoch->lokal tetap tanggung
  // jawab pemanggil (lihat formatTanggalWaktuStruk) krn Dart tanpa paket
  // timezone tambahan tidak bisa resolve nama zona IANA secara umum.
  final String zonaWaktu;

  int get lebarKarakter => lebarKertasMm == 80 ? 48 : 32;
}

class ItemStruk {
  const ItemStruk({
    required this.namaProduk,
    required this.qty,
    required this.hargaSatuan,
    required this.subtotal,
    this.modifiers = const [],
    this.catatan,
  });

  final String namaProduk;
  final double qty;
  final int hargaSatuan;
  final int subtotal;
  // Nama modifier saja cukup utk cetak - harga modifier sudah termasuk di
  // hargaSatuan/subtotal item (konsisten dgn cara checkout menyimpannya).
  final List<String> modifiers;
  final String? catatan;
}

class PembayaranStruk {
  const PembayaranStruk({required this.labelMetode, required this.jumlah});

  final String labelMetode;
  final int jumlah;
}

class StrukData {
  const StrukData({
    required this.namaOutlet,
    required this.nomorStruk,
    required this.tanggalEpochMs,
    this.namaKasir,
    this.namaPelanggan,
    this.namaTipeOrder,
    this.namaMeja,
    this.nomorAntrean,
    required this.items,
    required this.subtotal,
    this.diskonMember = 0,
    this.diskonPromo = 0,
    this.namaPromo,
    this.rincianService = const [],
    this.rincianPajak = const [],
    this.pembulatan = 0,
    required this.total,
    this.pembayaran = const [],
    this.kembalian = 0,
    this.statusBayar = 'lunas',
    this.sisaTagihan = 0,
    this.jatuhTempoEpochMs,
    this.poinDidapat,
    this.catatanTransaksi,
  });

  final String namaOutlet;
  final String nomorStruk;
  final int tanggalEpochMs;
  final String? namaKasir;
  final String? namaPelanggan;
  final String? namaTipeOrder;
  final String? namaMeja;
  final String? nomorAntrean;
  final List<ItemStruk> items;
  final int subtotal;
  final int diskonMember;
  final int diskonPromo;
  final String? namaPromo;
  final List<RincianPajak> rincianService;
  final List<RincianPajak> rincianPajak;
  final int pembulatan;
  final int total;
  final List<PembayaranStruk> pembayaran;
  final int kembalian;
  // Kasbon (tahap 3b-1) - 'lunas' | 'sebagian' | 'belumBayar'.
  final String statusBayar;
  final int sisaTagihan;
  final int? jatuhTempoEpochMs;
  final int? poinDidapat;
  final String? catatanTransaksi;
}

final _formatRupiah = NumberFormat.decimalPattern('id_ID');
final _formatTanggal = DateFormat('dd/MM/yyyy');
final _formatWaktu = DateFormat('dd/MM/yyyy HH:mm');

/// "Rp" + titik ribuan (aturan #1) - BUKAN NumberFormat.currency krn itu
/// pakai simbol "Rp" dgn spasi non-breaking yang beda dari konvensi struk
/// (nomor langsung nempel "Rp", lihat contoh di seluruh app: "Rp30.000").
/// Minus (nilai diskon/pembulatan negatif) diletakkan SEBELUM "Rp"
/// ("-Rp1.000", bukan "Rp-1.000") - NumberFormat taruh tanda minus di
/// depan digit, jadi "Rp" + format(nilai) negatif akan salah tempat kalau
/// tidak ditangani di sini.
String formatRupiahStruk(int nilai) =>
    nilai < 0 ? '-Rp${_formatRupiah.format(-nilai)}' : 'Rp${_formatRupiah.format(nilai)}';

// Zona waktu TOKO (bukan device) - Indonesia cuma 3 zona, jadi dipetakan
// manual lewat selisih jam drpd menambah dependency paket `timezone` utk
// resolve nama IANA penuh. Default WIB (Asia/Jakarta) kalau nama zona
// tidak dikenal.
int _offsetJamZonaWaktu(String zonaWaktu) {
  switch (zonaWaktu) {
    case 'Asia/Makassar':
      return 8; // WITA
    case 'Asia/Jayapura':
      return 9; // WIT
    default:
      return 7; // WIB (Asia/Jakarta)
  }
}

DateTime _keWaktuToko(int epochMs, String zonaWaktu) => DateTime.fromMillisecondsSinceEpoch(
      epochMs,
      isUtc: true,
    ).add(Duration(hours: _offsetJamZonaWaktu(zonaWaktu)));

String formatTanggalWaktuStruk(int epochMs, {String zonaWaktu = 'Asia/Jakarta'}) =>
    _formatWaktu.format(_keWaktuToko(epochMs, zonaWaktu));

String formatTanggalStruk(int epochMs, {String zonaWaktu = 'Asia/Jakarta'}) =>
    _formatTanggal.format(_keWaktuToko(epochMs, zonaWaktu));

// Padanan ASCII (aturan #4) utk tanda baca umum yang sering muncul dari
// hasil ketik/salin pengguna (header/footer/catatan custom) - karakter
// non-ASCII LAIN yang tidak ada di peta ini (emoji dkk, tidak punya
// padanan ASCII yang masuk akal) dibuang sepenuhnya, bukan dipaksa tampil
// sbg byte rusak di printer thermal.
const _penggantiAscii = <String, String>{
  '‘': "'", '’': "'", // ‘ ’
  '“': '"', '”': '"', // “ ”
  '–': '-', '—': '-', // – —
  '…': '...', // …
  '•': '-', // •
  '·': '-', // ·
  '°': 'der', // °
  '™': '(TM)', // ™
  '©': '(C)', // ©
  '®': '(R)', // ®
};

/// Ganti karakter non-ASCII (emoji, kutip miring, em dash, dkk) dgn
/// padanan ASCII-nya (aturan #4) - printer thermal umumnya cuma punya
/// code page terbatas, karakter di luar itu jadi kotak/tanda tanya aneh.
String keAscii(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune < 128) {
      buffer.writeCharCode(rune);
      continue;
    }
    final pengganti = _penggantiAscii[String.fromCharCode(rune)];
    if (pengganti != null) buffer.write(pengganti);
    // else: dibuang (emoji dkk tanpa padanan ASCII yang masuk akal).
  }
  return buffer.toString();
}

String _garis(int lebar) => '-' * lebar;

String _tengahkan(String teks, int lebar) {
  if (teks.length >= lebar) return teks.substring(0, lebar);
  final totalSpasi = lebar - teks.length;
  final kiri = totalSpasi ~/ 2;
  return '${' ' * kiri}$teks${' ' * (totalSpasi - kiri)}';
}

String _kanankan(String teks, int lebar) {
  if (teks.length >= lebar) return teks.substring(0, lebar);
  return '${' ' * (lebar - teks.length)}$teks';
}

/// Pecah [teks] (sudah di-ASCII-fold) menjadi baris2 sepanjang <= [lebar],
/// word-wrap sederhana (pecah di spasi kalau bisa, paksa potong kalau satu
/// kata saja sudah lebih panjang dari [lebar]).
List<String> bungkusTeks(String teks, int lebar) {
  final bersih = keAscii(teks).trim();
  if (bersih.isEmpty) return const [];
  if (bersih.length <= lebar) return [bersih];

  final hasil = <String>[];
  var sisa = bersih;
  while (sisa.length > lebar) {
    var potong = lebar;
    final spasiTerakhir = sisa.substring(0, lebar + 1).lastIndexOf(' ');
    if (spasiTerakhir > 0) potong = spasiTerakhir;
    hasil.add(sisa.substring(0, potong).trimRight());
    sisa = sisa.substring(potong).trimLeft();
  }
  if (sisa.isNotEmpty) hasil.add(sisa);
  return hasil;
}

/// Render [baris] (hasil [susunStrukTransaksi] dkk) jadi teks per-baris
/// SIAP TAMPIL (preview/tes) - padding tengah/kanan diterapkan DI SINI,
/// bukan saat menyusun, supaya [BarisStruk.teks] tetap berupa konten
/// mentah (lebih mudah dites/dibandingkan). Setiap baris hasil dijamin
/// panjangnya <= [lebar].
List<String> renderTeksStruk(List<BarisStruk> baris, int lebar) {
  return [
    for (final b in baris)
      switch (b.rata) {
        RataStruk.kiri => b.teks.length > lebar ? b.teks.substring(0, lebar) : b.teks,
        RataStruk.tengah => _tengahkan(b.teks, lebar),
        RataStruk.kanan => _kanankan(b.teks, lebar),
      },
  ];
}

List<BarisStruk> _baris2KolomRupiah(String label, int nilai, int lebar, {bool tebal = false}) =>
    [BarisStruk.duaKolom(label, formatRupiahStruk(nilai), lebar, tebal: tebal)];

/// Struk transaksi LENGKAP (aturan #2-3) - [salinan] = true menandai hasil
/// cetak ulang dari Riwayat ("** SALINAN **", aturan #5). [pengaturan.
/// strukRingkas] memangkas ke hanya item/total/pembayaran/kembalian
/// (aturan #3) - selebihnya (modifier, rincian pajak/service, promo,
/// poin, catatan) disembunyikan, BUKAN dihapus datanya.
List<BarisStruk> susunStrukTransaksi({
  required StrukData data,
  required PengaturanStrukData pengaturan,
  bool salinan = false,
}) {
  final lebar = pengaturan.lebarKarakter;
  final ringkas = pengaturan.strukRingkas;
  final baris = <BarisStruk>[];

  if (pengaturan.headerStruk != null && pengaturan.headerStruk!.trim().isNotEmpty) {
    for (final baris_ in bungkusTeks(pengaturan.headerStruk!, lebar)) {
      baris.add(BarisStruk(baris_, rata: RataStruk.tengah));
    }
  }
  for (final baris_ in bungkusTeks(data.namaOutlet, lebar)) {
    baris.add(BarisStruk(baris_, rata: RataStruk.tengah, tebal: true));
  }
  baris.add(BarisStruk(_garis(lebar)));
  baris.add(BarisStruk(keAscii(data.nomorStruk)));
  if (salinan) {
    baris.add(const BarisStruk('** SALINAN **', rata: RataStruk.tengah, tebal: true));
  }
  baris.add(BarisStruk(formatTanggalWaktuStruk(data.tanggalEpochMs, zonaWaktu: pengaturan.zonaWaktu)));
  if (data.namaKasir != null) baris.add(BarisStruk('Kasir: ${keAscii(data.namaKasir!)}'));
  if (data.namaPelanggan != null) {
    baris.add(BarisStruk('Pelanggan: ${keAscii(data.namaPelanggan!)}'));
  }
  if (data.namaTipeOrder != null) {
    final label = data.namaMeja != null
        ? '${keAscii(data.namaTipeOrder!)} - ${keAscii(data.namaMeja!)}'
        : keAscii(data.namaTipeOrder!);
    baris.add(BarisStruk(label));
  }
  // Nomor antrean HURUF BESAR kalau fitur-nya aktif (aturan #2) - paling
  // menonjol krn ini yang diteriakkan/dipanggil ke pelanggan.
  if (pengaturan.pakaiNomorAntrean && data.nomorAntrean != null) {
    baris.add(
      BarisStruk(
        'NO. ANTREAN: ${keAscii(data.nomorAntrean!).toUpperCase()}',
        rata: RataStruk.tengah,
        tebal: true,
        besar: true,
      ),
    );
  }
  baris.add(BarisStruk(_garis(lebar)));

  for (final item in data.items) {
    final qtyStr = item.qty == item.qty.roundToDouble()
        ? item.qty.toStringAsFixed(0)
        : item.qty.toString();
    for (final baris_ in bungkusTeks(item.namaProduk, lebar)) {
      baris.add(BarisStruk(baris_));
    }
    baris.add(
      BarisStruk.duaKolom('  $qtyStr x ${formatRupiahStruk(item.hargaSatuan)}', formatRupiahStruk(item.subtotal), lebar),
    );
    if (!ringkas) {
      for (final modifier in item.modifiers) {
        for (final baris_ in bungkusTeks('  + $modifier', lebar)) {
          baris.add(BarisStruk(baris_));
        }
      }
      if (item.catatan != null && item.catatan!.trim().isNotEmpty) {
        for (final baris_ in bungkusTeks('  Catatan: ${item.catatan}', lebar)) {
          baris.add(BarisStruk(baris_));
        }
      }
    }
  }

  baris.add(BarisStruk(_garis(lebar)));

  if (!ringkas) {
    baris.addAll(_baris2KolomRupiah('Subtotal', data.subtotal, lebar));
    if (data.diskonMember > 0) {
      baris.addAll(_baris2KolomRupiah('Diskon member', -data.diskonMember, lebar));
    }
    if (data.diskonPromo > 0) {
      baris.addAll(_baris2KolomRupiah(data.namaPromo ?? 'Promo', -data.diskonPromo, lebar));
    }
    for (final r in data.rincianService) {
      baris.addAll(_baris2KolomRupiah('${r.nama} ${_formatPersen(r.persen)}%', r.jumlah, lebar));
    }
    for (final r in data.rincianPajak) {
      final label = '${r.nama} ${_formatPersen(r.persen)}%${r.termasukHarga ? ' (incl)' : ''}';
      baris.addAll(_baris2KolomRupiah(label, r.jumlah, lebar));
    }
    if (data.pembulatan != 0) {
      baris.addAll(_baris2KolomRupiah('Pembulatan', data.pembulatan, lebar));
    }
  }

  baris.add(BarisStruk.duaKolom('TOTAL', formatRupiahStruk(data.total), lebar, tebal: true));
  for (final p in data.pembayaran) {
    baris.addAll(_baris2KolomRupiah(keAscii(p.labelMetode), p.jumlah, lebar));
  }

  final kasbon = data.statusBayar != 'lunas';
  if (kasbon) {
    baris.addAll(_baris2KolomRupiah('Sisa tagihan', data.sisaTagihan, lebar));
    if (data.jatuhTempoEpochMs != null) {
      baris.add(
        BarisStruk.duaKolom(
          'Jatuh tempo',
          formatTanggalStruk(data.jatuhTempoEpochMs!, zonaWaktu: pengaturan.zonaWaktu),
          lebar,
        ),
      );
    }
  } else {
    baris.addAll(_baris2KolomRupiah('Kembali', data.kembalian, lebar));
  }

  if (!ringkas) {
    if (data.poinDidapat != null && data.poinDidapat! > 0) {
      baris.add(BarisStruk('Poin didapat: +${data.poinDidapat}'));
    }
    if (data.catatanTransaksi != null && data.catatanTransaksi!.trim().isNotEmpty) {
      for (final baris_ in bungkusTeks('Catatan: ${data.catatanTransaksi}', lebar)) {
        baris.add(BarisStruk(baris_));
      }
    }
  }

  baris.add(BarisStruk(_garis(lebar)));
  if (pengaturan.footerStruk != null && pengaturan.footerStruk!.trim().isNotEmpty) {
    for (final baris_ in bungkusTeks(pengaturan.footerStruk!, lebar)) {
      baris.add(BarisStruk(baris_, rata: RataStruk.tengah));
    }
  } else {
    baris.add(const BarisStruk('Terima kasih!', rata: RataStruk.tengah));
  }

  return baris;
}

/// Bungkus [susunStrukTransaksi] + status logo - lihat [HasilStruk].
HasilStruk susunHasilStrukTransaksi({
  required StrukData data,
  required PengaturanStrukData pengaturan,
  bool salinan = false,
}) =>
    HasilStruk(
      tampilkanLogo: pengaturan.tampilLogo,
      baris: susunStrukTransaksi(data: data, pengaturan: pengaturan, salinan: salinan),
    );

/// Bukti pelunasan/cicilan kasbon (aturan #5) - dicetak dari PelunasanPage
/// setelah satu pembayaran kasbon dicatat (bukan struk transaksi penuh,
/// cuma konfirmasi SATU pembayaran itu).
List<BarisStruk> susunBuktiPelunasan({
  required String namaOutlet,
  required String nomorStrukAsal,
  required String namaPelanggan,
  required int jumlahDibayar,
  required String labelMetode,
  required int sisaSetelahIni,
  required int tanggalEpochMs,
  required PengaturanStrukData pengaturan,
}) {
  final lebar = pengaturan.lebarKarakter;
  final baris = <BarisStruk>[];

  for (final baris_ in bungkusTeks(namaOutlet, lebar)) {
    baris.add(BarisStruk(baris_, rata: RataStruk.tengah, tebal: true));
  }
  baris.add(BarisStruk(_garis(lebar)));
  baris.add(const BarisStruk('BUKTI PEMBAYARAN KASBON', rata: RataStruk.tengah, tebal: true));
  baris.add(BarisStruk('Transaksi: ${keAscii(nomorStrukAsal)}'));
  baris.add(BarisStruk('Pelanggan: ${keAscii(namaPelanggan)}'));
  baris.add(BarisStruk(formatTanggalWaktuStruk(tanggalEpochMs, zonaWaktu: pengaturan.zonaWaktu)));
  baris.add(BarisStruk(_garis(lebar)));
  baris.addAll(_baris2KolomRupiah('Dibayar', jumlahDibayar, lebar, tebal: true));
  baris.add(BarisStruk.duaKolom('Metode', keAscii(labelMetode), lebar));
  baris.addAll(_baris2KolomRupiah('Sisa tagihan', sisaSetelahIni, lebar));
  baris.add(BarisStruk(_garis(lebar)));
  baris.add(const BarisStruk('Terima kasih', rata: RataStruk.tengah));
  return baris;
}

/// Struk void/refund (aturan #5) - nomor struk asal, alasan, item yang
/// dibatalkan/dikembalikan, dan jumlah uang yang dikembalikan (refund) atau
/// catatan void tanpa pengembalian uang (transaksi belum dibayar).
List<BarisStruk> susunStrukVoidRefund({
  required String namaOutlet,
  required String nomorStruk,
  required bool adalahRefund,
  required String alasan,
  required List<ItemStruk> items,
  required int jumlahDikembalikan,
  required int tanggalEpochMs,
  required PengaturanStrukData pengaturan,
}) {
  final lebar = pengaturan.lebarKarakter;
  final baris = <BarisStruk>[];
  final judul = adalahRefund ? 'STRUK REFUND' : 'STRUK VOID';

  for (final baris_ in bungkusTeks(namaOutlet, lebar)) {
    baris.add(BarisStruk(baris_, rata: RataStruk.tengah, tebal: true));
  }
  baris.add(BarisStruk(_garis(lebar)));
  baris.add(BarisStruk(judul, rata: RataStruk.tengah, tebal: true));
  baris.add(BarisStruk('Transaksi: ${keAscii(nomorStruk)}'));
  baris.add(BarisStruk(formatTanggalWaktuStruk(tanggalEpochMs, zonaWaktu: pengaturan.zonaWaktu)));
  for (final baris_ in bungkusTeks('Alasan: $alasan', lebar)) {
    baris.add(BarisStruk(baris_));
  }
  baris.add(BarisStruk(_garis(lebar)));
  for (final item in items) {
    final qtyStr = item.qty == item.qty.roundToDouble()
        ? item.qty.toStringAsFixed(0)
        : item.qty.toString();
    for (final baris_ in bungkusTeks(item.namaProduk, lebar)) {
      baris.add(BarisStruk(baris_));
    }
    baris.add(
      BarisStruk.duaKolom('  $qtyStr x ${formatRupiahStruk(item.hargaSatuan)}', formatRupiahStruk(item.subtotal), lebar),
    );
  }
  baris.add(BarisStruk(_garis(lebar)));
  if (adalahRefund) {
    baris.add(BarisStruk.duaKolom('Dikembalikan', formatRupiahStruk(jumlahDikembalikan), lebar, tebal: true));
  } else {
    baris.add(const BarisStruk('Transaksi dibatalkan, tidak ada uang keluar.'));
  }
  baris.add(BarisStruk(_garis(lebar)));
  return baris;
}

/// Rekap tutup shift (aturan #5) - modal awal, penjualan per metode bayar,
/// kas seharusnya/aktual/selisih, jumlah transaksi.
List<BarisStruk> susunRekapTutupShift({
  required String namaOutlet,
  required String namaKasir,
  required int dibukaEpochMs,
  required int ditutupEpochMs,
  required int modalAwal,
  required List<PembayaranStruk> penjualanPerMetode,
  required int jumlahTransaksi,
  required int kasSeharusnya,
  required int kasAktual,
  required PengaturanStrukData pengaturan,
}) {
  final lebar = pengaturan.lebarKarakter;
  final selisih = kasAktual - kasSeharusnya;
  final baris = <BarisStruk>[];

  for (final baris_ in bungkusTeks(namaOutlet, lebar)) {
    baris.add(BarisStruk(baris_, rata: RataStruk.tengah, tebal: true));
  }
  baris.add(BarisStruk(_garis(lebar)));
  baris.add(const BarisStruk('REKAP TUTUP SHIFT', rata: RataStruk.tengah, tebal: true));
  baris.add(BarisStruk('Kasir: ${keAscii(namaKasir)}'));
  baris.add(
    BarisStruk('Buka : ${formatTanggalWaktuStruk(dibukaEpochMs, zonaWaktu: pengaturan.zonaWaktu)}'),
  );
  baris.add(
    BarisStruk('Tutup: ${formatTanggalWaktuStruk(ditutupEpochMs, zonaWaktu: pengaturan.zonaWaktu)}'),
  );
  baris.add(BarisStruk(_garis(lebar)));
  baris.addAll(_baris2KolomRupiah('Modal awal', modalAwal, lebar));
  for (final p in penjualanPerMetode) {
    baris.addAll(_baris2KolomRupiah(keAscii(p.labelMetode), p.jumlah, lebar));
  }
  baris.add(BarisStruk('Jumlah transaksi: $jumlahTransaksi'));
  baris.add(BarisStruk(_garis(lebar)));
  baris.addAll(_baris2KolomRupiah('Kas seharusnya', kasSeharusnya, lebar));
  baris.addAll(_baris2KolomRupiah('Kas aktual', kasAktual, lebar));
  baris.addAll(_baris2KolomRupiah('Selisih', selisih, lebar, tebal: true));
  baris.add(BarisStruk(_garis(lebar)));
  return baris;
}

String _formatPersen(double persen) =>
    persen == persen.roundToDouble() ? persen.toStringAsFixed(0) : persen.toString();
