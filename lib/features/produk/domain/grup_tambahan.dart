/// Grup varian/tambahan produk (dokumen IMOGI no. 42), mis. "Ukuran",
/// "Level gula", "Topping". Aturan pilih: minimal [minPilih] dan maksimal
/// [maksPilih] opsi. minPilih > 0 berarti wajib dipilih.
class GrupTambahan {
  const GrupTambahan({
    required this.id,
    required this.nama,
    required this.minPilih,
    required this.maksPilih,
    required this.opsi,
  });

  final String id;
  final String nama;
  final int minPilih;
  final int maksPilih;
  final List<OpsiTambahan> opsi;

  bool get wajib => minPilih > 0;
  bool get pilihTunggal => maksPilih == 1;

  /// Pesan galat bila [jumlahDipilih] melanggar aturan, null bila sah.
  String? validasi(int jumlahDipilih) {
    if (jumlahDipilih < minPilih) {
      return minPilih == 1 ? 'Pilih salah satu $nama' : 'Pilih minimal $minPilih untuk $nama';
    }
    if (maksPilih > 0 && jumlahDipilih > maksPilih) return 'Maksimal $maksPilih untuk $nama';
    return null;
  }
}

class OpsiTambahan {
  const OpsiTambahan({required this.id, required this.nama, required this.harga, this.aktif = true});

  final String id;
  final String nama;
  final int harga;
  final bool aktif;
}
