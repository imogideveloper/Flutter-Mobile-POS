import '../domain/tipe_order.dart' as domain;
import '../domain/tipe_order_mapper.dart';
import 'local/tipe_order_dao.dart';

class TipeOrderRepository {
  TipeOrderRepository(this._dao);

  final TipeOrderDao _dao;

  Stream<List<domain.TipeOrder>> watchTipeOrderAktif(String tokoId) =>
      _dao.watchTipeOrderAktif(tokoId).map((rows) => rows.map((row) => row.toDomain()).toList());
}
