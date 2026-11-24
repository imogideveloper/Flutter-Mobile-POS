import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Membaca nilai pertama sebuah [StreamProvider] dari aksi sesaat (ketukan tombol), tanpa menggantung.
///
/// Jangan pakai `await ref.read(provider.future)` untuk StreamProvider di aksi pengguna: tanpa pendengar, Riverpod 3
/// menjeda langganan aliran sehingga nilai pertama tidak pernah datang dan tombol "tidak berbuat apa pun" (ditemukan
/// di HP 2026-11-24: Tukar poin dan Produk yang memakai grup). Di sini dipasang pendengar sementara selama menunggu.
Future<T> bacaSekali<T>(
  WidgetRef ref,
  StreamProvider<T> provider, {
  Duration batasWaktu = const Duration(seconds: 10),
}) {
  final selesai = Completer<T>();
  late final ProviderSubscription<AsyncValue<T>> langganan;
  langganan = ref.listenManual<AsyncValue<T>>(
    provider,
    (_, nilai) {
      if (selesai.isCompleted) return;
      nilai.when(
        data: selesai.complete,
        error: (e, s) => selesai.completeError(e, s),
        loading: () {},
      );
    },
    fireImmediately: true,
  );
  return selesai.future.timeout(batasWaktu).whenComplete(() => langganan.close());
}
