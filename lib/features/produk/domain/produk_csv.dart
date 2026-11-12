/// Template, ekspor, dan pembacaan CSV produk (IMOGI no. 38 dan 39). FUNGSI MURNI tanpa berkas/jaringan
/// supaya bisa dites langsung. CSV dipilih karena bisa dibuka dan disunting di Excel/Google Sheets.
library;

import '../../../core/utils/csv_dasar.dart';

const kolomTemplate = ['nama', 'kategori', 'harga_jual', 'hpp', 'sku', 'barcode', 'deskripsi'];

/// Nama kolom lain yang dikenali (kunci = nama kolom di berkas, huruf kecil, tanpa spasi tepi).
const _alias = <String, String>{
  'nama': 'nama',
  'nama produk': 'nama',
  'produk': 'nama',
  'kategori': 'kategori',
  'harga_jual': 'harga_jual',
  'harga jual': 'harga_jual',
  'harga': 'harga_jual',
  'hpp': 'hpp',
  'harga beli': 'hpp',
  'harga_beli': 'hpp',
  'modal': 'hpp',
  'sku': 'sku',
  'barcode': 'barcode',
  'deskripsi': 'deskripsi',
  'keterangan': 'deskripsi',
};

/// Isi berkas template: judul kolom dan dua contoh baris yang jelas bukan data sungguhan.
String templateCsv() => '${kolomTemplate.join(',')}\n'
    'Kopi Susu,Minuman,18000,7000,KS-001,,Kopi susu gula aren\n'
    'Roti Bakar Coklat,Makanan,15000,6000,RB-001,,\n';

class BarisProdukCsv {
  const BarisProdukCsv({
    required this.nomorBaris,
    required this.nama,
    this.kategori,
    this.hargaJual = 0,
    this.hpp = 0,
    this.sku,
    this.barcode,
    this.deskripsi,
    this.masalah,
  });

  /// Nomor baris di berkas (baris 1 = judul kolom).
  final int nomorBaris;
  final String nama;
  final String? kategori;
  final int hargaJual;
  final int hpp;
  final String? sku;
  final String? barcode;
  final String? deskripsi;

  /// Alasan baris ini tidak dikirim (null = siap dikirim).
  final String? masalah;

  bool get valid => masalah == null;

  Map<String, dynamic> keJson() => {
        'nama': nama,
        if (kategori != null) 'kategori': kategori,
        'harga_jual': hargaJual,
        'hpp': hpp,
        if (sku != null) 'sku': sku,
        if (barcode != null) 'barcode': barcode,
        if (deskripsi != null) 'deskripsi': deskripsi,
      };
}

class HasilBacaCsv {
  const HasilBacaCsv({required this.baris, this.galat});

  final List<BarisProdukCsv> baris;

  /// Galat yang membuat seluruh berkas tidak bisa dipakai (mis. kolom nama tidak ada).
  final String? galat;

  Iterable<BarisProdukCsv> get siap => baris.where((b) => b.valid);
  Iterable<BarisProdukCsv> get bermasalah => baris.where((b) => !b.valid);
}

const maksBarisImpor = 500;

/// Membaca teks CSV. Pemisah (koma atau titik koma, umum di Excel Indonesia) dideteksi dari baris
/// judul. Baris kosong dilewati.
HasilBacaCsv bacaCsvProduk(String teks) {
  final rows = bacaBarisCsv(teks);
  if (rows.isEmpty) return const HasilBacaCsv(baris: [], galat: 'Berkas kosong');

  final judul = [for (final c in rows.first) _alias[c.trim().toLowerCase()] ?? ''];
  if (!judul.contains('nama')) {
    return const HasilBacaCsv(baris: [], galat: 'Kolom "nama" tidak ditemukan. Pakai template dari aplikasi.');
  }
  if (rows.length - 1 > maksBarisImpor) {
    return HasilBacaCsv(baris: const [], galat: 'Maksimal $maksBarisImpor produk sekali impor (berkas berisi ${rows.length - 1}).');
  }

  String? ambil(List<String> r, String kolom) {
    final i = judul.indexOf(kolom);
    if (i < 0 || i >= r.length) return null;
    final v = r[i].trim();
    return v.isEmpty ? null : v;
  }

  final hasil = <BarisProdukCsv>[];
  for (var n = 1; n < rows.length; n++) {
    final r = rows[n];
    final nomor = n + 1;
    final nama = ambil(r, 'nama');
    final harga = parseRupiahCsv(ambil(r, 'harga_jual'));
    final hpp = parseRupiahCsv(ambil(r, 'hpp'));

    String? masalah;
    if (nama == null) {
      masalah = 'Nama produk kosong';
    } else if (harga == null) {
      masalah = 'Harga jual "${ambil(r, 'harga_jual')}" tidak dapat dibaca';
    } else if (hpp == null) {
      masalah = 'HPP "${ambil(r, 'hpp')}" tidak dapat dibaca';
    } else if (harga < 0 || hpp < 0) {
      masalah = 'Harga tidak boleh negatif';
    }
    hasil.add(BarisProdukCsv(
      nomorBaris: nomor,
      nama: nama ?? '',
      kategori: ambil(r, 'kategori'),
      hargaJual: (harga ?? 0) < 0 ? 0 : (harga ?? 0),
      hpp: (hpp ?? 0) < 0 ? 0 : (hpp ?? 0),
      sku: ambil(r, 'sku'),
      barcode: ambil(r, 'barcode'),
      deskripsi: ambil(r, 'deskripsi'),
      masalah: masalah,
    ));
  }
  return HasilBacaCsv(baris: hasil);
}

/// "15000", "15.000", "Rp 15.000", "15,5" (koma desimal) -> bilangan bulat rupiah. Kosong -> 0.
/// Tidak terbaca -> null. Titik dianggap pemisah ribuan hanya bila polanya ribuan (1.000, 15.000.000).
int? parseRupiahCsv(String? teks) {
  var s = (teks ?? '').trim();
  if (s.isEmpty) return 0;
  s = s.replaceAll(RegExp(r'rp\.?', caseSensitive: false), '').replaceAll(' ', '');
  if (s.isEmpty) return 0;
  final negatif = s.startsWith('-');
  if (negatif) s = s.substring(1);
  if (RegExp(r'^\d{1,3}(\.\d{3})+(,\d+)?$').hasMatch(s)) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(s)) {
    s = s.replaceAll(',', '');
  } else if (RegExp(r'^\d+,\d+$').hasMatch(s)) {
    s = s.replaceAll(',', '.');
  }
  final angka = double.tryParse(s);
  if (angka == null) return null;
  final bulat = angka.round();
  return negatif ? -bulat : bulat;
}

/// Isi berkas ekspor: judul kolom template lalu satu baris per produk. Sel diberi tanda petik bila
/// perlu, dan sel berawalan = + - @ diberi apostrof agar tidak dibaca Excel sebagai rumus.
String eksporProdukCsv(Iterable<BarisEkspor> produk) {
  final sb = StringBuffer('﻿${kolomTemplate.join(',')}\n');
  for (final p in produk) {
    sb.writeln([
      p.nama,
      p.kategori ?? '',
      '${p.hargaJual}',
      '${p.hpp}',
      p.sku ?? '',
      p.barcode ?? '',
      p.deskripsi ?? '',
    ].map(selCsv).join(','));
  }
  return sb.toString();
}

class BarisEkspor {
  const BarisEkspor({
    required this.nama,
    this.kategori,
    required this.hargaJual,
    required this.hpp,
    this.sku,
    this.barcode,
    this.deskripsi,
  });

  final String nama;
  final String? kategori;
  final int hargaJual;
  final int hpp;
  final String? sku;
  final String? barcode;
  final String? deskripsi;
}

