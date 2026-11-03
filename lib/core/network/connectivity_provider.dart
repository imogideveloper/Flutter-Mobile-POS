import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tahap 5 - Prinsip 1: layar kelola data master (produk, promo, pajak,
/// pelanggan, karyawan, pengaturan) bersifat ONLINE. Tombol simpan di
/// layar2 itu wajib nonaktif saat offline (bukan cuma gagal senyap saat
/// ditekan) - provider ini satu-satunya sumber kebenaran "ada koneksi
/// jaringan" dipakai lintas semua layar kelola baru.
///
/// CATATAN: ini deteksi jaringan LOKAL (wifi/data aktif), BUKAN jaminan
/// server backend bisa dihubungi (mis. wifi tersambung tapi server down) -
/// cukup utk gating UI "butuh internet", kegagalan request sungguhan tetap
/// ditangani lewat BackendException.tidakAdaKoneksi spt biasa.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  bool keOnline(List<ConnectivityResult> hasil) =>
      hasil.any((r) => r != ConnectivityResult.none);

  yield keOnline(await Connectivity().checkConnectivity());
  yield* Connectivity().onConnectivityChanged.map(keOnline);
});
