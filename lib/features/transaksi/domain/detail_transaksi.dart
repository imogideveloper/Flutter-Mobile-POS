import '../../promo/domain/rincian_pajak.dart';
import '../data/local/tables/transaksi_table.dart' show TransaksiStatus;
import 'item_keranjang.dart';

/// Detail lengkap satu transaksi lama, dibangun dari beberapa query DAO
/// (item, pajak, promo, pembayaran) - dipakai halaman Riwayat > detail,
/// termasuk alur void.
class DetailTransaksi {
  const DetailTransaksi({
    required this.id,
    required this.nomorStruk,
    required this.tanggal,
    required this.status,
    required this.items,
    required this.subtotal,
    this.namaPromo,
    this.totalDiskon = 0,
    required this.rincianPajak,
    required this.totalPajak,
    required this.total,
    required this.totalBayar,
    required this.kembalian,
    this.metodeBayarId,
    this.jumlahPembayaran = 1,
    this.namaPelanggan,
    this.alasanVoid,
    this.snapshotStruk,
    this.nomorAntrean,
  });

  final String id;
  final String nomorStruk;
  final int tanggal;
  final TransaksiStatus status;
  final List<ItemKeranjang> items;
  final int subtotal;
  final String? namaPromo;
  final int totalDiskon;
  final List<RincianPajak> rincianPajak;
  final int totalPajak;
  final int total;
  final int totalBayar;
  final int kembalian;
  final String? metodeBayarId;
  final int jumlahPembayaran;
  final String? namaPelanggan;
  final String? alasanVoid;
  // Temuan A.2 (tahap 5) - JSON (lihat lib/core/struk/struk_snapshot.dart),
  // null = belum pernah tersimpan (transaksi lama/client lama) - cetak
  // ulang utk kasus itu turun ke rekonstruksi dari data saat ini
  // (keterbatasan lama, lihat docs/aturan_harga.md).
  final String? snapshotStruk;
  final String? nomorAntrean;
}
