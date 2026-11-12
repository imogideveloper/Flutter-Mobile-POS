import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Pemilih berkas CSV. Mengembalikan isi teks, atau null bila dibatalkan. Dipisah jadi provider
/// supaya tes bisa menggantinya tanpa membuka pemilih berkas sungguhan.
typedef PemilihCsv = Future<String?> Function();

const maksUkuranCsvByte = 1024 * 1024;

final pemilihCsvProvider = Provider<PemilihCsv>((ref) {
  return () async {
    final berkas = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
    );
    if (berkas == null) return null;
    final panjang = await berkas.length();
    if (panjang != null && panjang > maksUkuranCsvByte) {
      throw const FormatException('Berkas terlalu besar (maksimal 1 MB).');
    }
    return utf8.decode(await berkas.readAsBytes(), allowMalformed: true);
  };
});

/// Membagikan teks sebagai berkas (template atau ekspor) lewat menu bagikan.
typedef PembagiBerkas = Future<void> Function(String namaFile, String isi);

final pembagiBerkasProvider = Provider<PembagiBerkas>((ref) {
  return (namaFile, isi) async {
    final dir = await getTemporaryDirectory();
    final berkas = File('${dir.path}/$namaFile');
    await berkas.writeAsString(isi, encoding: utf8);
    await SharePlus.instance.share(ShareParams(files: [XFile(berkas.path)], subject: namaFile));
  };
});
