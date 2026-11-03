import 'dart:convert';

import '../../transaksi/data/local/transaksi_dao.dart';
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
    final sekarang = DateTime.now().toUtc();
    final akhirHariIni = DateTime.utc(sekarang.year, sekarang.month, sekarang.day)
        .add(const Duration(days: 1));
    if (periode == PeriodeLaporan.custom) {
      final r = custom;
      if (r == null) return (akhirHariIni.subtract(const Duration(days: 1)).millisecondsSinceEpoch, akhirHariIni.millisecondsSinceEpoch);
      final (mulai, selesai) = r;
      final awal = DateTime.utc(mulai.year, mulai.month, mulai.day);
      final akhir = DateTime.utc(selesai.year, selesai.month, selesai.day).add(const Duration(days: 1));
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

  Future<RingkasanLaporan> ringkasan(
    String outletId,
    PeriodeLaporan periode, {
    (DateTime, DateTime)? rentangCustom,
  }) async {
    final (awalMs, akhirMs) = _rentang(periode, rentangCustom);
    final transaksiList = await _transaksiDao.transaksiSelesaiRentang(outletId, awalMs, akhirMs);
    final transaksiIds = [for (final t in transaksiList) t.id];

    final items = await _transaksiDao.itemUntukTransaksiList(transaksiIds);
    final pembayaranList = await _transaksiDao.pembayaranUntukTransaksiList(transaksiIds);

    final penjualanBersih = transaksiList.fold<int>(0, (a, b) => a + b.total);
    final labaKotor = items.fold<int>(
        0, (a, item) => a + ((item.hargaSatuan - item.hppSatuan) * item.qty).round());

    final jamTotal = <int, int>{};
    for (final t in transaksiList) {
      final jam = DateTime.fromMillisecondsSinceEpoch(t.tanggal, isUtc: true).toLocal().hour;
      jamTotal[jam] = (jamTotal[jam] ?? 0) + t.total;
    }
    final jamRamai = jamTotal.entries.map((e) => JamRamai(jam: e.key, total: e.value)).toList()
      ..sort((a, b) => a.jam.compareTo(b.jam));

    // Key (metodeBayarId, labelOverride) - BUKAN cuma metodeBayarId - supaya
    // QRIS manual/belum terverifikasi selalu jadi baris TERPISAH dari QRIS
    // yang sungguhan terverifikasi, walau metodeBayarId-nya sama persis
    // (sama alasan dgn backend laporan_service.py).
    final metodeTotal = <(String, String?), int>{};
    for (final p in pembayaranList) {
      final key = (p.metodeBayarId, _labelOverridePembayaran(p.payloadGateway));
      metodeTotal[key] = (metodeTotal[key] ?? 0) + p.jumlah;
    }
    final totalMetode = metodeTotal.values.fold<int>(0, (a, b) => a + b);
    final metodeBayar = metodeTotal.entries
        .map((e) => MetodeBayarPersen(
              metodeBayarId: e.key.$1,
              labelOverride: e.key.$2,
              total: e.value,
              persen: totalMetode == 0 ? 0 : e.value / totalMetode * 100,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    final produkQty = <String, double>{};
    final produkTotal = <String, int>{};
    for (final item in items) {
      produkQty[item.namaProduk] = (produkQty[item.namaProduk] ?? 0) + item.qty;
      produkTotal[item.namaProduk] = (produkTotal[item.namaProduk] ?? 0) + item.subtotal;
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
      labaKotor: labaKotor,
      jumlahTransaksi: transaksiList.length,
      jamRamai: jamRamai,
      metodeBayar: metodeBayar,
      produkTerlaris: produkTerlaris.take(5).toList(),
    );
  }
}
