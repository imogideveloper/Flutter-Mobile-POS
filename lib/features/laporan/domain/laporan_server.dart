import '../../../core/network/sync_mapping.dart' show uangDariBackend;
import 'ringkasan_laporan.dart';

/// HP hanya menyimpan transaksi yang dibuat di HP itu atau yang pernah tersinkron ke sana. Setelah masuk ulang,
/// pasang ulang, atau ganti HP, transaksi lama tidak ada di database lokal. Laporan perlu data server bila awal
/// periode lebih lama dari transaksi lokal tertua (dibulatkan ke awal hari, supaya "Hari ini" tidak dianggap kurang)
/// atau bila lokal sama sekali kosong.
bool laporanPerluDataServer({required int awalMs, required int? palingAwalLokalMs}) {
  if (palingAwalLokalMs == null) return true;
  final awalLokal = DateTime.fromMillisecondsSinceEpoch(palingAwalLokalMs, isUtc: true).toLocal();
  final awalHariLokal = DateTime(awalLokal.year, awalLokal.month, awalLokal.day);
  final awalPeriode = DateTime.fromMillisecondsSinceEpoch(awalMs, isUtc: true).toLocal();
  return awalPeriode.isBefore(awalHariLokal);
}

/// Susun RingkasanLaporan dari jawaban server (`/laporan/penjualan` dan `/laporan/produk-terlaris`).
/// Server tidak mengirim margin per produk, penjualan harian, dan tren per produk/kategori, jadi bagian itu kosong.
/// Jam ramai dari server dalam UTC; digeser ke zona waktu HP agar sama dengan hitungan lokal.
RingkasanLaporan ringkasanDariServer({
  required Map<String, dynamic> penjualan,
  required List<dynamic> terlaris,
  Map<String, dynamic>? sebelumnya,
  Duration zona = Duration.zero,
}) {
  final geserJam = zona.inHours;
  final jam = <int, int>{};
  for (final j in (penjualan['jam_ramai'] as List? ?? const [])) {
    final m = j as Map<String, dynamic>;
    final lokal = (((m['jam'] as num).toInt() + geserJam) % 24 + 24) % 24;
    jam[lokal] = (jam[lokal] ?? 0) + uangDariBackend(m['total'].toString());
  }
  final jamRamai = [for (final e in jam.entries) JamRamai(jam: e.key, total: e.value)]..sort((a, b) => a.jam.compareTo(b.jam));

  final metode = [
    for (final m in (penjualan['metode_bayar'] as List? ?? const []))
      MetodeBayarPersen(
        metodeBayarId: (m as Map<String, dynamic>)['metode_bayar_id'] as String,
        total: uangDariBackend(m['total'].toString()),
        persen: double.parse(m['persen'].toString()),
      ),
  ];

  int? sebelumnyaBersih;
  if (sebelumnya != null && (sebelumnya['jumlah_transaksi'] as num).toInt() > 0) {
    sebelumnyaBersih = uangDariBackend(sebelumnya['penjualan_bersih'].toString());
  }

  return RingkasanLaporan(
    penjualanBersih: uangDariBackend(penjualan['penjualan_bersih'].toString()),
    pajakService: uangDariBackend((penjualan['pajak_service'] ?? '0').toString()),
    totalPenerimaan: uangDariBackend((penjualan['total_penerimaan'] ?? '0').toString()),
    labaKotor: uangDariBackend(penjualan['laba_kotor'].toString()),
    jumlahTransaksi: (penjualan['jumlah_transaksi'] as num).toInt(),
    jamRamai: jamRamai,
    metodeBayar: metode,
    produkTerlaris: [
      for (final t in terlaris)
        ProdukTerlaris(
          namaProduk: (t as Map<String, dynamic>)['nama_produk'] as String,
          qty: double.parse(t['qty'].toString()),
          total: uangDariBackend(t['total'].toString()),
        ),
    ],
    penjualanPeriodeSebelumnya: sebelumnyaBersih,
    dariServer: true,
  );
}
