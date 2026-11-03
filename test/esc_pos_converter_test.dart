import 'package:apps_pos/core/struk/esc_pos_converter.dart';
import 'package:apps_pos/core/struk/penyusun_struk.dart';
import 'package:flutter_test/flutter_test.dart';

const _png1x1 = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const data = StrukData(
    namaOutlet: 'Toko Kopi Asik',
    nomorStruk: 'STR001',
    tanggalEpochMs: 1768434600000,
    items: [ItemStruk(namaProduk: 'Kopi Hitam', qty: 1, hargaSatuan: 15000, subtotal: 15000)],
    subtotal: 15000,
    total: 15000,
    pembayaran: [PembayaranStruk(labelMetode: 'Tunai', jumlah: 15000)],
  );
  const pengaturan58 = PengaturanStrukData(lebarKertasMm: 58);
  const pengaturan80 = PengaturanStrukData(lebarKertasMm: 80);

  test('58mm: hasilkan byte non-kosong tanpa logo', () async {
    final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan58);
    final bytes = await konversiKeEscPos(baris: baris, lebarKertasMm: 58);
    expect(bytes, isNotEmpty);
  });

  test('80mm: hasilkan byte non-kosong tanpa logo', () async {
    final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan80);
    final bytes = await konversiKeEscPos(baris: baris, lebarKertasMm: 80);
    expect(bytes, isNotEmpty);
  });

  test('dgn logo valid: byte lebih banyak drpd tanpa logo', () async {
    final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan58);
    final tanpaLogo = await konversiKeEscPos(baris: baris, lebarKertasMm: 58);
    final denganLogo =
        await konversiKeEscPos(baris: baris, lebarKertasMm: 58, logoBytes: _png1x1);
    expect(denganLogo.length, greaterThan(tanpaLogo.length));
  });

  test('logo rusak (bukan gambar valid) tidak melempar exception', () async {
    final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan58);
    final bytes = await konversiKeEscPos(
      baris: baris,
      lebarKertasMm: 58,
      logoBytes: [1, 2, 3, 4, 5],
    );
    expect(bytes, isNotEmpty);
  });
}
