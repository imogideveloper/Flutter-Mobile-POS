import 'dart:convert';

import '../../../core/database/app_database.dart' show ItemTransaksiRow;
import '../../transaksi/data/local/transaksi_dao.dart';
import '../domain/angka_penjualan.dart';
import '../domain/ringkasan_laporan.dart';

enum PeriodeLaporan { hariIni, tujuhHari, tigaPuluhHari, custom }

/// Temuan A.1 (tahap 5) - mirror PERSIS `_label_pembayaran` di
/// backend/app/services/laporan_service.py, supaya laporan lokal (offline)
/// dan laporan server menampilkan pemisahan yang sama. null = tidak ada
/// override, UI pakai nama metode bayar biasa (lookup terpisah by id,
/// tidak berubah dari sebelumnya).
String? _labelOverridePembayaran(String? payloadGatewayJson) {
  if (payloadGatewayJson == null) return null;
  final decoded = jsonDecode(payloadGatewayJson);
  if (decoded is Map && decoded['metode'] == 'qris_statis_manual') {
    return 'QRIS manual (belum terverifikasi)';
  }
  return null;
}

/// Label tujuan pembayaran (IMOGI no. 18) dari payload_gateway; mirror `_label_pembayaran` di server.
String? _labelTujuanPembayaran(String? payloadGatewayJson) {
  if (payloadGatewayJson == null) return null;
  final decoded = jsonDecode(payloadGatewayJson);
  if (decoded is! Map) return null;
  // Kartu: jenis (Debit/Kredit) lebih dulu, lalu mesin EDC/tujuan, mis. "Debit · EDC BCA".
  final jenis = switch (decoded['jenis_kartu']) { 'debit' => 'Debit', 'kredit' => 'Kredit', _ => null };
  final tujuan = decoded['label_tujuan'];
  final bagian = [
    ?jenis,
    if (tujuan is String && tujuan.trim().isNotEmpty) tujuan.trim(),
  ];
  return bagian.isEmpty ? null : bagian.join(' · ');
}

/// F3.C - fitur 'laporan_dasar': null batasHari = paket tanpa batas
/// (Bisnis), selain itu rentang (inklusif kedua ujung) tidak boleh
/// melebihi batasHari. Dipisah dari LaporanPage supaya gatingnya bisa
/// dites langsung tanpa perlu drive date range picker sungguhan.
bool rentangLaporanMelebihiBatas({required int jumlahHari, required int? batasHari}) {
  return batasHari != null && jumlahHari > batasHari;
}

class LaporanRepository {
  LaporanRepository(this._transaksiDao);

  final TransaksiDao _transaksiDao;

  // (DateTime awal, DateTime akhir) - record biasa, BUKAN DateTimeRange
  // (package:flutter/material.dart) supaya layer data ini tidak perlu
  // tergantung framework UI.
  (int awalMs, int akhirMs) _rentang(PeriodeLaporan periode, (DateTime, DateTime)? custom) {
    // Hari menurut jam HP (bukan UTC): transaksi 00.00-07.00 WIB harus masuk "Hari ini", bukan kemarin.
    final sekarang = DateTime.now();
    final akhirHariIni = DateTime(sekarang.year, sekarang.month, sekarang.day)
        .add(const Duration(days: 1));
    if (periode == PeriodeLaporan.custom) {
      final r = custom;
      if (r == null) return (akhirHariIni.subtract(const Duration(days: 1)).millisecondsSinceEpoch, akhirHariIni.millisecondsSinceEpoch);
      final (mulai, selesai) = r;
      final awal = DateTime(mulai.year, mulai.month, mulai.day);
      final akhir = DateTime(selesai.year, selesai.month, selesai.day + 1);
      return (awal.millisecondsSinceEpoch, akhir.millisecondsSinceEpoch);
    }
    final jumlahHari = switch (periode) {
      PeriodeLaporan.hariIni => 1,
      PeriodeLaporan.tujuhHari => 7,
      PeriodeLaporan.tigaPuluhHari => 30,
      PeriodeLaporan.custom => 1, // tidak pernah dipakai - cabang custom ditangani di atas
    };
    final awal = akhirHariIni.subtract(Duration(days: jumlahHari));
    return (awal.millisecondsSinceEpoch, akhirHariIni.millisecondsSinceEpoch);
  }

  /// Batas periode (epoch ms, awal inklusif, akhir eksklusif) yang dipakai ringkasan lokal; dipakai juga untuk
  /// meminta rentang yang sama ke server.
  (int awalMs, int akhirMs) rentang(PeriodeLaporan periode, {(DateTime, DateTime)? rentangCustom}) =>
      _rentang(periode, rentangCustom);

  Future<int?> tanggalAwalLokal(String outletId) => _transaksiDao.tanggalTransaksiPalingAwal(outletId);

  Future<RingkasanLaporan> ringkasan(
    String outletId,
    PeriodeLaporan periode, {
    (DateTime, DateTime)? rentangCustom,
  }) async {
    final (awalMs, akhirMs) = _rentang(periode, rentangCustom);
    // Penjualan = transaksi selesai + refund sebagian (refund penuh dan void tidak ikut). Angka dihitung per
    // transaksi setelah dikurangi refund yang tercatat di HP ini (lihat angka_penjualan.dart).
    final transaksiList = await _transaksiDao.transaksiPenjualanRentang(outletId, awalMs, akhirMs);
    final transaksiIds = [for (final t in transaksiList) t.id];
    final angka = angkaPenjualanPerTransaksi(transaksiList, await _transaksiDao.totalRefundPerTransaksi(transaksiIds));
    final angkaTotal = jumlahkanAngkaPenjualan(angka.values);

    final items = await _itemSetelahRefund(await _transaksiDao.itemUntukTransaksiList(transaksiIds));
    final pembayaranList = await _transaksiDao.pembayaranUntukTransaksiList(transaksiIds);

    final penjualanBersih = angkaTotal.penjualanBersih;
    // Laba kotor per item: harga x qty yang masih terjual dikurangi HPP x qty yang HPP-nya masih ditanggung.
    final labaKotor = items.fold<int>(0, (a, item) => a + item.labaKotor);

    final jamTotal = <int, int>{};
    for (final t in transaksiList) {
      final jam = DateTime.fromMillisecondsSinceEpoch(t.tanggal, isUtc: true).toLocal().hour;
      jamTotal[jam] = (jamTotal[jam] ?? 0) + angka[t.id]!.penjualanBersih;
    }
    final jamRamai = jamTotal.entries.map((e) => JamRamai(jam: e.key, total: e.value)).toList()
      ..sort((a, b) => a.jam.compareTo(b.jam));

    // Key (metodeBayarId, labelOverride) - BUKAN cuma metodeBayarId - supaya
    // QRIS manual/belum terverifikasi selalu jadi baris TERPISAH dari QRIS
    // yang sungguhan terverifikasi, walau metodeBayarId-nya sama persis
    // (sama alasan dgn backend laporan_service.py).
    // Label tujuan (IMOGI no. 18) ikut kunci: GoPay dan OVO jadi baris terpisah untuk rekonsiliasi.
    // Periode sebelumnya sama panjang, tepat sebelum rentang ini (pembanding tren).
    final panjang = akhirMs - awalMs;
    final sebelumnya = await _transaksiDao.transaksiPenjualanRentang(outletId, awalMs - panjang, awalMs);
    final angkaSebelumnya = angkaPenjualanPerTransaksi(
      sebelumnya,
      await _transaksiDao.totalRefundPerTransaksi([for (final t in sebelumnya) t.id]),
    );
    final penjualanSebelumnya =
        sebelumnya.isEmpty ? null : jumlahkanAngkaPenjualan(angkaSebelumnya.values).penjualanBersih;

    final itemSebelumnya =
        await _itemSetelahRefund(await _transaksiDao.itemUntukTransaksiList([for (final t in sebelumnya) t.id]));
    final kategoriProduk = await _transaksiDao.namaKategoriPerProduk({
      for (final i in [...items, ...itemSebelumnya]) i.item.produkId,
    });
    Map<String, int> omzetPer(List<ItemTerjual> daftar, String Function(ItemTransaksiRow) kunci) {
      final m = <String, int>{};
      for (final i in daftar) {
        m[kunci(i.item)] = (m[kunci(i.item)] ?? 0) + i.subtotal;
      }
      return m;
    }

    String namaProduk(ItemTransaksiRow i) => i.namaProduk;
    String namaKategori(ItemTransaksiRow i) => kategoriProduk[i.produkId] ?? 'Tanpa kategori';

    final penjualanHarian = _susunPenjualanHarian(
      transaksiList.map((t) => (t.tanggal, angka[t.id]!.penjualanBersih)),
      awalMs,
      akhirMs,
    );

    final metodeTotal = <(String, String?, String?), int>{};
    for (final p in pembayaranList) {
      final key = (
        p.metodeBayarId,
        _labelOverridePembayaran(p.payloadGateway),
        _labelTujuanPembayaran(p.payloadGateway),
      );
      metodeTotal[key] = (metodeTotal[key] ?? 0) + p.jumlah;
    }
    final totalMetode = metodeTotal.values.fold<int>(0, (a, b) => a + b);
    final metodeBayar = metodeTotal.entries
        .map((e) => MetodeBayarPersen(
              metodeBayarId: e.key.$1,
              labelOverride: e.key.$2,
              labelTujuan: e.key.$3,
              total: e.value,
              persen: totalMetode == 0 ? 0 : e.value / totalMetode * 100,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    final produkQty = <String, double>{};
    final produkTotal = <String, int>{};
    for (final terjual in items) {
      if (terjual.qty <= 0) continue; // seluruh qty item ini sudah direfund
      final nama = terjual.item.namaProduk;
      produkQty[nama] = (produkQty[nama] ?? 0) + terjual.qty;
      produkTotal[nama] = (produkTotal[nama] ?? 0) + terjual.subtotal;
    }
    final produkTerlaris = produkTotal.entries
        .map((e) => ProdukTerlaris(
              namaProduk: e.key,
              qty: produkQty[e.key] ?? 0,
              total: e.value,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return RingkasanLaporan(
      penjualanBersih: penjualanBersih,
      pajakService: angkaTotal.pajakService,
      totalPenerimaan: angkaTotal.totalPenerimaan,
      labaKotor: labaKotor,
      jumlahTransaksi: transaksiList.length,
      jamRamai: jamRamai,
      metodeBayar: metodeBayar,
      produkTerlaris: produkTerlaris.take(5).toList(),
      penjualanHarian: penjualanHarian,
      penjualanPeriodeSebelumnya: penjualanSebelumnya,
      trenProduk: hitungTren(omzetPer(items, namaProduk), omzetPer(itemSebelumnya, namaProduk)),
      trenKategori: hitungTren(omzetPer(items, namaKategori), omzetPer(itemSebelumnya, namaKategori)),
      marginProduk: hitungMarginProduk([
        for (final terjual in items)
          BarisItemMargin(
            nama: terjual.item.namaProduk,
            qty: terjual.qty,
            omzet: terjual.subtotal,
            hpp: terjual.hpp,
          ),
      ]),
    );
  }

  /// Item dengan qty yang masih terjual setelah dikurangi refund yang tercatat di HP ini.
  Future<List<ItemTerjual>> _itemSetelahRefund(List<ItemTransaksiRow> items) async {
    final refund = await _transaksiDao.refundPerItem([for (final i in items) i.id]);
    return itemTerjual(items, {
      for (final e in refund.entries) e.key: RefundItem(qty: e.value.qty, qtyKembaliStok: e.value.qtyKembaliStok),
    });
  }
}

/// Total penjualan per hari UTC (batas yang sama dengan periode laporan) dari [awalMs] sampai [akhirMs] (eksklusif); hari tanpa transaksi
/// bernilai 0 supaya grafik tren tidak melompati hari kosong. Dibatasi 92 hari agar grafik tetap terbaca.
List<PenjualanHarian> susunPenjualanHarian(Iterable<(int, int)> transaksi, int awalMs, int akhirMs) =>
    _susunPenjualanHarian(transaksi, awalMs, akhirMs);

List<PenjualanHarian> _susunPenjualanHarian(Iterable<(int, int)> transaksi, int awalMs, int akhirMs) {
  // Hari menurut jam HP, sama dengan batas periode laporan, supaya 7 hari = 7 batang.
  DateTime hari(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day);
  }

  final total = <DateTime, int>{};
  for (final (ms, jumlah) in transaksi) {
    final h = hari(ms);
    total[h] = (total[h] ?? 0) + jumlah;
  }
  final awal = hari(awalMs);
  final akhir = hari(akhirMs - 1);
  final hasil = <PenjualanHarian>[];
  for (var h = awal; !h.isAfter(akhir) && hasil.length < 92; h = DateTime(h.year, h.month, h.day + 1)) {
    hasil.add(PenjualanHarian(tanggal: h, total: total[h] ?? 0));
  }
  return hasil;
}
