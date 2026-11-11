import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart'
    show StatusPesanan;
import 'package:apps_pos/features/transaksi/domain/estimasi_pesanan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dibuat = DateTime(2026, 11, 12, 10, 0);
  final ms = dibuat.toUtc().millisecondsSinceEpoch;

  String? label({
    int menit = 15,
    StatusPesanan status = StatusPesanan.baru,
    required DateTime sekarang,
  }) => labelEstimasiPesanan(
    tanggalMs: ms,
    menit: menit,
    status: status,
    sekarang: sekarang,
  );

  test('menampilkan jam estimasi selesai = waktu dibuat + menit', () {
    expect(
      label(sekarang: DateTime(2026, 11, 12, 10, 5)),
      'Estimasi selesai 10:15',
    );
    expect(
      label(
        status: StatusPesanan.diproses,
        sekarang: DateTime(2026, 11, 12, 10, 5),
      ),
      'Estimasi selesai 10:15',
    );
  });

  test('melewati estimasi menampilkan keterlambatan dalam menit', () {
    expect(label(sekarang: DateTime(2026, 11, 12, 10, 22)), 'Terlambat 7 mnt');
    expect(estimasiTerlambat('Terlambat 7 mnt'), isTrue);
    expect(
      label(sekarang: DateTime(2026, 11, 12, 10, 15, 30)),
      'Estimasi lewat',
    );
    expect(estimasiTerlambat('Estimasi selesai 10:15'), isFalse);
  });

  test(
    'tidak tampil bila dimatikan (0 menit) atau pesanan sudah siap/selesai',
    () {
      final sekarang = DateTime(2026, 11, 12, 10, 5);
      expect(label(menit: 0, sekarang: sekarang), isNull);
      for (final s in [
        StatusPesanan.siap,
        StatusPesanan.diantar,
        StatusPesanan.selesai,
        StatusPesanan.dibatalkan,
      ]) {
        expect(label(status: s, sekarang: sekarang), isNull);
      }
    },
  );
}
