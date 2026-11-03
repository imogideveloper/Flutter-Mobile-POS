import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../transaksi/data/local/tables/transaksi_table.dart';
import '../../../transaksi/data/local/transaksi_dao.dart';

/// Piutang (tahap 3b-1) - agregat per pelanggan dari transaksi kasbon
/// (statusBayar != lunas) di outlet device ini, murni dari data lokal yang
/// SUDAH ADA (sama pola dgn LaporanRepository: tidak ada tabel baru).
class PiutangPelanggan {
  const PiutangPelanggan({
    required this.pelangganId,
    required this.namaPelanggan,
    required this.totalUtang,
    required this.jumlahTransaksi,
    required this.jatuhTempoTerdekat,
    required this.lewatJatuhTempo,
  });

  final String pelangganId;
  final String namaPelanggan;
  final int totalUtang;
  final int jumlahTransaksi;
  final int? jatuhTempoTerdekat;
  final bool lewatJatuhTempo;
}

final transaksiDaoProvider = Provider<TransaksiDao>((ref) {
  return ref.watch(appDatabaseProvider).transaksiDao;
});

final piutangPelangganProvider = StreamProvider<List<PiutangPelanggan>>((ref) {
  final outletId = ref.watch(currentOutletIdProvider);
  final transaksiDao = ref.watch(transaksiDaoProvider);
  final pelangganDao = ref.watch(appDatabaseProvider).pelangganDao;

  return transaksiDao.watchTransaksiOutlet(outletId).asyncMap((rows) async {
    final kasbon = rows.where(
      (t) => t.statusBayar != StatusBayarTransaksi.lunas && t.pelangganId != null,
    );
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    final totalUtang = <String, int>{};
    final jumlahTransaksi = <String, int>{};
    final jatuhTempoTerdekat = <String, int?>{};

    for (final t in kasbon) {
      final pelangganId = t.pelangganId!;
      totalUtang[pelangganId] = (totalUtang[pelangganId] ?? 0) + t.sisaTagihan;
      jumlahTransaksi[pelangganId] = (jumlahTransaksi[pelangganId] ?? 0) + 1;
      if (t.jatuhTempo != null) {
        final terdekat = jatuhTempoTerdekat[pelangganId];
        if (terdekat == null || t.jatuhTempo! < terdekat) {
          jatuhTempoTerdekat[pelangganId] = t.jatuhTempo;
        }
      }
    }

    final hasil = <PiutangPelanggan>[];
    for (final pelangganId in totalUtang.keys) {
      final pelanggan = await pelangganDao.pelangganById(pelangganId);
      final terdekat = jatuhTempoTerdekat[pelangganId];
      hasil.add(
        PiutangPelanggan(
          pelangganId: pelangganId,
          namaPelanggan: pelanggan?.nama ?? '-',
          totalUtang: totalUtang[pelangganId]!,
          jumlahTransaksi: jumlahTransaksi[pelangganId]!,
          jatuhTempoTerdekat: terdekat,
          lewatJatuhTempo: terdekat != null && terdekat < now,
        ),
      );
    }
    hasil.sort((a, b) => b.totalUtang.compareTo(a.totalUtang));
    return hasil;
  });
});

/// Transaksi kasbon milik SATU pelanggan - dipakai PelunasanPage utk daftar
/// pilihan transaksi mana yang mau dicicil/dilunasi.
final transaksiKasbonPelangganProvider =
    StreamProvider.family<List<TransaksiRow>, String>((ref, pelangganId) {
  final outletId = ref.watch(currentOutletIdProvider);
  final transaksiDao = ref.watch(transaksiDaoProvider);
  return transaksiDao.watchTransaksiOutlet(outletId).map(
        (rows) => rows
            .where(
              (t) => t.pelangganId == pelangganId && t.statusBayar != StatusBayarTransaksi.lunas,
            )
            .toList(),
      );
});
