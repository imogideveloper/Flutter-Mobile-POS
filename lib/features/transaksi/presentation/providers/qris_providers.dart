import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/struk/qris_cache.dart';

/// Gambar QRIS statis usaha dari cache lokal (diisi sync pull atau unggahan di Pengaturan metode
/// bayar). null = belum ada gambar atau cache tidak terbaca.
final qrisTokoProvider = FutureProvider.autoDispose<Uint8List?>((ref) async {
  try {
    final bytes = await QrisCache.ambil();
    return bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  }
});
