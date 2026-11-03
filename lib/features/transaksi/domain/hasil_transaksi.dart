import '../../promo/domain/rincian_pajak.dart';
import 'item_keranjang.dart';

/// Snapshot hasil checkout untuk ditampilkan di halaman struk.
class HasilTransaksi {
  const HasilTransaksi({
    required this.id,
    required this.nomorStruk,
    required this.tanggal,
    required this.items,
    required this.subtotal,
    this.namaPromo,
    this.totalDiskon = 0,
    required this.rincianPajak,
    required this.totalPajak,
    required this.total,
    required this.totalBayar,
    required this.kembalian,
    this.statusBayar = 'lunas',
    this.sisaTagihan = 0,
    this.jatuhTempo,
    this.produkStokMenipis = const [],
  });

  final String id;
  final String nomorStruk;
  final int tanggal;
  final List<ItemKeranjang> items;
  final int subtotal;
  final String? namaPromo;
  final int totalDiskon;
  final List<RincianPajak> rincianPajak;
  final int totalPajak;
  final int total;
  final int totalBayar;
  final int kembalian;
  // Kasbon (tahap 3b-1) - 'lunas' | 'sebagian' | 'belumBayar'.
  final String statusBayar;
  final int sisaTagihan;
  final int? jatuhTempo;
  // Nama produk yang saldonya jadi <= batas minimum GARA-GARA transaksi ini
  // (lihat TransaksiRepository.checkout) - dipakai StrukPage utk nampilkan
  // toast pengingat tepat setelah checkout, bukan cuma badge pasif di
  // halaman Stok yang baru kelihatan kalau kasir sempat buka halaman itu.
  final List<String> produkStokMenipis;
}
