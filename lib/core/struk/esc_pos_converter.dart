import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

import 'penyusun_struk.dart';

/// Konversi [baris] (hasil penyusun_struk.dart) jadi byte ESC/POS siap
/// dikirim ke printer thermal (tahap 4 bagian C.6). [logoBytes] (PNG/JPG
/// mentah, hasil cache lokal - lihat printer_service.dart) dicetak PALING
/// ATAS kalau diisi, di-resize dulu supaya lebarnya pas kertas.
Future<List<int>> konversiKeEscPos({
  required List<BarisStruk> baris,
  required int lebarKertasMm,
  List<int>? logoBytes,
}) async {
  final profile = await CapabilityProfile.load();
  final paperSize = lebarKertasMm == 80 ? PaperSize.mm80 : PaperSize.mm58;
  final generator = Generator(paperSize, profile);
  final lebarKarakter = lebarKertasMm == 80 ? 48 : 32;

  var bytes = <int>[];
  bytes += generator.reset();

  if (logoBytes != null) {
    // decodeImage bisa melempar exception internal (bukan cuma balikin
    // null) utk byte yang rusak/terlalu pendek (quirk sniffing format di
    // package:image) - logo cache yang korup TIDAK BOLEH menggagalkan
    // seluruh pencetakan struk, jadi dibungkus try/catch.
    img.Image? decoded;
    try {
      decoded = img.decodeImage(Uint8List.fromList(logoBytes));
    } catch (_) {
      decoded = null;
    }
    if (decoded != null) {
      // Target lebar dot aman utk kedua ukuran kertas fisik - printer
      // sendiri yang memotong kalau masih lebih lebar dari print head.
      final targetLebar = lebarKertasMm == 80 ? 480 : 360;
      final gambar =
          decoded.width > targetLebar ? img.copyResize(decoded, width: targetLebar) : decoded;
      bytes += generator.image(gambar);
    }
  }

  for (final b in baris) {
    final align = switch (b.rata) {
      RataStruk.kiri => PosAlign.left,
      RataStruk.tengah => PosAlign.center,
      RataStruk.kanan => PosAlign.right,
    };
    bytes += generator.text(
      b.teks,
      styles: PosStyles(
        align: align,
        bold: b.tebal,
        height: b.besar ? PosTextSize.size2 : PosTextSize.size1,
        width: b.besar ? PosTextSize.size2 : PosTextSize.size1,
      ),
      maxCharsPerLine: lebarKarakter,
    );
  }

  bytes += generator.feed(1);
  bytes += generator.cut();
  return bytes;
}
