import 'package:apps_pos/features/transaksi/data/local/tables/transaksi_table.dart' show StatusPesanan;
import 'package:apps_pos/features/transaksi/domain/alur_status_pesanan.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alur status pesanan menurut Panduan Menu Pengaturan IMOGI bagian 4.2.
void main() {
  List<String> urutanLabel(AlurStatusPesanan a) => [for (final t in a.tahap) t.label];

  test('kafe/restoran/minuman/food court: Baru, Diproses, Siap, Selesai', () {
    for (final jenis in ['CAF', 'RES', 'BRD', 'BEV', 'STL', 'FRZ', null]) {
      expect(urutanLabel(AlurStatusPesanan.untuk(jenis)), ['Baru', 'Diproses', 'Siap', 'Selesai'], reason: '$jenis');
    }
  });

  test('pesanan antar menambah tahap Diantar sebelum Selesai', () {
    expect(
      urutanLabel(AlurStatusPesanan.untuk('CAF', termasukDiantar: true)),
      ['Baru', 'Diproses', 'Siap', 'Diantar', 'Selesai'],
    );
  });

  test('katering: Dipesan, Dimasak, Siap kirim, Dikirim, Selesai', () {
    final a = AlurStatusPesanan.untuk('CAT');
    expect(urutanLabel(a), ['Dipesan', 'Dimasak', 'Siap kirim', 'Dikirim', 'Selesai']);
    // Kode tahap sama dengan alur lain, hanya nama tampilannya berbeda.
    expect(a.tahap.map((t) => t.kode), [
      StatusPesanan.baru,
      StatusPesanan.diproses,
      StatusPesanan.siap,
      StatusPesanan.diantar,
      StatusPesanan.selesai,
    ]);
  });

  test('status awal selalu tahap pertama', () {
    expect(AlurStatusPesanan.untuk('CAF').awal, StatusPesanan.baru);
    expect(AlurStatusPesanan.untuk('CAT').awal, StatusPesanan.baru);
  });

  test('berikutnya maju satu tahap dan berhenti di akhir', () {
    final a = AlurStatusPesanan.untuk('CAF');
    expect(a.berikutnya(StatusPesanan.baru)!.kode, StatusPesanan.diproses);
    expect(a.berikutnya(StatusPesanan.diproses)!.kode, StatusPesanan.siap);
    expect(a.berikutnya(StatusPesanan.siap)!.kode, StatusPesanan.selesai);
    expect(a.berikutnya(StatusPesanan.selesai), isNull);
  });

  test('data lama berstatus diambil dan pesanan dibatalkan dianggap tuntas', () {
    final a = AlurStatusPesanan.untuk('CAF');
    expect(a.sudahSelesai(StatusPesanan.diambil), isTrue);
    expect(a.sudahSelesai(StatusPesanan.dibatalkan), isTrue);
    expect(a.sudahSelesai(StatusPesanan.selesai), isTrue);
    expect(a.sudahSelesai(StatusPesanan.baru), isFalse);
    expect(a.berikutnya(StatusPesanan.diambil), isNull);
    expect(a.berikutnya(StatusPesanan.dibatalkan), isNull);
  });

  test('status di luar alur (diantar pada alur standar) tidak punya tahap berikutnya dan tetap punya nama', () {
    final a = AlurStatusPesanan.untuk('CAF');
    expect(a.berikutnya(StatusPesanan.diantar), isNull);
    expect(a.label(StatusPesanan.diantar), 'Diantar');
    expect(a.label(StatusPesanan.diambil), 'Selesai');
    expect(a.label(StatusPesanan.dibatalkan), 'Dibatalkan');
  });

  test('label tombol aksi menyebut tahap yang dituju', () {
    final a = AlurStatusPesanan.untuk('CAT');
    expect(a.berikutnya(StatusPesanan.baru)!.labelAksi, 'Mulai dimasak');
    expect(a.berikutnya(StatusPesanan.diproses)!.labelAksi, 'Tandai siap kirim');
    expect(a.berikutnya(StatusPesanan.siap)!.labelAksi, 'Tandai dikirim');
  });

  test('kode jenis usaha tidak peka huruf besar/kecil', () {
    expect(urutanLabel(AlurStatusPesanan.untuk('cat')).first, 'Dipesan');
  });
}
