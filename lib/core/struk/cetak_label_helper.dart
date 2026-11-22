import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../printer/pengaturan_printer_providers.dart';
import '../printer/printer_service.dart';
import 'cetak_struk_helper.dart' show StatusCetak;
import 'penyusun_label_produk.dart';

/// true kalau printer label sudah dipilih DAN "cetak label otomatis" aktif.
Future<bool> perluCetakLabelOtomatis(WidgetRef ref) async {
  final p = await ref.read(pengaturanPrinterDaoProvider).ambil();
  return p?.labelMacAddress != null && p!.labelOtomatis;
}

/// true kalau ada printer label yang dipilih (tombol cetak label hanya tampil bila ini true).
Future<bool> printerLabelTersedia(WidgetRef ref) async {
  final p = await ref.read(pengaturanPrinterDaoProvider).ambil();
  return p?.labelMacAddress != null;
}

/// Cetak semua [labels] ke printer label. Seperti `cetakStruk`: TIDAK pernah melempar exception, hasilnya
/// lewat [StatusCetak] supaya kegagalan cetak tidak memengaruhi transaksi yang sudah tersimpan.
/// Printer struk dan printer label berbagi satu koneksi Bluetooth di HP, jadi setelah selesai koneksi
/// diputus supaya cetak struk berikutnya menyambung ulang ke printer struk, bukan ke printer label.
Future<StatusCetak> cetakLabelProduk(
  WidgetRef ref,
  List<LabelProdukData> labels,
) async {
  try {
    final p = await ref.read(pengaturanPrinterDaoProvider).ambil();
    final mac = p?.labelMacAddress;
    if (mac == null) return StatusCetak.printerBelumDiatur;

    final printer = ref.read(printerServiceProvider);
    // Mungkin masih tersambung ke printer struk: putuskan lalu sambung ke printer label.
    if (await printer.statusTersambung()) await printer.putuskan();
    if (!await printer.sambungkan(mac)) return StatusCetak.gagalTersambung;

    try {
      for (final label in labels) {
        final bytes = susunTspl(
          label,
          lebarMm: p!.labelLebarMm,
          tinggiMm: p.labelTinggiMm,
        );
        if (!await printer.cetakBytes(bytes)) return StatusCetak.gagalCetak;
      }
      return StatusCetak.berhasil;
    } finally {
      await printer.putuskan();
    }
  } catch (_) {
    return StatusCetak.gagalCetak;
  }
}

String pesanStatusLabel(StatusCetak status, int jumlah) => switch (status) {
  StatusCetak.berhasil =>
    jumlah == 1 ? 'Label tercetak' : '$jumlah label tercetak',
  StatusCetak.printerBelumDiatur =>
    'Printer label belum diatur - atur di Lainnya > Printer struk',
  StatusCetak.gagalTersambung => 'Gagal terhubung ke printer label',
  StatusCetak.gagalCetak =>
    'Gagal mencetak label - cek printer (stiker/baterai/jarak)',
};
