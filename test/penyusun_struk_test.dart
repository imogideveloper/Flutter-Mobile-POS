import 'package:apps_pos/core/struk/penyusun_struk.dart';
import 'package:apps_pos/features/promo/domain/rincian_pajak.dart';
import 'package:flutter_test/flutter_test.dart';

int _tanggal(int jam, int menit) =>
    DateTime.utc(2026, 1, 15, jam - 7, menit).millisecondsSinceEpoch; // WIB = UTC+7

void _pastikanTidakOverflow(List<BarisStruk> baris, int lebar) {
  for (final line in renderTeksStruk(baris, lebar)) {
    expect(line.length, lessThanOrEqualTo(lebar), reason: 'baris "$line" melebihi $lebar karakter');
  }
}

void main() {
  group('primitif format', () {
    test('formatRupiahStruk pakai titik ribuan tanpa spasi', () {
      expect(formatRupiahStruk(30000), 'Rp30.000');
      expect(formatRupiahStruk(3300), 'Rp3.300');
      expect(formatRupiahStruk(0), 'Rp0');
    });

    test('keAscii mengganti kutip miring/em dash/elipsis/bullet', () {
      expect(keAscii('Promo “Beli 1” – gratis…'), 'Promo "Beli 1" - gratis...');
      expect(keAscii('• Item spesial'), '- Item spesial');
    });

    test('keAscii membuang emoji (tanpa padanan ASCII)', () {
      expect(keAscii('Terima kasih 😊🙏'), 'Terima kasih ');
    });

    test('BarisStruk.duaKolom pas lebar & pisah label-nilai dgn spasi', () {
      final baris = BarisStruk.duaKolom('Subtotal', 'Rp30.000', 32);
      expect(baris.teks, 'Subtotal${' ' * 16}Rp30.000');
      expect(baris.teks.length, 32);
    });

    test('BarisStruk.duaKolom memotong label yg kepanjangan', () {
      final baris = BarisStruk.duaKolom('Diskon member yang sangat panjang sekali', 'Rp1.000', 32);
      expect(baris.teks.length, 32);
      expect(baris.teks.endsWith('Rp1.000'), isTrue);
    });

    test('bungkusTeks memecah teks panjang di spasi, tiap baris <= lebar', () {
      final hasil = bungkusTeks('Kopi Susu Gula Aren Signature Spesial', 16);
      expect(hasil, isNotEmpty);
      for (final baris in hasil) {
        expect(baris.length, lessThanOrEqualTo(16));
      }
      expect(hasil.join(' '), 'Kopi Susu Gula Aren Signature Spesial');
    });

    test('renderTeksStruk menengahkan RataStruk.tengah sesuai lebar', () {
      final hasil = renderTeksStruk([const BarisStruk('AB', rata: RataStruk.tengah)], 6);
      expect(hasil.single, '  AB  ');
      expect(hasil.single.length, 6);
    });
  });

  group('susunStrukTransaksi - 58mm', () {
    test('transaksi lunas biasa: subtotal, pajak, total, bayar, kembali', () {
      final data = StrukData(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR001',
        tanggalEpochMs: _tanggal(10, 30),
        namaKasir: 'Budi',
        items: const [
          ItemStruk(namaProduk: 'Kopi Hitam', qty: 2, hargaSatuan: 15000, subtotal: 30000),
        ],
        subtotal: 30000,
        rincianPajak: const [
          RincianPajak(nama: 'PPN', persen: 11, jumlah: 3300, termasukHarga: false),
        ],
        total: 33300,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 40000)],
        kembalian: 6700,
      );
      const pengaturan = PengaturanStrukData(lebarKertasMm: 58);

      final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan);

      expect(baris, [
        const BarisStruk('Toko Kopi Asik', rata: RataStruk.tengah, tebal: true),
        const BarisStruk('--------------------------------'),
        const BarisStruk('STR001'),
        const BarisStruk('15/01/2026 10:30'),
        const BarisStruk('Kasir: Budi'),
        const BarisStruk('--------------------------------'),
        const BarisStruk('Kopi Hitam'),
        BarisStruk.duaKolom('  2 x Rp15.000', 'Rp30.000', 32),
        const BarisStruk('--------------------------------'),
        BarisStruk.duaKolom('Subtotal', 'Rp30.000', 32),
        BarisStruk.duaKolom('PPN 11%', 'Rp3.300', 32),
        BarisStruk.duaKolom('TOTAL', 'Rp33.300', 32, tebal: true),
        BarisStruk.duaKolom('Tunai', 'Rp40.000', 32),
        BarisStruk.duaKolom('Kembali', 'Rp6.700', 32),
        const BarisStruk('--------------------------------'),
        const BarisStruk('Terima kasih!', rata: RataStruk.tengah),
      ]);
      _pastikanTidakOverflow(baris, 32);
    });

    test('pajak termasuk harga ditandai (incl)', () {
      final data = StrukData(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR002',
        tanggalEpochMs: _tanggal(10, 30),
        items: const [
          ItemStruk(namaProduk: 'Nasi Goreng', qty: 1, hargaSatuan: 22200, subtotal: 22200),
        ],
        subtotal: 22200,
        rincianPajak: const [
          RincianPajak(nama: 'PPN', persen: 11, jumlah: 2200, termasukHarga: true),
        ],
        total: 22200,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 22200)],
      );
      const pengaturan = PengaturanStrukData(lebarKertasMm: 58);

      final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan);

      expect(baris, contains(BarisStruk.duaKolom('PPN 11% (incl)', 'Rp2.200', 32)));
      _pastikanTidakOverflow(baris, 32);
    });
  });

  group('susunStrukTransaksi - 80mm', () {
    test('lebar 48 karakter dipakai, dgn diskon member+promo+service', () {
      final data = StrukData(
        namaOutlet: 'Toko Kopi Asik Cabang Sudirman',
        nomorStruk: 'STR003',
        tanggalEpochMs: _tanggal(14, 5),
        namaPelanggan: 'Sari',
        items: const [
          ItemStruk(namaProduk: 'Kopi Hitam', qty: 2, hargaSatuan: 15000, subtotal: 30000),
        ],
        subtotal: 30000,
        diskonMember: 1000,
        diskonPromo: 2000,
        namaPromo: 'Promo Akhir Tahun',
        rincianService: const [RincianPajak(nama: 'Service', persen: 5, jumlah: 1350, termasukHarga: false)],
        rincianPajak: const [RincianPajak(nama: 'PPN', persen: 11, jumlah: 2970, termasukHarga: false)],
        pembulatan: -20,
        total: 31300,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 31300)],
      );
      const pengaturan = PengaturanStrukData(lebarKertasMm: 80);

      final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan);
      final lebar = 48;

      expect(baris, containsAllInOrder([
        BarisStruk.duaKolom('Subtotal', 'Rp30.000', lebar),
        BarisStruk.duaKolom('Diskon member', '-Rp1.000', lebar),
        BarisStruk.duaKolom('Promo Akhir Tahun', '-Rp2.000', lebar),
        BarisStruk.duaKolom('Service 5%', 'Rp1.350', lebar),
        BarisStruk.duaKolom('PPN 11%', 'Rp2.970', lebar),
        BarisStruk.duaKolom('Pembulatan', '-Rp20', lebar),
        BarisStruk.duaKolom('TOTAL', 'Rp31.300', lebar, tebal: true),
      ]));
      expect(baris, contains(const BarisStruk('Pelanggan: Sari')));
      _pastikanTidakOverflow(baris, lebar);
    });

    test('nama produk panjang di-wrap, tidak pernah melebihi lebar', () {
      final data = StrukData(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR004',
        tanggalEpochMs: _tanggal(9, 0),
        items: const [
          ItemStruk(
            namaProduk: 'Kopi Susu Gula Aren Signature Edisi Spesial Toko',
            qty: 1,
            hargaSatuan: 25000,
            subtotal: 25000,
          ),
        ],
        subtotal: 25000,
        total: 25000,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 25000)],
      );
      const pengaturan58 = PengaturanStrukData(lebarKertasMm: 58);
      const pengaturan80 = PengaturanStrukData(lebarKertasMm: 80);

      final baris58 = susunStrukTransaksi(data: data, pengaturan: pengaturan58);
      final baris80 = susunStrukTransaksi(data: data, pengaturan: pengaturan80);
      _pastikanTidakOverflow(baris58, 32);
      _pastikanTidakOverflow(baris80, 48);

      final gabungan58 = baris58.map((b) => b.teks).join(' ');
      expect(gabungan58, contains('Kopi Susu Gula Aren Signature Edisi Spesial Toko'));
    });
  });

  group('susunStrukTransaksi - kasbon', () {
    test('status sebagian: tampilkan dibayar, sisa tagihan, jatuh tempo (bukan kembali)', () {
      final data = StrukData(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR005',
        tanggalEpochMs: _tanggal(11, 0),
        namaPelanggan: 'Dedi',
        items: const [
          ItemStruk(namaProduk: 'Galon Air', qty: 1, hargaSatuan: 50000, subtotal: 50000),
        ],
        subtotal: 50000,
        total: 50000,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 20000)],
        statusBayar: 'sebagian',
        sisaTagihan: 30000,
        jatuhTempoEpochMs: _tanggal(11, 0) + Duration(days: 7).inMilliseconds,
      );
      const pengaturan = PengaturanStrukData(lebarKertasMm: 58);

      final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan);

      expect(baris, contains(BarisStruk.duaKolom('Tunai', 'Rp20.000', 32)));
      expect(baris, contains(BarisStruk.duaKolom('Sisa tagihan', 'Rp30.000', 32)));
      expect(baris, contains(BarisStruk.duaKolom('Jatuh tempo', '22/01/2026', 32)));
      expect(baris, isNot(contains(BarisStruk.duaKolom('Kembali', 'Rp0', 32))));
      _pastikanTidakOverflow(baris, 32);
    });
  });

  group('susunStrukTransaksi - struk ringkas', () {
    test('hanya item, total, pembayaran, kembalian - tanpa modifier/pajak/promo', () {
      final data = StrukData(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR006',
        tanggalEpochMs: _tanggal(12, 0),
        items: const [
          ItemStruk(
            namaProduk: 'Kopi Hitam',
            qty: 1,
            hargaSatuan: 15000,
            subtotal: 15000,
            modifiers: ['Extra shot'],
            catatan: 'Tanpa gula',
          ),
        ],
        subtotal: 15000,
        diskonPromo: 1000,
        namaPromo: 'Promo',
        rincianPajak: const [RincianPajak(nama: 'PPN', persen: 11, jumlah: 1540, termasukHarga: false)],
        total: 15540,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 20000)],
        kembalian: 4460,
        poinDidapat: 15,
        catatanTransaksi: 'Bungkus terpisah',
      );
      const pengaturan = PengaturanStrukData(lebarKertasMm: 58, strukRingkas: true);

      final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan);
      final isiTeks = baris.map((b) => b.teks).toList();

      expect(isiTeks, isNot(contains(contains('Extra shot'))));
      expect(isiTeks, isNot(contains(contains('Tanpa gula'))));
      expect(isiTeks, isNot(contains(contains('Promo'))));
      expect(isiTeks, isNot(contains(contains('PPN'))));
      expect(isiTeks, isNot(contains(contains('Subtotal'))));
      expect(isiTeks, isNot(contains(contains('Poin'))));
      expect(isiTeks, isNot(contains(contains('Bungkus terpisah'))));
      expect(baris, contains(const BarisStruk('Kopi Hitam')));
      expect(baris, contains(BarisStruk.duaKolom('TOTAL', 'Rp15.540', 32, tebal: true)));
      expect(baris, contains(BarisStruk.duaKolom('Kembali', 'Rp4.460', 32)));
      _pastikanTidakOverflow(baris, 32);
    });
  });

  group('susunStrukTransaksi - nomor antrean & salinan', () {
    test('nomor antrean huruf besar kalau fitur aktif', () {
      final data = StrukData(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR007',
        tanggalEpochMs: _tanggal(13, 0),
        nomorAntrean: 'a12',
        namaTipeOrder: 'Makan di tempat',
        items: const [
          ItemStruk(namaProduk: 'Kopi Hitam', qty: 1, hargaSatuan: 15000, subtotal: 15000),
        ],
        subtotal: 15000,
        total: 15000,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 15000)],
      );
      const pengaturanAktif = PengaturanStrukData(lebarKertasMm: 58, pakaiNomorAntrean: true);
      const pengaturanNonaktif = PengaturanStrukData(lebarKertasMm: 58, pakaiNomorAntrean: false);

      final barisAktif = susunStrukTransaksi(data: data, pengaturan: pengaturanAktif);
      final barisNonaktif = susunStrukTransaksi(data: data, pengaturan: pengaturanNonaktif);

      expect(
        barisAktif,
        contains(const BarisStruk('NO. ANTREAN: A12', rata: RataStruk.tengah, tebal: true, besar: true)),
      );
      expect(barisNonaktif.map((b) => b.teks), isNot(contains(contains('ANTREAN'))));
      _pastikanTidakOverflow(barisAktif, 32);
    });

    test('salinan menandai ** SALINAN ** setelah nomor struk', () {
      final data = StrukData(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR008',
        tanggalEpochMs: _tanggal(15, 0),
        items: const [
          ItemStruk(namaProduk: 'Kopi Hitam', qty: 1, hargaSatuan: 15000, subtotal: 15000),
        ],
        subtotal: 15000,
        total: 15000,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 15000)],
      );
      const pengaturan = PengaturanStrukData(lebarKertasMm: 58);

      final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan, salinan: true);
      final idx = baris.indexWhere((b) => b.teks == 'STR008');

      expect(
        baris[idx + 1],
        const BarisStruk('** SALINAN **', rata: RataStruk.tengah, tebal: true),
      );
      _pastikanTidakOverflow(baris, 32);
    });
  });

  group('susunStrukTransaksi - non-ASCII', () {
    test('header/footer/nama custom dgn emoji & kutip miring di-ASCII-fold', () {
      final data = StrukData(
        namaOutlet: 'Café “Kopi” Asik™',
        nomorStruk: 'STR009',
        tanggalEpochMs: _tanggal(16, 0),
        namaKasir: 'Rizky 😊',
        items: const [
          ItemStruk(namaProduk: 'Kopi — Susu', qty: 1, hargaSatuan: 15000, subtotal: 15000),
        ],
        subtotal: 15000,
        total: 15000,
        pembayaran: const [PembayaranStruk(labelMetode: 'Tunai', jumlah: 15000)],
      );
      const pengaturan = PengaturanStrukData(
        lebarKertasMm: 58,
        headerStruk: 'Selamat datang… 🎉',
        footerStruk: 'Sampai jumpa lagi 👋',
      );

      final baris = susunStrukTransaksi(data: data, pengaturan: pengaturan);
      final semuaTeks = baris.map((b) => b.teks).join('\n');

      expect(semuaTeks, isNot(contains('😊')));
      expect(semuaTeks, isNot(contains('🎉')));
      expect(semuaTeks, isNot(contains('👋')));
      expect(semuaTeks, isNot(contains('“')));
      expect(semuaTeks, isNot(contains('™')));
      expect(semuaTeks, isNot(contains('—')));
      expect(semuaTeks, contains('Caf'));
      expect(semuaTeks, contains('"Kopi"'));
      expect(semuaTeks, contains('Kopi - Susu'));
      expect(semuaTeks, contains('Selamat datang...'));
      _pastikanTidakOverflow(baris, 32);
    });
  });

  group('susunBuktiPelunasan', () {
    test('isi bukti pembayaran kasbon lengkap', () {
      const pengaturan = PengaturanStrukData(lebarKertasMm: 58);
      final baris = susunBuktiPelunasan(
        namaOutlet: 'Toko Kopi Asik',
        nomorStrukAsal: 'STR005',
        namaPelanggan: 'Dedi',
        jumlahDibayar: 30000,
        labelMetode: 'Tunai',
        sisaSetelahIni: 0,
        tanggalEpochMs: _tanggal(9, 15),
        pengaturan: pengaturan,
      );

      expect(baris, [
        const BarisStruk('Toko Kopi Asik', rata: RataStruk.tengah, tebal: true),
        const BarisStruk('--------------------------------'),
        const BarisStruk('BUKTI PEMBAYARAN KASBON', rata: RataStruk.tengah, tebal: true),
        const BarisStruk('Transaksi: STR005'),
        const BarisStruk('Pelanggan: Dedi'),
        const BarisStruk('15/01/2026 09:15'),
        const BarisStruk('--------------------------------'),
        BarisStruk.duaKolom('Dibayar', 'Rp30.000', 32, tebal: true),
        BarisStruk.duaKolom('Metode', 'Tunai', 32),
        BarisStruk.duaKolom('Sisa tagihan', 'Rp0', 32),
        const BarisStruk('--------------------------------'),
        const BarisStruk('Terima kasih', rata: RataStruk.tengah),
      ]);
      _pastikanTidakOverflow(baris, 32);
    });
  });

  group('susunStrukVoidRefund', () {
    test('refund menampilkan jumlah dikembalikan', () {
      const pengaturan = PengaturanStrukData(lebarKertasMm: 58);
      final baris = susunStrukVoidRefund(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR010',
        adalahRefund: true,
        alasan: 'Pesanan salah',
        items: const [
          ItemStruk(namaProduk: 'Kopi Hitam', qty: 1, hargaSatuan: 15000, subtotal: 15000),
        ],
        jumlahDikembalikan: 15000,
        tanggalEpochMs: _tanggal(10, 0),
        pengaturan: pengaturan,
      );

      expect(baris, contains(const BarisStruk('STRUK REFUND', rata: RataStruk.tengah, tebal: true)));
      expect(baris, contains(BarisStruk.duaKolom('Dikembalikan', 'Rp15.000', 32, tebal: true)));
      _pastikanTidakOverflow(baris, 32);
    });

    test('void tanpa pengembalian uang', () {
      const pengaturan = PengaturanStrukData(lebarKertasMm: 58);
      final baris = susunStrukVoidRefund(
        namaOutlet: 'Toko Kopi Asik',
        nomorStruk: 'STR011',
        adalahRefund: false,
        alasan: 'Salah input',
        items: const [
          ItemStruk(namaProduk: 'Kopi Hitam', qty: 1, hargaSatuan: 15000, subtotal: 15000),
        ],
        jumlahDikembalikan: 0,
        tanggalEpochMs: _tanggal(10, 0),
        pengaturan: pengaturan,
      );

      expect(baris, contains(const BarisStruk('STRUK VOID', rata: RataStruk.tengah, tebal: true)));
      expect(
        baris,
        contains(const BarisStruk('Transaksi dibatalkan, tidak ada uang keluar.')),
      );
      _pastikanTidakOverflow(baris, 32);
    });
  });

  group('susunRekapTutupShift', () {
    test('rekap lengkap dgn selisih kas', () {
      const pengaturan = PengaturanStrukData(lebarKertasMm: 80);
      final baris = susunRekapTutupShift(
        namaOutlet: 'Toko Kopi Asik',
        namaKasir: 'Budi',
        dibukaEpochMs: _tanggal(8, 0),
        ditutupEpochMs: _tanggal(17, 0),
        modalAwal: 100000,
        penjualanPerMetode: const [
          PembayaranStruk(labelMetode: 'Tunai', jumlah: 250000),
          PembayaranStruk(labelMetode: 'QRIS statis (cek manual)', jumlah: 50000),
        ],
        jumlahTransaksi: 12,
        kasSeharusnya: 350000,
        kasAktual: 345000,
        pengaturan: pengaturan,
      );

      expect(baris, contains(const BarisStruk('REKAP TUTUP SHIFT', rata: RataStruk.tengah, tebal: true)));
      expect(baris, contains(const BarisStruk('Jumlah transaksi: 12')));
      expect(baris, contains(BarisStruk.duaKolom('Kas seharusnya', 'Rp350.000', 48)));
      expect(baris, contains(BarisStruk.duaKolom('Kas aktual', 'Rp345.000', 48)));
      expect(baris, contains(BarisStruk.duaKolom('Selisih', '-Rp5.000', 48, tebal: true)));
      _pastikanTidakOverflow(baris, 48);
    });
  });
}
