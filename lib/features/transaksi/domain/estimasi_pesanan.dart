import 'package:intl/intl.dart';

import '../data/local/tables/transaksi_table.dart' show StatusPesanan;

/// Estimasi selesai pesanan (IMOGI no. 26): waktu pesanan dibuat + lama pengerjaan bawaan outlet.
/// FUNGSI MURNI supaya bisa dites tanpa database atau jam sungguhan.
///
/// Hanya relevan selama pesanan belum siap (baru/diproses). [menit] <= 0 = fitur dimatikan.
/// Mengembalikan null bila tidak ada yang perlu ditampilkan.
String? labelEstimasiPesanan({
  required int tanggalMs,
  required int menit,
  required StatusPesanan status,
  required DateTime sekarang,
}) {
  if (menit <= 0) return null;
  if (status != StatusPesanan.baru && status != StatusPesanan.diproses)
    return null;

  final selesai = DateTime.fromMillisecondsSinceEpoch(
    tanggalMs,
    isUtc: true,
  ).toLocal().add(Duration(minutes: menit));
  if (sekarang.isAfter(selesai)) {
    final telat = sekarang.difference(selesai).inMinutes;
    return telat < 1 ? 'Estimasi lewat' : 'Terlambat $telat mnt';
  }
  return 'Estimasi selesai ${DateFormat('HH:mm').format(selesai)}';
}

/// Apakah label ini menandai keterlambatan (untuk pewarnaan).
bool estimasiTerlambat(String label) =>
    label.startsWith('Terlambat') || label == 'Estimasi lewat';
