import 'package:apps_pos/core/struk/penyusun_struk.dart';
import 'package:apps_pos/core/struk/penyusun_tiket_dapur.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tiket dapur/bar (dokumen IMOGI no. 35): hanya yang dibutuhkan dapur, tanpa harga.
void main() {
  const waktu = 1794300000000; // 2026-11-09 sekitar 09:20 WIB

  TiketDapurData data({
    String? nomorAntrean = 'A-007',
    String? tipe = 'Dine in',
    String? catatan,
    bool salinan = false,
    List<ItemTiketDapur>? items,
  }) =>
      TiketDapurData(
        nomorStruk: 'STR1794300000000',
        tanggalEpochMs: waktu,
        nomorAntrean: nomorAntrean,
        namaTipeOrder: tipe,
        catatan: catatan,
        salinan: salinan,
        items: items ??
            const [
              ItemTiketDapur(namaProduk: 'Kopi Susu', qty: 2),
              ItemTiketDapur(namaProduk: 'Roti Bakar Coklat Keju', qty: 1),
            ],
      );

  List<String> teks(TiketDapurData d, {int lebar = 32}) =>
      renderTeksStruk(susunTiketDapur(data: d, lebar: lebar), lebar);

  test('memuat judul, nomor antrian, tipe pesanan, nomor struk, dan item dengan jumlahnya', () {
    final t = teks(data()).join('\n');
    expect(t, contains('TIKET DAPUR'));
    expect(t, contains('A-007'));
    expect(t, contains('Dine in'));
    expect(t, contains('STR1794300000000'));
    expect(t, contains('2x Kopi Susu'));
    expect(t, contains('1x Roti Bakar Coklat Keju'));
  });

  test('tidak memuat harga atau uang', () {
    final t = teks(data()).join('\n');
    expect(t, isNot(contains('Rp')));
    expect(t.toLowerCase(), isNot(contains('total')));
    expect(t.toLowerCase(), isNot(contains('bayar')));
  });

  test('semua baris tidak melebihi lebar kertas 58 mm (32) maupun 80 mm (48)', () {
    for (final lebar in [32, 48]) {
      for (final b in teks(data(catatan: 'Tolong dipisah, es batunya sedikit saja ya kak'), lebar: lebar)) {
        expect(b.length, lessThanOrEqualTo(lebar), reason: '"$b" lebih panjang dari $lebar');
      }
    }
  });

  test('qty pecahan tampil apa adanya, qty bulat tanpa koma', () {
    final t = teks(data(items: const [
      ItemTiketDapur(namaProduk: 'Nasi Goreng', qty: 3),
      ItemTiketDapur(namaProduk: 'Keju Parut', qty: 0.5),
    ])).join('\n');
    expect(t, contains('3x Nasi Goreng'));
    expect(t, contains('0.5x Keju Parut'));
    expect(t, isNot(contains('3.0x')));
  });

  test('tambahan (topping/varian) dan catatan per item dicetak di bawah menunya', () {
    final t = teks(data(items: const [
      ItemTiketDapur(namaProduk: 'Es Kopi', qty: 1, tambahan: ['Large', 'Less sugar'], catatan: 'tanpa es'),
    ])).join('\n');
    expect(t, contains('1x Es Kopi'));
    expect(t, contains('+ Large'));
    expect(t, contains('+ Less sugar'));
    expect(t, contains('* tanpa es'));
    final urut = teks(data(items: const [
      ItemTiketDapur(namaProduk: 'Es Kopi', qty: 1, tambahan: ['Large']),
    ]));
    expect(urut.indexWhere((e) => e.contains('Es Kopi')) < urut.indexWhere((e) => e.contains('+ Large')), isTrue);
  });

  test('catatan pesanan dicetak, dan nama tanpa nomor antrian atau tipe tetap valid', () {
    final t = teks(data(nomorAntrean: null, tipe: null, catatan: 'Meja dekat jendela')).join('\n');
    expect(t, contains('Catatan: Meja dekat jendela'));
    expect(t, isNot(contains('A-007')));
    expect(t, isNot(contains('Dine in')));
  });

  test('cetak ulang diberi tanda supaya dapur tidak menyiapkan dua kali', () {
    expect(teks(data()).join('\n'), isNot(contains('CETAK ULANG')));
    expect(teks(data(salinan: true)).join('\n'), contains('** CETAK ULANG **'));
  });

  test('karakter non-ASCII diubah agar printer thermal tidak mencetak simbol aneh', () {
    final t = teks(data(items: const [ItemTiketDapur(namaProduk: 'Kopi “Special”', qty: 1)])).join('\n');
    expect(t, contains('Kopi "Special"'));
  });

  test('nomor antrian dicetak besar dan tebal', () {
    final baris = susunTiketDapur(data: data(), lebar: 32);
    final antre = baris.firstWhere((b) => b.teks == 'A-007');
    expect(antre.besar, isTrue);
    expect(antre.tebal, isTrue);
  });
}
