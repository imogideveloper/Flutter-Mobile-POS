import 'package:intl/intl.dart';

/// Data absensi dari server (IMOGI no. 62). Waktu diterima sebagai ISO-8601 dan ditampilkan lokal.
class CatatanAbsensi {
  const CatatanAbsensi({
    required this.id,
    required this.penggunaNama,
    required this.jamMasuk,
    required this.jamKeluar,
    required this.durasiMenit,
    this.catatan,
  });

  factory CatatanAbsensi.dariJson(Map<String, dynamic> j) => CatatanAbsensi(
        id: j['id'] as String,
        penggunaNama: j['pengguna_nama'] as String,
        jamMasuk: DateTime.parse(j['jam_masuk'] as String).toLocal(),
        jamKeluar: j['jam_keluar'] == null ? null : DateTime.parse(j['jam_keluar'] as String).toLocal(),
        durasiMenit: (j['durasi_menit'] as num?)?.toInt(),
        catatan: j['catatan'] as String?,
      );

  final String id;
  final String penggunaNama;
  final DateTime jamMasuk;
  final DateTime? jamKeluar;
  final int? durasiMenit;
  final String? catatan;

  bool get masihMasuk => jamKeluar == null;
}

class RekapAbsensi {
  const RekapAbsensi({
    required this.penggunaNama,
    required this.jumlahHari,
    required this.totalMenit,
    required this.masihMasuk,
  });

  factory RekapAbsensi.dariJson(Map<String, dynamic> j) => RekapAbsensi(
        penggunaNama: j['pengguna_nama'] as String,
        jumlahHari: (j['jumlah_hari'] as num).toInt(),
        totalMenit: (j['total_menit'] as num).toInt(),
        masihMasuk: j['masih_masuk'] as bool,
      );

  final String penggunaNama;
  final int jumlahHari;
  final int totalMenit;
  final bool masihMasuk;
}

class DaftarAbsensi {
  const DaftarAbsensi({required this.rekap, required this.item});

  factory DaftarAbsensi.dariJson(Map<String, dynamic> j) => DaftarAbsensi(
        rekap: [
          for (final r in (j['rekap'] as List? ?? const [])) RekapAbsensi.dariJson(r as Map<String, dynamic>),
        ],
        item: [
          for (final i in (j['item'] as List? ?? const [])) CatatanAbsensi.dariJson(i as Map<String, dynamic>),
        ],
      );

  final List<RekapAbsensi> rekap;
  final List<CatatanAbsensi> item;
}

/// 135 -> "2 jam 15 mnt", 45 -> "45 mnt", 120 -> "2 jam", 0 -> "0 mnt".
String formatDurasi(int menit) {
  final jam = menit ~/ 60;
  final sisa = menit % 60;
  if (jam == 0) return '$sisa mnt';
  return sisa == 0 ? '$jam jam' : '$jam jam $sisa mnt';
}

String formatJam(DateTime t) => DateFormat('HH:mm').format(t);

/// Offset zona waktu perangkat dari UTC dalam menit (WIB = 420), untuk parameter `tz_menit`.
int offsetZonaMenit(DateTime sekarang) => sekarang.timeZoneOffset.inMinutes;
