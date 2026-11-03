import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dipicu dari 2 arah: (1) DioBackendApi, begitu respons API manapun
/// balas 403 `{"detail": {"kode": "fitur_terkunci", ...}}` (lihat
/// dio_backend_api.dart) - device baru sadar fiturnya terkunci SAAT
/// dicoba, bukan sebelumnya; (2) FiturTerkunci widget, saat pengguna
/// menekan tombol yang sudah kelihatan terkunci dari cache lokal
/// (FeatureGate). Keduanya berakhir di bottom sheet yang SAMA - lihat
/// fitur_terkunci_sheet.dart + listener di main.dart.
class FiturTerkunciEvent {
  const FiturTerkunciEvent({required this.fitur, required this.paketMinimal});

  final String fitur;
  final String? paketMinimal;
}

class _FiturTerkunciNotifier extends Notifier<FiturTerkunciEvent?> {
  @override
  FiturTerkunciEvent? build() => null;

  void tampilkan(String fitur, String? paketMinimal) {
    state = FiturTerkunciEvent(fitur: fitur, paketMinimal: paketMinimal);
  }

  void bersihkan() => state = null;
}

final fiturTerkunciEventProvider =
    NotifierProvider<_FiturTerkunciNotifier, FiturTerkunciEvent?>(_FiturTerkunciNotifier.new);
