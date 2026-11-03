import '../data/local/tables/shift_table.dart' show ShiftStatus;

class Shift {
  const Shift({
    required this.id,
    required this.tokoId,
    required this.outletId,
    this.perangkatId,
    required this.penggunaId,
    required this.dibukaPada,
    this.ditutupPada,
    required this.modalAwal,
    this.kasSeharusnya,
    this.kasAktual,
    this.selisih,
    this.catatan,
    required this.status,
  });

  final String id;
  final String tokoId;
  final String outletId;
  final String? perangkatId;
  final String penggunaId;
  final int dibukaPada;
  final int? ditutupPada;
  final int modalAwal;
  final int? kasSeharusnya;
  final int? kasAktual;
  final int? selisih;
  final String? catatan;
  final ShiftStatus status;

  bool get sedangBuka => status == ShiftStatus.buka;
}
