import 'dart:convert';

import '../../promo/domain/rincian_pajak.dart';
import '../data/local/tables/transaksi_table.dart' show TransaksiStatus, transaksiStatusPostgresValue;
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
    this.dariServer = false,
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

  /// true = transaksi tidak ada di database HP ini (dibuat di HP lain / sebelum masuk ulang) dan dibangun dari
  /// jawaban server; hanya untuk dilihat dan dicetak ulang, void dan refund dari layar ini tidak tersedia.
  final bool dariServer;
}

/// Bangun [DetailTransaksi] dari `GET /transaksi/{id}` untuk transaksi yang tidak tersimpan di HP ini. Rincian item
/// diambil dari `snapshot_struk` (server tidak menyimpan baris item di respons ini); tanpa snapshot daftar item kosong.
DetailTransaksi detailTransaksiDariServer(Map<String, dynamic> resp, {String? namaPelanggan}) {
  int rupiah(Object? v) => v == null ? 0 : double.parse(v.toString()).round();

  final snapshot = resp['snapshot_struk'];
  final data = snapshot is Map<String, dynamic> ? snapshot['data'] as Map<String, dynamic>? : null;

  final items = <ItemKeranjang>[
    for (final i in (data?['items'] as List? ?? const []))
      ItemKeranjang(
        produkId: '',
        namaProduk: (i as Map<String, dynamic>)['namaProduk'] as String,
        hargaSatuan: (i['hargaSatuan'] as num).toInt(),
        qty: (i['qty'] as num).toDouble(),
        lacakStok: false,
        modifiers: [for (final m in (i['modifiers'] as List? ?? const [])) ModifierPilihan(nama: m as String)],
      ),
  ];
  final pajak = [
    for (final r in (data?['rincianPajak'] as List? ?? const []))
      RincianPajak(
        nama: (r as Map<String, dynamic>)['nama'] as String,
        persen: (r['persen'] as num).toDouble(),
        jumlah: (r['jumlah'] as num).toInt(),
        termasukHarga: r['termasukHarga'] as bool,
      ),
  ];

  return DetailTransaksi(
    id: resp['id'] as String,
    nomorStruk: resp['nomor_struk'] as String,
    nomorAntrean: resp['nomor_antrean'] as String?,
    tanggal: DateTime.parse(resp['tanggal'] as String).toUtc().millisecondsSinceEpoch,
    status: transaksiStatusPostgresValue.entries
        .firstWhere((e) => e.value == resp['status'], orElse: () => transaksiStatusPostgresValue.entries.first)
        .key,
    items: items,
    subtotal: rupiah(resp['subtotal']),
    namaPromo: data?['namaPromo'] as String?,
    totalDiskon: rupiah(resp['total_diskon']),
    rincianPajak: pajak,
    totalPajak: rupiah(resp['total_pajak']),
    total: rupiah(resp['total']),
    totalBayar: rupiah(resp['total_bayar']),
    kembalian: rupiah(resp['kembalian']),
    namaPelanggan: namaPelanggan ?? data?['namaPelanggan'] as String?,
    alasanVoid: resp['alasan_void'] as String?,
    snapshotStruk: snapshot == null ? null : jsonEncode(snapshot),
    dariServer: true,
  );
}
