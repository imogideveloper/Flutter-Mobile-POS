import 'dart:convert';

import 'package:apps_pos/core/struk/penyusun_struk.dart' as struk;
import 'package:apps_pos/core/struk/struk_snapshot.dart';
import 'package:apps_pos/features/promo/domain/rincian_pajak.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = struk.StrukData(
    namaOutlet: 'Toko Kopi Senang',
    nomorStruk: 'OUT1-0042',
    tanggalEpochMs: DateTime.utc(2026, 1, 15, 3, 30).millisecondsSinceEpoch,
    namaKasir: 'Budi',
    namaPelanggan: 'Ani',
    items: const [
      struk.ItemStruk(namaProduk: 'Kopi Hitam', qty: 2, hargaSatuan: 15000, subtotal: 30000),
      struk.ItemStruk(namaProduk: 'Roti Bakar', qty: 1, hargaSatuan: 12000, subtotal: 12000, catatan: 'Tanpa keju'),
    ],
    subtotal: 42000,
    diskonPromo: 2000,
    namaPromo: 'Promo Jumat',
    rincianPajak: const [
      RincianPajak(nama: 'PPN', persen: 11, jumlah: 4400, termasukHarga: false),
    ],
    rincianService: const [
      RincianPajak(nama: 'Service', persen: 5, jumlah: 2000, termasukHarga: false),
    ],
    pembulatan: -400,
    total: 46000,
    pembayaran: const [struk.PembayaranStruk(labelMetode: 'Tunai', jumlah: 50000)],
    kembalian: 4000,
    poinDidapat: 46,
    catatanTransaksi: 'Bungkus terpisah',
  );
  const pengaturan = struk.PengaturanStrukData(
    headerStruk: 'Selamat datang',
    footerStruk: 'Terima kasih sudah berbelanja',
    lebarKertasMm: 58,
    tampilLogo: true,
    pakaiNomorAntrean: false,
  );

  test('temuan A.2 (tahap 5) - snapshot JSON round-trip tidak mengubah data', () {
    final json = strukSnapshotKeJson(data, pengaturan);
    // Lewat encode+decode sungguhan (bukan cuma Map langsung) - persis
    // jalur yang dipakai simpan ke drift (TEXT) & backend (JSONB).
    final kembali = strukSnapshotDariJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

    final asli = struk.renderTeksStruk(
      struk.susunStrukTransaksi(data: data, pengaturan: pengaturan),
      pengaturan.lebarKarakter,
    );
    final dariSnapshot = struk.renderTeksStruk(
      struk.susunStrukTransaksi(data: kembali.data, pengaturan: kembali.pengaturan),
      kembali.pengaturan.lebarKarakter,
    );
    expect(dariSnapshot, asli);
  });

  test(
    'golden: cetak ulang (salinan=true) dari snapshot IDENTIK dgn struk asli kecuali baris ** SALINAN **',
    () {
      final json = strukSnapshotKeJson(data, pengaturan);
      final kembali = strukSnapshotDariJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

      final baSalinan = struk.renderTeksStruk(
        struk.susunStrukTransaksi(data: kembali.data, pengaturan: kembali.pengaturan, salinan: true),
        kembali.pengaturan.lebarKarakter,
      );
      final asli = struk.renderTeksStruk(
        struk.susunStrukTransaksi(data: data, pengaturan: pengaturan),
        pengaturan.lebarKarakter,
      );

      // Baris "** SALINAN **" (sudah dicenter sendiri oleh susunStrukTransaksi)
      // adalah SATU-SATUNYA perbedaan - buang baris itu dari hasil salinan,
      // sisanya harus PERSIS sama dgn struk asli, urutan dan isi.
      final tanpaMarkerSalinan = baSalinan.where((b) => !b.contains('SALINAN')).toList();
      expect(tanpaMarkerSalinan, asli);
      expect(baSalinan.where((b) => b.contains('SALINAN')), hasLength(1));
    },
  );
}
