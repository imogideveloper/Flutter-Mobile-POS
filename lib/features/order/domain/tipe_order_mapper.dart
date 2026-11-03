import '../../../core/database/app_database.dart';
import 'tipe_order.dart' as domain;

extension TipeOrderRowMapper on TipeOrderRow {
  domain.TipeOrder toDomain() => domain.TipeOrder(
        id: id,
        tokoId: tokoId,
        nama: nama,
        kanal: kanal,
        pakaiMeja: pakaiMeja,
        markupPersen: markupPersen,
        urutan: urutan,
        aktif: aktif,
      );
}
