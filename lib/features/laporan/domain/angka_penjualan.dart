import '../../../core/database/app_database.dart' show ItemTransaksiRow, TransaksiRow;

/// Tiga angka penjualan yang harus dibedakan (keputusan sementara AT1, docs/perlu_konfirmasi.md):
/// - [penjualanBersih]: penjualan tanpa pajak dan service (setelah diskon dan refund). Sama dengan
///   "Penjualan bersih" di Laba rugi.
/// - [pajakService]: pajak (PB1/PPN) dan service charge yang dipungut dari pelanggan.
/// - [totalPenerimaan]: semua uang yang diterima dari pelanggan (bersih + pajak + service + pembulatan),
///   setelah refund. Dipakai untuk mencocokkan uang di laci dan metode bayar.
class AngkaPenjualan {
  const AngkaPenjualan({this.penjualanBersih = 0, this.pajakService = 0, this.totalPenerimaan = 0});

  final int penjualanBersih;
  final int pajakService;
  final int totalPenerimaan;

  AngkaPenjualan operator +(AngkaPenjualan lain) => AngkaPenjualan(
        penjualanBersih: penjualanBersih + lain.penjualanBersih,
        pajakService: pajakService + lain.pajakService,
        totalPenerimaan: totalPenerimaan + lain.totalPenerimaan,
      );
}

/// Angka satu transaksi setelah dikurangi [refund] (total yang sudah dikembalikan ke pelanggan, Rupiah).
/// Refund dibagi proporsional ke penjualan bersih dan pajak/service, sama dengan cara server membaginya
/// untuk refund sebagian. Refund 0 = tidak ada pengurangan. FUNGSI MURNI.
AngkaPenjualan angkaPenjualanTransaksi(TransaksiRow t, {int refund = 0}) {
  final total = t.total;
  final bersihPenuh = total - t.totalPajak - t.pembulatan;
  final dikembalikan = refund.clamp(0, total < 0 ? 0 : total);
  final sisa = total <= 0 ? 0.0 : 1 - dikembalikan / total;
  return AngkaPenjualan(
    penjualanBersih: (bersihPenuh * sisa).round(),
    pajakService: (t.totalPajak * sisa).round(),
    totalPenerimaan: total - dikembalikan,
  );
}

/// Angka per transaksi untuk [daftar]; [refundPerTransaksi] = total refund per id transaksi (boleh kosong).
Map<String, AngkaPenjualan> angkaPenjualanPerTransaksi(
  Iterable<TransaksiRow> daftar,
  Map<String, int> refundPerTransaksi,
) =>
    {for (final t in daftar) t.id: angkaPenjualanTransaksi(t, refund: refundPerTransaksi[t.id] ?? 0)};

/// Refund satu item lokal: [qty] yang dikembalikan ke pelanggan, [qtyKembaliStok] di antaranya yang barangnya
/// dikembalikan ke stok (hanya itu yang HPP-nya dibalik).
class RefundItem {
  const RefundItem({this.qty = 0, this.qtyKembaliStok = 0});

  final double qty;
  final double qtyKembaliStok;
}

/// Satu baris item yang masih terjual setelah refund. [qty] = yang masih terjual, [qtyHpp] = qty yang HPP-nya
/// tetap ditanggung (barang yang direfund tanpa kembali ke stok tetap jadi biaya).
class ItemTerjual {
  const ItemTerjual({required this.item, required this.qty, required this.qtyHpp});

  final ItemTransaksiRow item;
  final double qty;
  final double qtyHpp;

  /// Subtotal baris dikurangi proporsional sesuai qty yang masih terjual.
  int get subtotal => item.qty <= 0 ? 0 : (item.subtotal * qty / item.qty).round();

  /// Laba kotor baris: harga x qty terjual dikurangi HPP x qty yang HPP-nya masih ditanggung.
  int get labaKotor => (item.hargaSatuan * qty - item.hppSatuan * qtyHpp).round();

  int get hpp => (item.hppSatuan * qtyHpp).round();
}

/// Item setelah dikurangi refund; [refundPerItem] berkunci id item lokal (boleh kosong). FUNGSI MURNI.
List<ItemTerjual> itemTerjual(Iterable<ItemTransaksiRow> items, Map<String, RefundItem> refundPerItem) => [
      for (final i in items)
        ItemTerjual(
          item: i,
          qty: (i.qty - (refundPerItem[i.id]?.qty ?? 0)).clamp(0.0, i.qty < 0 ? 0.0 : i.qty),
          qtyHpp: (i.qty - (refundPerItem[i.id]?.qtyKembaliStok ?? 0)).clamp(0.0, i.qty < 0 ? 0.0 : i.qty),
        ),
    ];

/// Menjumlahkan angka semua transaksi di [perTransaksi].
AngkaPenjualan jumlahkanAngkaPenjualan(Iterable<AngkaPenjualan> perTransaksi) =>
    perTransaksi.fold(const AngkaPenjualan(), (a, b) => a + b);
