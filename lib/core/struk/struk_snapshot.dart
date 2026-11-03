import '../../features/promo/domain/rincian_pajak.dart';
import 'penyusun_struk.dart';

/// Temuan A.2 (tahap 5) - serialisasi [StrukData]+[PengaturanStrukData]
/// jadi/dari JSON MURNI (tanpa dependency Flutter/drift) supaya bisa
/// disimpan sbg satu blob (lokal drift `transaksi.snapshotStruk` DAN
/// backend `transaksi.snapshot_struk`) tepat seperti kondisi saat
/// transaksi dibuat - cetak ulang nanti pakai snapshot ini, BUKAN
/// rekonstruksi dari data/pengaturan outlet SAAT INI (yang bisa sudah
/// beda, lihat docs/aturan_harga.md).
Map<String, dynamic> strukSnapshotKeJson(StrukData data, PengaturanStrukData pengaturan) {
  return {
    'data': {
      'namaOutlet': data.namaOutlet,
      'nomorStruk': data.nomorStruk,
      'tanggalEpochMs': data.tanggalEpochMs,
      'namaKasir': data.namaKasir,
      'namaPelanggan': data.namaPelanggan,
      'namaTipeOrder': data.namaTipeOrder,
      'namaMeja': data.namaMeja,
      'nomorAntrean': data.nomorAntrean,
      'items': [
        for (final item in data.items)
          {
            'namaProduk': item.namaProduk,
            'qty': item.qty,
            'hargaSatuan': item.hargaSatuan,
            'subtotal': item.subtotal,
            'modifiers': item.modifiers,
            'catatan': item.catatan,
          },
      ],
      'subtotal': data.subtotal,
      'diskonMember': data.diskonMember,
      'diskonPromo': data.diskonPromo,
      'namaPromo': data.namaPromo,
      'rincianService': [
        for (final r in data.rincianService)
          {'nama': r.nama, 'persen': r.persen, 'jumlah': r.jumlah, 'termasukHarga': r.termasukHarga},
      ],
      'rincianPajak': [
        for (final r in data.rincianPajak)
          {'nama': r.nama, 'persen': r.persen, 'jumlah': r.jumlah, 'termasukHarga': r.termasukHarga},
      ],
      'pembulatan': data.pembulatan,
      'total': data.total,
      'pembayaran': [
        for (final p in data.pembayaran) {'labelMetode': p.labelMetode, 'jumlah': p.jumlah},
      ],
      'kembalian': data.kembalian,
      'statusBayar': data.statusBayar,
      'sisaTagihan': data.sisaTagihan,
      'jatuhTempoEpochMs': data.jatuhTempoEpochMs,
      'poinDidapat': data.poinDidapat,
      'catatanTransaksi': data.catatanTransaksi,
    },
    'pengaturan': {
      'headerStruk': pengaturan.headerStruk,
      'footerStruk': pengaturan.footerStruk,
      'lebarKertasMm': pengaturan.lebarKertasMm,
      'tampilLogo': pengaturan.tampilLogo,
      'strukRingkas': pengaturan.strukRingkas,
      'pakaiNomorAntrean': pengaturan.pakaiNomorAntrean,
      'zonaWaktu': pengaturan.zonaWaktu,
    },
  };
}

({StrukData data, PengaturanStrukData pengaturan}) strukSnapshotDariJson(Map<String, dynamic> json) {
  final d = json['data'] as Map<String, dynamic>;
  final p = json['pengaturan'] as Map<String, dynamic>;

  final data = StrukData(
    namaOutlet: d['namaOutlet'] as String,
    nomorStruk: d['nomorStruk'] as String,
    tanggalEpochMs: d['tanggalEpochMs'] as int,
    namaKasir: d['namaKasir'] as String?,
    namaPelanggan: d['namaPelanggan'] as String?,
    namaTipeOrder: d['namaTipeOrder'] as String?,
    namaMeja: d['namaMeja'] as String?,
    nomorAntrean: d['nomorAntrean'] as String?,
    items: [
      for (final item in (d['items'] as List))
        ItemStruk(
          namaProduk: (item as Map<String, dynamic>)['namaProduk'] as String,
          qty: (item['qty'] as num).toDouble(),
          hargaSatuan: item['hargaSatuan'] as int,
          subtotal: item['subtotal'] as int,
          modifiers: ((item['modifiers'] as List?) ?? const []).cast<String>(),
          catatan: item['catatan'] as String?,
        ),
    ],
    subtotal: d['subtotal'] as int,
    diskonMember: (d['diskonMember'] as int?) ?? 0,
    diskonPromo: (d['diskonPromo'] as int?) ?? 0,
    namaPromo: d['namaPromo'] as String?,
    rincianService: [
      for (final r in (d['rincianService'] as List? ?? const []))
        RincianPajak(
          nama: (r as Map<String, dynamic>)['nama'] as String,
          persen: (r['persen'] as num).toDouble(),
          jumlah: r['jumlah'] as int,
          termasukHarga: r['termasukHarga'] as bool,
        ),
    ],
    rincianPajak: [
      for (final r in (d['rincianPajak'] as List? ?? const []))
        RincianPajak(
          nama: (r as Map<String, dynamic>)['nama'] as String,
          persen: (r['persen'] as num).toDouble(),
          jumlah: r['jumlah'] as int,
          termasukHarga: r['termasukHarga'] as bool,
        ),
    ],
    pembulatan: (d['pembulatan'] as int?) ?? 0,
    total: d['total'] as int,
    pembayaran: [
      for (final p2 in (d['pembayaran'] as List? ?? const []))
        PembayaranStruk(
          labelMetode: (p2 as Map<String, dynamic>)['labelMetode'] as String,
          jumlah: p2['jumlah'] as int,
        ),
    ],
    kembalian: (d['kembalian'] as int?) ?? 0,
    statusBayar: (d['statusBayar'] as String?) ?? 'lunas',
    sisaTagihan: (d['sisaTagihan'] as int?) ?? 0,
    jatuhTempoEpochMs: d['jatuhTempoEpochMs'] as int?,
    poinDidapat: d['poinDidapat'] as int?,
    catatanTransaksi: d['catatanTransaksi'] as String?,
  );

  final pengaturan = PengaturanStrukData(
    headerStruk: p['headerStruk'] as String?,
    footerStruk: p['footerStruk'] as String?,
    lebarKertasMm: (p['lebarKertasMm'] as int?) ?? 58,
    tampilLogo: (p['tampilLogo'] as bool?) ?? false,
    strukRingkas: (p['strukRingkas'] as bool?) ?? false,
    pakaiNomorAntrean: (p['pakaiNomorAntrean'] as bool?) ?? false,
    zonaWaktu: (p['zonaWaktu'] as String?) ?? 'Asia/Jakarta',
  );

  return (data: data, pengaturan: pengaturan);
}
