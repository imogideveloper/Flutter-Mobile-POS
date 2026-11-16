import 'package:apps_pos/features/pelanggan/domain/pelanggan.dart';
import 'package:apps_pos/features/pelanggan/presentation/providers/pelanggan_providers.dart';
import 'package:apps_pos/features/promo/data/local/tables/promo_table.dart' show PromoCakupan, PromoTipe;
import 'package:apps_pos/features/promo/domain/promo.dart';
import 'package:apps_pos/features/promo/domain/promo_ulang_tahun.dart';
import 'package:apps_pos/features/promo/presentation/providers/promo_providers.dart';
import 'package:apps_pos/features/transaksi/presentation/providers/keranjang_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Promo khusus ulang tahun (IMOGI no. 56) hanya berlaku bila pelanggan di keranjang berulang tahun
/// hari ini. Penjaga ada di keranjangPromoProvider, titik tunggal yang dipakai semua jalur bayar.
void main() {
  const promoBiasa = Promo(
    id: 'biasa', tokoId: 't', nama: 'Promo Jumat', tipe: PromoTipe.persen, nilai: 10,
    cakupan: PromoCakupan.transaksi, minBelanja: 0, aktif: true,
  );
  const promoUlangTahun = Promo(
    id: 'bday', tokoId: 't', nama: 'Diskon Ulang Tahun', tipe: PromoTipe.persen, nilai: 20,
    cakupan: PromoCakupan.transaksi, minBelanja: 0, aktif: true, khususUlangTahun: true,
  );

  final sekarang = DateTime.now();
  final lahirHariIni = 2000 * 10000 + sekarang.month * 100 + sekarang.day; // tahun kabisat: aman untuk 29 Feb
  final besok = sekarang.add(const Duration(days: 1));
  final lahirBesok = 2000 * 10000 + besok.month * 100 + besok.day;

  Pelanggan pelanggan(String id, int? lahir) =>
      Pelanggan(id: id, tokoId: 't', nama: 'P $id', poin: 0, totalBelanja: 0, tanggalLahir: lahir);

  ProviderContainer buat() {
    final c = ProviderContainer(overrides: [
      promoAktifProvider.overrideWith((ref) => Stream.value([promoBiasa, promoUlangTahun])),
      pelangganAktifProvider.overrideWith((ref) => Stream.value([
            pelanggan('ultah', lahirHariIni),
            pelanggan('besok', lahirBesok),
            pelanggan('tanpa', null),
          ])),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> siap(ProviderContainer c) async {
    // `.future` pada StreamProvider menggantung di tes: dengarkan lalu beri waktu stream mengeluarkan nilai.
    c.listen(promoAktifProvider, (_, _) {});
    c.listen(pelangganAktifProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('promo biasa berlaku tanpa pelanggan', () async {
    final c = buat();
    await siap(c);
    c.read(keranjangPromoIdProvider.notifier).state = 'biasa';
    expect(c.read(keranjangPromoProvider)?.id, 'biasa');
  });

  test('promo ulang tahun tidak berlaku tanpa pelanggan, atau pelanggan tanpa tanggal lahir', () async {
    final c = buat();
    await siap(c);
    c.read(keranjangPromoIdProvider.notifier).state = 'bday';
    expect(c.read(keranjangPromoProvider), isNull, reason: 'belum ada pelanggan');

    c.read(keranjangPelangganIdProvider.notifier).state = 'tanpa';
    expect(c.read(keranjangPromoProvider), isNull);
    expect(c.read(keranjangPelangganUlangTahunProvider), isFalse);
  });

  test('promo ulang tahun berlaku untuk pelanggan yang berulang tahun hari ini, tidak untuk besok', () async {
    final c = buat();
    await siap(c);
    c.read(keranjangPromoIdProvider.notifier).state = 'bday';

    c.read(keranjangPelangganIdProvider.notifier).state = 'ultah';
    expect(c.read(keranjangPelangganUlangTahunProvider), isTrue);
    expect(c.read(keranjangPromoProvider)?.id, 'bday');

    c.read(keranjangPelangganIdProvider.notifier).state = 'besok';
    expect(c.read(keranjangPromoProvider), isNull);
  });

  test('mengganti pelanggan setelah promo dipilih mencabut promo ulang tahun, promo biasa tetap', () async {
    final c = buat();
    await siap(c);
    c.read(keranjangPelangganIdProvider.notifier).state = 'ultah';
    c.read(keranjangPromoIdProvider.notifier).state = 'bday';
    expect(c.read(keranjangPromoProvider)?.id, 'bday');

    c.read(keranjangPelangganIdProvider.notifier).state = null; // pelanggan dilepas
    expect(c.read(keranjangPromoProvider), isNull);

    c.read(keranjangPromoIdProvider.notifier).state = 'biasa';
    expect(c.read(keranjangPromoProvider)?.id, 'biasa');
  });

  group('penerapan otomatis promo ulang tahun', () {
    const nonaktif = Promo(
      id: 'mati', tokoId: 't', nama: 'Ultah Lama', tipe: PromoTipe.persen, nilai: 50,
      cakupan: PromoCakupan.transaksi, minBelanja: 0, aktif: false, khususUlangTahun: true,
    );

    test('diterapkan hanya bila berulang tahun dan kasir belum memilih promo', () {
      Promo? coba({required bool ultah, String? terpilih, List<Promo>? daftar}) => promoUlangTahunOtomatis(
            promoAktif: daftar ?? [promoBiasa, promoUlangTahun],
            pelangganUlangTahun: ultah,
            promoTerpilihId: terpilih,
          );
      expect(coba(ultah: true)?.id, 'bday');
      expect(coba(ultah: false), isNull);
      expect(coba(ultah: true, terpilih: 'biasa'), isNull, reason: 'pilihan kasir tidak ditimpa');
    });

    test('tanpa promo ulang tahun aktif tidak ada yang diterapkan; yang pertama dipilih bila ada beberapa', () {
      expect(promoUlangTahunOtomatis(promoAktif: [promoBiasa], pelangganUlangTahun: true, promoTerpilihId: null), isNull);
      expect(promoUlangTahunOtomatis(promoAktif: [nonaktif], pelangganUlangTahun: true, promoTerpilihId: null), isNull);
      expect(
        promoUlangTahunOtomatis(
          promoAktif: [promoBiasa, promoUlangTahun, nonaktif],
          pelangganUlangTahun: true,
          promoTerpilihId: null,
        )?.id,
        'bday',
      );
    });
  });
}
