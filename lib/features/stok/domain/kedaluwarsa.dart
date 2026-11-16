/// Pengingat kedaluwarsa produk (IMOGI no. 50). FUNGSI MURNI.

enum StatusKedaluwarsa { sudahLewat, segera, aman }

/// Selisih hari kalender (menurut zona waktu perangkat) dari [sekarang] ke tanggal kedaluwarsa.
/// Negatif = sudah lewat. [tanggalKedaluwarsaMs] adalah epoch ms UTC tengah malam (konvensi kolom `date`).
int sisaHariKedaluwarsa(int tanggalKedaluwarsaMs, DateTime sekarang) {
  final t = DateTime.fromMillisecondsSinceEpoch(tanggalKedaluwarsaMs, isUtc: true);
  final tanggal = DateTime.utc(t.year, t.month, t.day);
  final hariIni = DateTime.utc(sekarang.year, sekarang.month, sekarang.day);
  return tanggal.difference(hariIni).inDays;
}

/// Sudah lewat bila tanggal kedaluwarsa SEBELUM hari ini; "segera" bila sisa hari <= [ingatkanHari]
/// (termasuk hari ini); selain itu aman.
StatusKedaluwarsa statusKedaluwarsa({
  required int tanggalKedaluwarsaMs,
  required int ingatkanHari,
  required DateTime sekarang,
}) {
  final sisa = sisaHariKedaluwarsa(tanggalKedaluwarsaMs, sekarang);
  if (sisa < 0) return StatusKedaluwarsa.sudahLewat;
  if (sisa <= ingatkanHari) return StatusKedaluwarsa.segera;
  return StatusKedaluwarsa.aman;
}

String labelSisaHari(int sisaHari) {
  if (sisaHari < 0) return 'Lewat ${-sisaHari} hari';
  if (sisaHari == 0) return 'Kedaluwarsa hari ini';
  return '$sisaHari hari lagi';
}
