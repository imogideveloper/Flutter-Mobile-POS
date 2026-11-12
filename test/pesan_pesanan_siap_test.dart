import 'package:apps_pos/features/transaksi/domain/pesan_pesanan_siap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pesan siap diambil memuat nama, nomor antrian, dan toko', () {
    expect(
      pesanPesananSiap(judul: 'A-007', antar: false, namaPelanggan: 'Sari', namaToko: 'Kopi Kita'),
      'Halo Sari, pesanan A-007 di Kopi Kita sudah siap, silakan diambil. Terima kasih!',
    );
  });

  test('pesanan antar memakai kalimat akan segera diantar', () {
    expect(
      pesanPesananSiap(judul: 'A-008', antar: true, namaPelanggan: 'Budi'),
      'Halo Budi, pesanan A-008 sudah siap dan akan segera diantar. Terima kasih!',
    );
  });

  test('nama dan toko kosong tidak merusak kalimat', () {
    expect(
      pesanPesananSiap(judul: 'INV-1', antar: false, namaPelanggan: '  ', namaToko: ''),
      'Halo, pesanan INV-1 sudah siap, silakan diambil. Terima kasih!',
    );
  });
}
