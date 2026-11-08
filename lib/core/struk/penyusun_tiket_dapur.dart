import 'penyusun_struk.dart';

/// Penyusun tiket dapur/bar (dokumen IMOGI no. 35, "Cetak tiket pesanan
/// dapur"). FUNGSI MURNI seperti [susunStrukTransaksi]: dari data pesanan
/// menjadi daftar [BarisStruk] yang bisa dicetak lewat jalur yang sama dengan
/// struk (ESC/POS) atau dipratinjau sebagai teks. Tiket HANYA memuat apa yang
/// dibutuhkan dapur: nomor antrian, waktu, item, dan catatan - tanpa harga.

/// Satu baris menu di tiket. [tambahan] dan [catatan] disiapkan untuk varian,
/// topping, dan catatan per item (belum diisi sampai fitur varian dibangun).
class ItemTiketDapur {
  const ItemTiketDapur({
    required this.namaProduk,
    required this.qty,
    this.tambahan = const [],
    this.catatan,
  });

  final String namaProduk;
  final num qty;
  final List<String> tambahan;
  final String? catatan;
}

class TiketDapurData {
  const TiketDapurData({
    required this.nomorStruk,
    required this.tanggalEpochMs,
    required this.items,
    this.nomorAntrean,
    this.namaTipeOrder,
    this.catatan,
    this.salinan = false,
  });

  final String nomorStruk;
  final int tanggalEpochMs;
  final List<ItemTiketDapur> items;
  final String? nomorAntrean;
  final String? namaTipeOrder;
  final String? catatan;

  /// true = cetak ulang; diberi tanda supaya dapur tidak menyiapkan dua kali.
  final bool salinan;
}

String _qty(num qty) => qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();

List<BarisStruk> susunTiketDapur({
  required TiketDapurData data,
  required int lebar,
  String zonaWaktu = 'Asia/Jakarta',
}) {
  final baris = <BarisStruk>[];
  final garis = '-' * lebar;

  baris.add(const BarisStruk('TIKET DAPUR', rata: RataStruk.tengah, tebal: true));
  if (data.salinan) {
    baris.add(const BarisStruk('** CETAK ULANG **', rata: RataStruk.tengah, tebal: true));
  }
  if (data.nomorAntrean != null && data.nomorAntrean!.trim().isNotEmpty) {
    baris.add(BarisStruk(keAscii(data.nomorAntrean!), rata: RataStruk.tengah, tebal: true, besar: true));
  }
  baris.add(BarisStruk(garis));
  if (data.namaTipeOrder != null && data.namaTipeOrder!.trim().isNotEmpty) {
    baris.add(BarisStruk(keAscii(data.namaTipeOrder!), tebal: true));
  }
  baris.add(BarisStruk(keAscii(data.nomorStruk)));
  baris.add(BarisStruk(formatTanggalWaktuStruk(data.tanggalEpochMs, zonaWaktu: zonaWaktu)));
  baris.add(BarisStruk(garis));

  for (final item in data.items) {
    for (final b in bungkusTeks('${_qty(item.qty)}x ${keAscii(item.namaProduk)}', lebar)) {
      baris.add(BarisStruk(b, tebal: true));
    }
    for (final t in item.tambahan) {
      for (final b in bungkusTeks('  + ${keAscii(t)}', lebar)) {
        baris.add(BarisStruk(b));
      }
    }
    if (item.catatan != null && item.catatan!.trim().isNotEmpty) {
      for (final b in bungkusTeks('  * ${keAscii(item.catatan!)}', lebar)) {
        baris.add(BarisStruk(b));
      }
    }
  }

  baris.add(BarisStruk(garis));
  if (data.catatan != null && data.catatan!.trim().isNotEmpty) {
    for (final b in bungkusTeks('Catatan: ${keAscii(data.catatan!)}', lebar)) {
      baris.add(BarisStruk(b, tebal: true));
    }
    baris.add(BarisStruk(garis));
  }
  return baris;
}
