import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../printer/pengaturan_printer_providers.dart';
import '../printer/printer_service.dart';
import '../widgets/app_toast.dart';
import 'esc_pos_converter.dart';
import 'logo_cache.dart';
import 'penyusun_struk.dart';

/// Hasil cetak - dibedakan dari sekedar bool supaya UI bisa tunjukkan
/// pesan yang beda ("belum atur printer" vs "gagal terhubung").
enum StatusCetak { berhasil, printerBelumDiatur, gagalTersambung, gagalCetak }

/// Warna toast yang konsisten di semua layar yang menampilkan hasil cetak
/// (struk_page.dart, transaksi_detail_page.dart, pelunasan_page.dart).
ToastVariant variantStatusCetak(StatusCetak status) => switch (status) {
      StatusCetak.berhasil => ToastVariant.success,
      StatusCetak.printerBelumDiatur => ToastVariant.warning,
      StatusCetak.gagalTersambung || StatusCetak.gagalCetak => ToastVariant.danger,
    };

/// Satu titik masuk cetak struk (tahap 4 bagian D.3) - cari pengaturan
/// printer tersimpan, sambung kalau belum, cetak [baris]. TIDAK PERNAH
/// melempar exception ke pemanggil - kegagalan apa pun (printer mati,
/// Bluetooth putus, dkk) dilaporkan lewat [StatusCetak], bukan exception,
/// supaya pemanggil (struk_page.dart dkk) tidak perlu try/catch sendiri
/// dan TIDAK ADA jalan bagi error cetak utk mempengaruhi status transaksi
/// yang sudah tersimpan (aturan #D.3 - transaksi SELALU tetap tersimpan).
Future<StatusCetak> cetakStruk(
  WidgetRef ref,
  List<BarisStruk> baris, {
  bool tampilkanLogo = false,
}) async {
  try {
    final pengaturanPrinter = await ref.read(pengaturanPrinterDaoProvider).ambil();
    final mac = pengaturanPrinter?.macAddress;
    if (mac == null) return StatusCetak.printerBelumDiatur;

    final printer = ref.read(printerServiceProvider);
    var tersambung = await printer.statusTersambung();
    if (!tersambung) {
      tersambung = await printer.sambungkan(mac);
    }
    if (!tersambung) return StatusCetak.gagalTersambung;

    final logoBytes = tampilkanLogo ? await LogoCache.ambil() : null;
    final bytes = await konversiKeEscPos(
      baris: baris,
      lebarKertasMm: pengaturanPrinter!.lebarKertasMm,
      logoBytes: logoBytes,
    );
    final sukses = await printer.cetakBytes(bytes);
    return sukses ? StatusCetak.berhasil : StatusCetak.gagalCetak;
  } catch (_) {
    return StatusCetak.gagalCetak;
  }
}

/// true kalau printer tersimpan DAN "cetak otomatis setelah bayar" aktif -
/// dipakai struk_page.dart/pelunasan_page.dart utk tahu apakah perlu
/// mencoba cetak otomatis tanpa kasir menekan tombol apa pun.
Future<bool> perluCetakOtomatis(WidgetRef ref) async {
  final pengaturan = await ref.read(pengaturanPrinterDaoProvider).ambil();
  return pengaturan?.macAddress != null && pengaturan!.cetakOtomatis;
}

String labelStatusCetak(StatusCetak status) => switch (status) {
      StatusCetak.berhasil => 'Struk tercetak',
      StatusCetak.printerBelumDiatur => 'Printer belum diatur - atur di Lainnya > Printer struk',
      StatusCetak.gagalTersambung => 'Gagal terhubung ke printer',
      StatusCetak.gagalCetak => 'Gagal mencetak - cek printer (kertas/baterai/jarak)',
    };
