import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cache logo toko di file lokal (tahap 4 bagian C.6/D) - path TETAP (satu
/// file, ditimpa tiap kali logo baru berhasil diunduh saat sync pull),
/// supaya struk tetap bisa cetak logo walau device offline sejak unduhan
/// terakhir. TIDAK pakai drift (gambar sbg BLOB bikin query drift berat
/// tanpa guna, file biasa sudah cukup & lebih murah dibaca printer).
class LogoCache {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'logo_struk_cache.bin'));
  }

  static Future<void> simpan(List<int> bytes) async {
    final file = await _file();
    await file.writeAsBytes(bytes, flush: true);
  }

  /// null kalau belum pernah ada logo tersimpan ATAU file-nya gagal
  /// dibaca (rusak/terhapus manual) - pemanggil (konversiKeEscPos) sudah
  /// menangani logoBytes null dgn aman (cuma skip cetak logo).
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
