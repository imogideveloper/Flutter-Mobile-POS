/// Template dan pembacaan CSV pelanggan (IMOGI no. 53). FUNGSI MURNI tanpa berkas/jaringan.
library;

import '../../../core/utils/csv_dasar.dart';

const kolomTemplatePelanggan = ['nama', 'no_hp', 'email', 'tanggal_lahir', 'catatan'];
const maksBarisImporPelanggan = 500;

const _alias = <String, String>{
  'nama': 'nama',
  'nama pelanggan': 'nama',
  'pelanggan': 'nama',
  'no_hp': 'no_hp',
  'no hp': 'no_hp',
  'nomor hp': 'no_hp',
  'hp': 'no_hp',
  'telepon': 'no_hp',
  'whatsapp': 'no_hp',
  'email': 'email',
  'tanggal_lahir': 'tanggal_lahir',
  'tanggal lahir': 'tanggal_lahir',
  'tgl lahir': 'tanggal_lahir',
  'ulang tahun': 'tanggal_lahir',
  'catatan': 'catatan',
  'keterangan': 'catatan',
};

/// Isi berkas template: judul kolom dan dua contoh baris yang jelas bukan data sungguhan.
/// Nomor HP ditulis dengan awalan 0; di Excel, set kolom no_hp sebagai Teks agar angka 0 tidak hilang.
String templatePelangganCsv() => '${kolomTemplatePelanggan.join(',')}\n'
    'Sari Contoh,081200000001,sari@contoh.id,1995-04-12,Suka kopi hitam\n'
    'Budi Contoh,081200000002,,,\n';

class BarisPelangganCsv {
  const BarisPelangganCsv({
    required this.nomorBaris,
    required this.nama,
    this.noHp,
    this.email,
    this.tanggalLahir,
    this.catatan,
    this.masalah,
  });

  /// Nomor baris di berkas (baris 1 = judul kolom).
  final int nomorBaris;
  final String nama;
  final String? noHp;
  final String? email;

  /// Format ISO "yyyy-MM-dd" (siap dikirim ke server).
  final String? tanggalLahir;
  final String? catatan;

  /// Alasan baris ini tidak dikirim (null = siap dikirim).
  final String? masalah;

  bool get valid => masalah == null;

  Map<String, dynamic> keJson() => {
        'nama': nama,
        if (noHp != null) 'no_hp': noHp,
        if (email != null) 'email': email,
        if (tanggalLahir != null) 'tanggal_lahir': tanggalLahir,
        if (catatan != null) 'catatan': catatan,
      };
}

class HasilBacaCsvPelanggan {
  const HasilBacaCsvPelanggan({required this.baris, this.galat});

  final List<BarisPelangganCsv> baris;

  /// Galat yang membuat seluruh berkas tidak bisa dipakai.
  final String? galat;

  Iterable<BarisPelangganCsv> get siap => baris.where((b) => b.valid);
  Iterable<BarisPelangganCsv> get bermasalah => baris.where((b) => !b.valid);
}

HasilBacaCsvPelanggan bacaCsvPelanggan(String teks) {
  final rows = bacaBarisCsv(teks);
  if (rows.isEmpty) return const HasilBacaCsvPelanggan(baris: [], galat: 'Berkas kosong');

  final judul = [for (final c in rows.first) _alias[c.trim().toLowerCase()] ?? ''];
  if (!judul.contains('nama')) {
    return const HasilBacaCsvPelanggan(
        baris: [], galat: 'Kolom "nama" tidak ditemukan. Pakai template dari aplikasi.');
  }
  if (rows.length - 1 > maksBarisImporPelanggan) {
    return HasilBacaCsvPelanggan(
      baris: const [],
      galat: 'Maksimal $maksBarisImporPelanggan pelanggan sekali impor (berkas berisi ${rows.length - 1}).',
    );
  }

  String? ambil(List<String> r, String kolom) {
    final i = judul.indexOf(kolom);
    if (i < 0 || i >= r.length) return null;
    final v = r[i].trim();
    return v.isEmpty ? null : v;
  }

  final hasil = <BarisPelangganCsv>[];
  for (var n = 1; n < rows.length; n++) {
    final r = rows[n];
    final nama = ambil(r, 'nama');
    final hpMentah = ambil(r, 'no_hp');
    final tglMentah = ambil(r, 'tanggal_lahir');
    final tgl = tglMentah == null ? null : parseTanggalLahir(tglMentah);

    String? masalah;
    if (nama == null) {
      masalah = 'Nama pelanggan kosong';
    } else if (tglMentah != null && tgl == null) {
      masalah = 'Tanggal lahir "$tglMentah" tidak dapat dibaca (pakai yyyy-mm-dd atau dd/mm/yyyy)';
    }
    hasil.add(BarisPelangganCsv(
      nomorBaris: n + 1,
      nama: nama ?? '',
      noHp: hpMentah == null ? null : normalisasiHp(hpMentah),
      email: ambil(r, 'email'),
      tanggalLahir: tgl,
      catatan: ambil(r, 'catatan'),
      masalah: masalah,
    ));
  }
  return HasilBacaCsvPelanggan(baris: hasil);
}

/// Sisakan angka dan pulihkan angka 0 di depan yang sering hilang saat Excel membaca kolom nomor
/// sebagai angka: "81234567890" -> "081234567890". Awalan 62 dan 0 dibiarkan.
String normalisasiHp(String teks) {
  final digit = teks.replaceAll(RegExp(r'\D'), '');
  if (digit.isEmpty) return teks.trim();
  if (digit.startsWith('62') || digit.startsWith('0')) return digit;
  if (digit.startsWith('8') && digit.length >= 9 && digit.length <= 12) return '0$digit';
  return digit;
}

/// "1995-04-12", "12/04/1995", "12-04-1995", "12.04.1995" -> "1995-04-12". Tidak terbaca atau
/// tanggal yang tidak ada (31 Februari) -> null.
String? parseTanggalLahir(String teks) {
  final s = teks.trim();
  int? t, b, y;
  final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s);
  final lokal = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(s);
  if (iso != null) {
    y = int.parse(iso.group(1)!);
    b = int.parse(iso.group(2)!);
    t = int.parse(iso.group(3)!);
  } else if (lokal != null) {
    t = int.parse(lokal.group(1)!);
    b = int.parse(lokal.group(2)!);
    y = int.parse(lokal.group(3)!);
  } else {
    return null;
  }
  if (y < 1900 || y > DateTime.now().year) return null;
  final tanggal = DateTime(y, b, t);
  if (tanggal.year != y || tanggal.month != b || tanggal.day != t) return null;
  String dua(int n) => n.toString().padLeft(2, '0');
  return '$y-${dua(b)}-${dua(t)}';
}
