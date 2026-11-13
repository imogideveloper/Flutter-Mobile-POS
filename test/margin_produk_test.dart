import 'package:apps_pos/features/produk/domain/margin_produk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('marginPersen', () {
    test('hitungan dan pembulatan', () {
      expect(marginPersen(hargaJual: 18000, hpp: 7000), 61); // 61,1
      expect(marginPersen(hargaJual: 15000, hpp: 7500), 50);
      expect(marginPersen(hargaJual: 10000, hpp: 10000), 0);
      expect(marginPersen(hargaJual: 10000, hpp: 12000), -20, reason: 'dijual rugi');
      expect(marginPersen(hargaJual: 0, hpp: 5000), isNull);
    });
  });

  group('statusMargin', () {
    test('batas bawaan 50 persen', () {
      expect(batasMarginBawaan, 50);
      expect(statusMargin(hargaJual: 18000, hpp: 7000), StatusMargin.aman);
      expect(statusMargin(hargaJual: 15000, hpp: 9000), StatusMargin.rendah); // 40%
    });

    test('tepat di batas dianggap aman, satu rupiah di bawahnya rendah', () {
      expect(statusMargin(hargaJual: 10000, hpp: 5000), StatusMargin.aman); // tepat 50%
      expect(statusMargin(hargaJual: 10000, hpp: 5001), StatusMargin.rendah); // 49,99% (dibulatkan 50 di tampilan)
    });

    test('batas diatur per outlet', () {
      expect(statusMargin(hargaJual: 10000, hpp: 7000, batasPersen: 30), StatusMargin.aman);
      expect(statusMargin(hargaJual: 10000, hpp: 7000, batasPersen: 40), StatusMargin.rendah);
      expect(statusMargin(hargaJual: 10000, hpp: 9999, batasPersen: 0), StatusMargin.aman, reason: 'batas 0 = penanda mati');
    });

    test('HPP kosong ditandai tersendiri, bukan margin 100 persen', () {
      expect(statusMargin(hargaJual: 10000, hpp: 0), StatusMargin.hppKosong);
    });

    test('harga jual kosong tidak dinilai; rugi selalu rendah', () {
      expect(statusMargin(hargaJual: 0, hpp: 0), StatusMargin.tidakDinilai);
      expect(statusMargin(hargaJual: 8000, hpp: 9000, batasPersen: 10), StatusMargin.rendah);
    });
  });
}
