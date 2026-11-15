// Model data dashboard Administrator (respons `/admin/dashboard/*`).

class PilihanJenisUsaha {
  const PilihanJenisUsaha({required this.kode, required this.nama});

  factory PilihanJenisUsaha.fromJson(Map<String, dynamic> j) =>
      PilihanJenisUsaha(kode: j['kode'] as String, nama: j['nama'] as String);

  final String kode;
  final String nama;
}

class ItemJumlah {
  const ItemJumlah({required this.kode, required this.nama, required this.jumlah});

  factory ItemJumlah.fromJson(Map<String, dynamic> j) =>
      ItemJumlah(kode: j['kode'] as String, nama: j['nama'] as String, jumlah: (j['jumlah'] as num).toInt());

  final String kode;
  final String nama;
  final int jumlah;
}

class RingkasanFitur {
  const RingkasanFitur({
    required this.sudah,
    required this.sedang,
    required this.belum,
    required this.tidakRelevan,
    required this.ujiHp,
    required this.total,
  });

  factory RingkasanFitur.fromJson(Map<String, dynamic> j) => RingkasanFitur(
        sudah: (j['sudah'] as num).toInt(),
        sedang: (j['sedang'] as num).toInt(),
        belum: (j['belum'] as num).toInt(),
        tidakRelevan: (j['tidak_relevan'] as num).toInt(),
        ujiHp: (j['uji_hp'] as num).toInt(),
        total: (j['total'] as num).toInt(),
      );

  final int sudah;
  final int sedang;
  final int belum;
  final int tidakRelevan;
  final int ujiHp;
  final int total;

  /// Fitur yang relevan (tidak termasuk "tidak relevan").
  int get relevan => total - tidakRelevan;

  /// Persentase fitur relevan yang sudah terpasang (0-100).
  int get persenSelesai => relevan == 0 ? 0 : (sudah * 100 / relevan).round();
}

class RingkasanTrial {
  const RingkasanTrial({
    required this.diatur,
    required this.durasiBulan,
    required this.dalamTrial,
    required this.berakhir,
    required this.hampirBerakhir,
    required this.batasNotifikasiHari,
  });

  factory RingkasanTrial.fromJson(Map<String, dynamic> j) => RingkasanTrial(
        diatur: j['aktif_diatur'] as bool,
        durasiBulan: (j['durasi_bulan'] as num).toInt(),
        dalamTrial: (j['usaha_dalam_trial'] as num).toInt(),
        berakhir: (j['usaha_trial_berakhir'] as num).toInt(),
        hampirBerakhir: (j['usaha_hampir_berakhir'] as num).toInt(),
        batasNotifikasiHari: (j['batas_notifikasi_hari'] as num).toInt(),
      );

  final bool diatur;
  final int durasiBulan;
  final int dalamTrial;
  final int berakhir;
  final int hampirBerakhir;
  final int batasNotifikasiHari;
}

class RingkasanAdmin {
  const RingkasanAdmin({
    required this.totalUsaha,
    required this.usahaBaru30Hari,
    required this.totalPengguna,
    required this.perPaket,
    required this.perJenisUsaha,
    required this.trial,
    required this.fitur,
  });

  factory RingkasanAdmin.fromJson(Map<String, dynamic> j) => RingkasanAdmin(
        totalUsaha: (j['total_usaha'] as num).toInt(),
        usahaBaru30Hari: (j['usaha_baru_30_hari'] as num).toInt(),
        totalPengguna: (j['total_pengguna'] as num).toInt(),
        perPaket: [for (final e in j['per_paket'] as List) ItemJumlah.fromJson(e as Map<String, dynamic>)],
        perJenisUsaha: [for (final e in j['per_jenis_usaha'] as List) ItemJumlah.fromJson(e as Map<String, dynamic>)],
        trial: RingkasanTrial.fromJson(j['trial'] as Map<String, dynamic>),
        fitur: RingkasanFitur.fromJson(j['fitur'] as Map<String, dynamic>),
      );

  final int totalUsaha;
  final int usahaBaru30Hari;
  final int totalPengguna;
  final List<ItemJumlah> perPaket;
  final List<ItemJumlah> perJenisUsaha;
  final RingkasanTrial trial;
  final RingkasanFitur fitur;
}

class UsahaAdmin {
  const UsahaAdmin({
    required this.id,
    required this.nama,
    required this.jenisUsahaNama,
    required this.pemilikNama,
    required this.email,
    required this.noHp,
    required this.terdaftar,
    required this.usiaHari,
    required this.paket,
    required this.paketLangganan,
    required this.statusLangganan,
    required this.trialAktif,
    required this.trialBerakhir,
    required this.trialHariTersisa,
    required this.jumlahPengguna,
    required this.jumlahOutlet,
    required this.terakhirSync,
  });

  factory UsahaAdmin.fromJson(Map<String, dynamic> j) => UsahaAdmin(
        id: j['id'] as String,
        nama: j['nama'] as String,
        jenisUsahaNama: j['jenis_usaha_nama'] as String?,
        pemilikNama: j['pemilik_nama'] as String?,
        email: j['email'] as String?,
        noHp: j['no_hp'] as String?,
        terdaftar: DateTime.parse(j['terdaftar'] as String).toLocal(),
        usiaHari: (j['usia_hari'] as num).toInt(),
        paket: j['paket'] as String,
        paketLangganan: j['paket_langganan'] as String,
        statusLangganan: j['status_langganan'] as String,
        trialAktif: j['trial_aktif'] as bool?,
        trialBerakhir: j['trial_berakhir'] == null ? null : DateTime.parse(j['trial_berakhir'] as String).toLocal(),
        trialHariTersisa: (j['trial_hari_tersisa'] as num?)?.toInt(),
        jumlahPengguna: (j['jumlah_pengguna'] as num).toInt(),
        jumlahOutlet: (j['jumlah_outlet'] as num).toInt(),
        terakhirSync: j['terakhir_sync'] == null ? null : DateTime.parse(j['terakhir_sync'] as String).toLocal(),
      );

  final String id;
  final String nama;
  final String? jenisUsahaNama;
  final String? pemilikNama;
  final String? email;
  final String? noHp;
  final DateTime terdaftar;
  final int usiaHari;
  final String paket;
  final String paketLangganan;
  final String statusLangganan;
  final bool? trialAktif;
  final DateTime? trialBerakhir;
  final int? trialHariTersisa;
  final int jumlahPengguna;
  final int jumlahOutlet;
  final DateTime? terakhirSync;
}

/// Status pengembangan satu fitur IMOGI.
enum StatusFitur {
  sudah('sudah', 'Sudah'),
  sedang('sedang', 'Sedang'),
  belum('belum', 'Belum'),
  tidakRelevan('tidak_relevan', 'Tidak relevan');

  const StatusFitur(this.kode, this.label);

  final String kode;
  final String label;

  static StatusFitur dari(String kode) =>
      StatusFitur.values.firstWhere((s) => s.kode == kode, orElse: () => StatusFitur.belum);
}

class FiturAdmin {
  const FiturAdmin({
    required this.nomor,
    required this.nama,
    required this.modul,
    required this.status,
    required this.kebutuhan,
    required this.ujiHp,
    required this.catatan,
  });

  factory FiturAdmin.fromJson(Map<String, dynamic> j) => FiturAdmin(
        nomor: (j['nomor'] as num).toInt(),
        nama: j['nama'] as String,
        modul: j['modul'] as String,
        status: StatusFitur.dari(j['status'] as String),
        kebutuhan: j['kebutuhan'] as String?,
        ujiHp: j['uji_hp'] as bool,
        catatan: j['catatan'] as String?,
      );

  final int nomor;
  final String nama;
  final String modul;
  final StatusFitur status;

  /// inti / opsional / na; null bila tidak ada filter jenis usaha.
  final String? kebutuhan;
  final bool ujiHp;
  final String? catatan;
}

/// Kelompokkan fitur per modul beserta hitungan status (untuk "peta modul").
class RingkasanModul {
  const RingkasanModul({required this.modul, required this.fitur});

  final String modul;
  final List<FiturAdmin> fitur;

  int hitung(StatusFitur s) => fitur.where((f) => f.status == s).length;

  /// Modul yang belum punya satu pun fitur "sudah" di antara yang relevan.
  bool get belumAda {
    final relevan = fitur.where((f) => f.status != StatusFitur.tidakRelevan);
    return relevan.isNotEmpty && relevan.every((f) => f.status == StatusFitur.belum);
  }
}

List<RingkasanModul> kelompokkanPerModul(List<FiturAdmin> daftar) {
  final peta = <String, List<FiturAdmin>>{};
  for (final f in daftar) {
    peta.putIfAbsent(f.modul, () => []).add(f);
  }
  return [for (final e in peta.entries) RingkasanModul(modul: e.key, fitur: e.value)];
}
