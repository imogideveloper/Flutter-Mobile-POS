import '../data/local/tables/transaksi_table.dart' show StatusPesanan;

/// Alur tahap status pesanan menurut dokumen IMOGI (Panduan Menu Pengaturan,
/// bagian 4.2 "Alur status", fitur no. 26). Tahap mengikuti jenis usaha dan
/// tidak bisa diubah pemilik:
/// - Kafe, restoran, roti, minuman, food court, bahan segar:
///   Baru, Diproses, Siap, (Diantar), Selesai
/// - Katering: Dipesan, Dimasak, Siap kirim, Dikirim, Selesai
///
/// FUNGSI MURNI tanpa database, supaya bisa dites langsung. Tahap "Diantar"
/// pada alur standar hanya dipakai untuk pesanan antar ([termasukDiantar]).
class TahapStatus {
  const TahapStatus(this.kode, this.label, {this.labelAksi});

  final StatusPesanan kode;

  /// Nama tahap yang tampil (mis. "Dimasak").
  final String label;

  /// Teks tombol untuk MASUK ke tahap ini (mis. "Mulai dimasak").
  final String? labelAksi;
}

class AlurStatusPesanan {
  const AlurStatusPesanan._(this.tahap);

  final List<TahapStatus> tahap;

  /// Kode jenis usaha IMOGI untuk Katering.
  static const kodeKatering = 'CAT';

  static const _standar = [
    TahapStatus(StatusPesanan.baru, 'Baru'),
    TahapStatus(StatusPesanan.diproses, 'Diproses', labelAksi: 'Mulai proses'),
    TahapStatus(StatusPesanan.siap, 'Siap', labelAksi: 'Tandai siap'),
    TahapStatus(StatusPesanan.selesai, 'Selesai', labelAksi: 'Selesaikan'),
  ];

  static const _standarAntar = [
    TahapStatus(StatusPesanan.baru, 'Baru'),
    TahapStatus(StatusPesanan.diproses, 'Diproses', labelAksi: 'Mulai proses'),
    TahapStatus(StatusPesanan.siap, 'Siap', labelAksi: 'Tandai siap'),
    TahapStatus(StatusPesanan.diantar, 'Diantar', labelAksi: 'Tandai diantar'),
    TahapStatus(StatusPesanan.selesai, 'Selesai', labelAksi: 'Selesaikan'),
  ];

  static const _katering = [
    TahapStatus(StatusPesanan.baru, 'Dipesan'),
    TahapStatus(StatusPesanan.diproses, 'Dimasak', labelAksi: 'Mulai dimasak'),
    TahapStatus(StatusPesanan.siap, 'Siap kirim', labelAksi: 'Tandai siap kirim'),
    TahapStatus(StatusPesanan.diantar, 'Dikirim', labelAksi: 'Tandai dikirim'),
    TahapStatus(StatusPesanan.selesai, 'Selesai', labelAksi: 'Selesaikan'),
  ];

  /// Alur untuk jenis usaha ([kodeJenisUsaha] = kode IMOGI, mis. 'CAF').
  factory AlurStatusPesanan.untuk(String? kodeJenisUsaha, {bool termasukDiantar = false}) {
    if (kodeJenisUsaha?.toUpperCase() == kodeKatering) return const AlurStatusPesanan._(_katering);
    return AlurStatusPesanan._(termasukDiantar ? _standarAntar : _standar);
  }

  /// Status awal pesanan baru.
  StatusPesanan get awal => tahap.first.kode;

  static bool _akhir(StatusPesanan s) =>
      s == StatusPesanan.selesai || s == StatusPesanan.diambil || s == StatusPesanan.dibatalkan;

  /// Pesanan sudah tuntas (tidak perlu ditindaklanjuti lagi).
  bool sudahSelesai(StatusPesanan s) => _akhir(s);

  /// Tahap setelah [sekarang], atau null bila sudah di tahap akhir atau tidak
  /// dikenal. Data lama berstatus `diambil` dianggap sudah selesai.
  TahapStatus? berikutnya(StatusPesanan sekarang) {
    if (_akhir(sekarang)) return null;
    final i = tahap.indexWhere((t) => t.kode == sekarang);
    if (i < 0 || i + 1 >= tahap.length) return null;
    return tahap[i + 1];
  }

  /// Nama tahap untuk ditampilkan; status di luar alur (data lama,
  /// dibatalkan) tetap punya nama yang masuk akal.
  String label(StatusPesanan s) {
    for (final t in tahap) {
      if (t.kode == s) return t.label;
    }
    return switch (s) {
      StatusPesanan.diambil => 'Selesai',
      StatusPesanan.dibatalkan => 'Dibatalkan',
      StatusPesanan.diantar => 'Diantar',
      _ => s.name,
    };
  }
}
