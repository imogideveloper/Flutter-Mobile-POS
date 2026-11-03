import '../data/local/tables/tipe_order_table.dart' show TipeOrderKanal;

class TipeOrder {
  const TipeOrder({
    required this.id,
    required this.tokoId,
    required this.nama,
    required this.kanal,
    required this.pakaiMeja,
    required this.markupPersen,
    required this.urutan,
    required this.aktif,
  });

  final String id;
  final String tokoId;
  final String nama;
  final TipeOrderKanal kanal;
  final bool pakaiMeja;
  final double markupPersen;
  final int urutan;
  final bool aktif;
}
