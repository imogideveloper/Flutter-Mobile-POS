import '../data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import 'mutasi_item.dart';

/// Riwayat mutasi stok per produk (IMOGI no. 49, Kelola stok produk). FUNGSI MURNI.

/// Nama jenis mutasi yang tampil ke pengguna.
String labelMutasi(MutasiJenis jenis) => switch (jenis) {
      MutasiJenis.stokAwal => 'Stok awal',
      MutasiJenis.pembelian => 'Pembelian',
      MutasiJenis.penjualan => 'Penjualan',
      MutasiJenis.refund => 'Refund',
      MutasiJenis.voidTransaksi => 'Void',
      MutasiJenis.opname => 'Opname',
      MutasiJenis.transferMasuk => 'Transfer masuk',
      MutasiJenis.transferKeluar => 'Transfer keluar',
      MutasiJenis.penyesuaian => 'Penyesuaian',
      MutasiJenis.produksi => 'Produksi',
    };

enum FilterMutasi { semua, masuk, keluar }

List<MutasiItem> saringMutasi(List<MutasiItem> items, FilterMutasi filter) => switch (filter) {
      FilterMutasi.semua => items,
      FilterMutasi.masuk => [for (final m in items) if (m.qty > 0) m],
      FilterMutasi.keluar => [for (final m in items) if (m.qty < 0) m],
    };

/// Total barang masuk (positif) dan keluar (dikembalikan sebagai angka positif) dari [items].
({double masuk, double keluar}) ringkasMutasi(List<MutasiItem> items) {
  var masuk = 0.0, keluar = 0.0;
  for (final m in items) {
    if (m.qty > 0) {
      masuk += m.qty;
    } else {
      keluar += -m.qty;
    }
  }
  return (masuk: masuk, keluar: keluar);
}
