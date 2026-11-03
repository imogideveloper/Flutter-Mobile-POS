/// Mesin hitung nominal refund proporsional - cermin 1:1 dari
/// `backend/app/services/harga/refund_kalkulator.py`. Aturan lengkap di
/// `docs/aturan_harga.md` bagian "Refund proporsional (F3.D)" - UBAH
/// DOKUMEN ITU DULU kalau mau ubah aturan, lalu samakan kedua modul ini.
///
/// Murni (tidak sentuh DB/network) - dites lewat fixture JSON bersama di
/// `shared/fixtures/refund/` (dibaca juga oleh pytest).
///
/// CATATAN: refund SAAT INI selalu online lewat endpoint backend (lihat
/// aturan_harga.md "Keterbatasan") - modul ini BELUM dipakai oleh alur
/// refund Flutter sungguhan manapun, murni supaya kalkulasinya tetap
/// tervalidasi identik dgn backend lewat fixture bersama.
library;

int bulatkan(num nilai) => nilai.round();

/// Bagi `total` (rupiah bulat) proporsional ke `weights` - metode largest
/// remainder (Hare-Niemeyer): tiap bagian di-floor dulu, sisa rupiah yang
/// belum terbagi diberikan satu-satu ke bagian dengan sisa desimal
/// terbesar (dasi dipecah by urutan index, deterministik). Hasil SELALU
/// sum persis = total. Weight 0 di semua baris -> semua bagian 0.
List<int> splitLargestRemainder(int total, List<int> weights) {
  final n = weights.length;
  if (n == 0 || total == 0) return List.filled(n, 0);
  final totalWeight = weights.fold<int>(0, (a, b) => a + b);
  if (totalWeight == 0) return List.filled(n, 0);

  final mentah = [for (final w in weights) total * w / totalWeight];
  final lantai = [for (final m in mentah) m.floor()];
  final sisaRupiah = total - lantai.fold<int>(0, (a, b) => a + b);

  final urutanSisa = List.generate(n, (i) => i)
    ..sort((a, b) {
      final fracA = mentah[a] - lantai[a];
      final fracB = mentah[b] - lantai[b];
      final cmp = fracB.compareTo(fracA);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

  final hasil = [...lantai];
  for (var i = 0; i < sisaRupiah; i++) {
    hasil[urutanSisa[i]] += 1;
  }
  return hasil;
}

class ItemRefundInput {
  const ItemRefundInput({
    required this.itemTransaksiId,
    required this.qty,
    required this.hargaSatuan,
    required this.diskon,
    required this.subtotal,
  });

  final String itemTransaksiId;
  final num qty;
  final int hargaSatuan;
  final int diskon; // diskon per-produk baris ini (promo cakupan='produk')
  final int subtotal; // dasar pembagian proporsional (sama basis dgn kalkulator.dart)
}

class RefundLineInput {
  const RefundLineInput({required this.itemTransaksiId, required this.qtyRefund});

  final String itemTransaksiId;
  final num qtyRefund;
}

class HasilRefundLine {
  const HasilRefundLine({required this.itemTransaksiId, required this.jumlah});

  final String itemTransaksiId;
  final int jumlah;
}

/// `items` = SEMUA baris item_transaksi dari transaksi asal (basis
/// alokasi, bukan cuma yang direfund) - `refundLines` = baris yang
/// BENAR-BENAR direfund sekarang (bisa subset, qtyRefund <= qty).
List<HasilRefundLine> hitungRefundProporsional({
  required List<ItemRefundInput> items,
  required int diskonTransaksiTotal,
  required int pajakServiceTotal,
  required List<RefundLineInput> refundLines,
}) {
  final weights = [for (final i in items) i.subtotal];
  final alokasiDiskon = splitLargestRemainder(diskonTransaksiTotal, weights);
  final alokasiPajak = splitLargestRemainder(pajakServiceTotal, weights);

  final petaDiskon = <String, int>{};
  final petaPajak = <String, int>{};
  final itemById = <String, ItemRefundInput>{};
  for (var i = 0; i < items.length; i++) {
    petaDiskon[items[i].itemTransaksiId] = alokasiDiskon[i];
    petaPajak[items[i].itemTransaksiId] = alokasiPajak[i];
    itemById[items[i].itemTransaksiId] = items[i];
  }

  return [
    for (final line in refundLines)
      () {
        final item = itemById[line.itemTransaksiId]!;
        final fraksi = item.qty == 0 ? 0 : line.qtyRefund / item.qty;
        final jumlah = bulatkan(
          line.qtyRefund * item.hargaSatuan -
              item.diskon * fraksi -
              (petaDiskon[line.itemTransaksiId] ?? 0) * fraksi +
              (petaPajak[line.itemTransaksiId] ?? 0) * fraksi,
        );
        return HasilRefundLine(
          itemTransaksiId: line.itemTransaksiId,
          jumlah: jumlah < 0 ? 0 : jumlah,
        );
      }(),
  ];
}
