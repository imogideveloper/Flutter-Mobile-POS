import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cache gambar QRIS statis milik usaha (IMOGI no. 10) di file lokal - satu file yang ditimpa setiap
/// sync pull membawa gambar baru, supaya layar bayar QRIS tetap menampilkan QR walau perangkat
/// offline. Pola sama dengan [LogoCache].
class QrisCache {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'qris_statis_cache.bin'));
  }

  static Future<void> simpan(List<int> bytes) async {
    final file = await _file();
    await file.writeAsBytes(bytes, flush: true);
  }

  /// null bila belum ada gambar atau file gagal dibaca.
  static Future<List<int>?> ambil() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> hapus() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
