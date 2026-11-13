/// Tanggal lahir pelanggan dan ulang tahun (IMOGI no. 56, Promo ulang tahun). FUNGSI MURNI.
///
/// Di HP, tanggal lahir disimpan sebagai bilangan bulat yyyymmdd (mis. 19950412) di kolom
/// `pelanggan.tanggal_lahir`. Bentuk ini tidak terpengaruh zona waktu, sedangkan epoch milidetik
/// bisa bergeser sehari. Hanya bulan dan tanggal yang dipakai untuk menilai ulang tahun.
library;

/// "1995-04-12" -> 19950412. Tidak terbaca atau tanggal fiktif -> null.
int? tanggalLahirDariIso(String? iso) {
  if (iso == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!), b = int.parse(m.group(2)!), t = int.parse(m.group(3)!);
  final d = DateTime(y, b, t);
  if (d.year != y || d.month != b || d.day != t) return null;
  return y * 10000 + b * 100 + t;
}

/// 19950412 -> "1995-04-12".
String? tanggalLahirKeIso(int? nilai) {
  if (nilai == null) return null;
  final y = nilai ~/ 10000, b = (nilai ~/ 100) % 100, t = nilai % 100;
  String dua(int n) => n.toString().padLeft(2, '0');
  return '${y.toString().padLeft(4, '0')}-${dua(b)}-${dua(t)}';
}

DateTime? tanggalLahirKeDateTime(int? nilai) {
  if (nilai == null) return null;
  return DateTime(nilai ~/ 10000, (nilai ~/ 100) % 100, nilai % 100);
}

bool _kabisat(int tahun) => (tahun % 4 == 0 && tahun % 100 != 0) || tahun % 400 == 0;

/// Bulan dan tanggal perayaan pada tahun [tahun]. Yang lahir 29 Februari dirayakan 28 Februari di
/// tahun yang bukan kabisat.
({int bulan, int tanggal}) _perayaan(int nilai, int tahun) {
  final b = (nilai ~/ 100) % 100, t = nilai % 100;
  if (b == 2 && t == 29 && !_kabisat(tahun)) return (bulan: 2, tanggal: 28);
  return (bulan: b, tanggal: t);
}

/// Apakah [sekarang] adalah hari ulang tahun. Tanggal lahir kosong -> false.
bool ulangTahunHariIni(int? tanggalLahir, DateTime sekarang) {
  if (tanggalLahir == null) return false;
  final p = _perayaan(tanggalLahir, sekarang.year);
  return p.bulan == sekarang.month && p.tanggal == sekarang.day;
}

/// Apakah ulang tahun jatuh pada bulan yang sama dengan [sekarang].
bool ulangTahunBulanIni(int? tanggalLahir, DateTime sekarang) =>
    tanggalLahir != null && (tanggalLahir ~/ 100) % 100 == sekarang.month;

/// Usia yang genap pada ulang tahun tahun ini (untuk teks "berulang tahun ke-31").
int? usiaTahunIni(int? tanggalLahir, DateTime sekarang) =>
    tanggalLahir == null ? null : sekarang.year - tanggalLahir ~/ 10000;
