import 'package:intl/intl.dart';

/// Jadwal shift mingguan dan pengajuan cuti (IMOGI no. 63). FUNGSI MURNI dan model data dari server.

const namaHariLengkap = {1: 'Senin', 2: 'Selasa', 3: 'Rabu', 4: 'Kamis', 5: 'Jumat', 6: 'Sabtu', 7: 'Minggu'};
const namaHariSingkat = {1: 'Sen', 2: 'Sel', 3: 'Rab', 4: 'Kam', 5: 'Jum', 6: 'Sab', 7: 'Min'};

const kodeShift = ['libur', 'pagi', 'siang'];

String labelShift(String? kode) => switch (kode) {
      'libur' => 'Libur',
      'pagi' => 'Pagi',
      'siang' => 'Siang',
      _ => 'Belum diatur',
    };

String labelJenisCuti(String kode) => switch (kode) {
      'cuti' => 'Cuti',
      'sakit' => 'Sakit',
      'izin' => 'Izin',
      _ => kode,
    };

String labelStatusCuti(String kode) => switch (kode) {
      'menunggu' => 'Menunggu',
      'disetujui' => 'Disetujui',
      'ditolak' => 'Ditolak',
      'dibatalkan' => 'Dibatalkan',
      _ => kode,
    };

class HariJadwal {
  const HariJadwal({required this.hari, required this.shift, this.jamMulai, this.jamSelesai});

  factory HariJadwal.dariJson(Map<String, dynamic> j) => HariJadwal(
        hari: (j['hari'] as num).toInt(),
        shift: j['shift'] as String,
        jamMulai: j['jam_mulai'] as String?,
        jamSelesai: j['jam_selesai'] as String?,
      );

  final int hari;
  final String shift;
  final String? jamMulai;
  final String? jamSelesai;

  /// "Pagi 07:00-15:00", "Libur".
  String get ringkas => shift == 'libur' || jamMulai == null ? labelShift(shift) : '${labelShift(shift)} $jamMulai-$jamSelesai';
}

class JadwalKaryawan {
  const JadwalKaryawan({required this.penggunaId, required this.nama, required this.hari});

  factory JadwalKaryawan.dariJson(Map<String, dynamic> j) => JadwalKaryawan(
        penggunaId: j['pengguna_id'] as String,
        nama: j['pengguna_nama'] as String,
        hari: [for (final h in (j['hari'] as List? ?? const [])) HariJadwal.dariJson(h as Map<String, dynamic>)],
      );

  final String penggunaId;
  final String nama;
  final List<HariJadwal> hari;

  /// Shift pada hari [nomor] (1 = Senin) atau null bila belum diatur.
  String? shiftPada(int nomor) {
    for (final h in hari) {
      if (h.hari == nomor) return h.shift;
    }
    return null;
  }

  int get jumlahHariKerja => hari.where((h) => h.shift != 'libur').length;
}

class JadwalHariIni {
  const JadwalHariIni({required this.shift, this.jamMulai, this.jamSelesai, this.cuti});

  factory JadwalHariIni.dariJson(Map<String, dynamic> j) => JadwalHariIni(
        shift: j['shift'] as String?,
        jamMulai: j['jam_mulai'] as String?,
        jamSelesai: j['jam_selesai'] as String?,
        cuti: j['cuti'] as String?,
      );

  final String? shift;
  final String? jamMulai;
  final String? jamSelesai;

  /// Jenis pengajuan yang disetujui dan mencakup hari ini (cuti/sakit/izin), bila ada.
  final String? cuti;

  String get teks {
    if (cuti != null) return '${labelJenisCuti(cuti!)} (disetujui)';
    if (shift == null) return 'Jadwal hari ini belum diatur';
    if (shift == 'libur') return 'Hari ini libur';
    return 'Hari ini shift ${labelShift(shift).toLowerCase()} $jamMulai-$jamSelesai';
  }
}

class PengajuanCutiItem {
  const PengajuanCutiItem({
    required this.id,
    required this.penggunaId,
    required this.penggunaNama,
    required this.jenis,
    required this.tanggalMulai,
    required this.tanggalSelesai,
    required this.status,
    this.alasan,
    this.catatanKeputusan,
  });

  factory PengajuanCutiItem.dariJson(Map<String, dynamic> j) => PengajuanCutiItem(
        id: j['id'] as String,
        penggunaId: j['pengguna_id'] as String,
        penggunaNama: j['pengguna_nama'] as String,
        jenis: j['jenis'] as String,
        tanggalMulai: DateTime.parse(j['tanggal_mulai'] as String),
        tanggalSelesai: DateTime.parse(j['tanggal_selesai'] as String),
        status: j['status'] as String,
        alasan: j['alasan'] as String?,
        catatanKeputusan: j['catatan_keputusan'] as String?,
      );

  final String id;
  final String penggunaId;
  final String penggunaNama;
  final String jenis;
  final DateTime tanggalMulai;
  final DateTime tanggalSelesai;
  final String status;
  final String? alasan;
  final String? catatanKeputusan;

  bool get menunggu => status == 'menunggu';

  int get jumlahHari => tanggalSelesai.difference(tanggalMulai).inDays + 1;

  String get rentangTeks {
    final f = DateFormat('d MMM yyyy', 'id_ID');
    return tanggalMulai == tanggalSelesai ? f.format(tanggalMulai) : '${f.format(tanggalMulai)} - ${f.format(tanggalSelesai)}';
  }
}

/// Isi untuk PUT /jadwal/{pengguna}: satu entri per hari yang sudah dipilih (tanpa "belum diatur").
List<Map<String, dynamic>> badanJadwal(Map<int, String> pilihan) => [
      for (final e in pilihan.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        if (kodeShift.contains(e.value)) {'hari': e.key, 'shift': e.value},
    ];
