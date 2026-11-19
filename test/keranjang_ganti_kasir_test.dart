import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/features/produk/data/local/tables/produk_table.dart' show ProdukTipe;
import 'package:apps_pos/features/produk/domain/produk.dart';
import 'package:apps_pos/features/transaksi/presentation/providers/keranjang_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Perilaku B4 (perlu_konfirmasi): keranjang dan isiannya tidak terbawa ke kasir berikutnya.
void main() {
  const kopi = Produk(
    id: 'p-kopi',
    tokoId: 't1',
    nama: 'Kopi',
    tipe: ProdukTipe.barang,
    lacakStok: false,
    punyaVarian: false,
    pakaiResep: false,
    hpp: 8000,
    hargaJual: 18000,
    dijual: true,
    aktif: true,
  );

  test('ganti akun mengosongkan keranjang, pelanggan, catatan, dan draft', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Provider yang tidak di-watch widget harus dijaga hidup selama tes.
    container.listen(keranjangProvider, (_, __) {});
    container.listen(keranjangPelangganIdProvider, (_, __) {});
    container.listen(keranjangCatatanProvider, (_, __) {});
    container.listen(draftPesananDibukaProvider, (_, __) {});

    container.read(currentPenggunaIdProvider.notifier).login('kasir-a');
    container.read(keranjangProvider.notifier).tambah(kopi);
    container.read(keranjangPelangganIdProvider.notifier).state = 'pelanggan-1';
    container.read(keranjangCatatanProvider.notifier).state = 'tanpa gula';
    container.read(draftPesananDibukaProvider.notifier).state = 'draft-1';
    expect(container.read(keranjangProvider), hasLength(1));

    container.read(currentPenggunaIdProvider.notifier).logout();
    container.read(currentPenggunaIdProvider.notifier).login('kasir-b');

    expect(container.read(keranjangProvider), isEmpty);
    expect(container.read(keranjangPelangganIdProvider), isNull);
    expect(container.read(keranjangCatatanProvider), isNull);
    expect(container.read(draftPesananDibukaProvider), isNull);
  });
}
