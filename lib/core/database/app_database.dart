import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/absensi/data/local/tables/absensi_table.dart';
import '../../features/dapur/data/local/tables/antrean_harian_table.dart';
import '../../features/dapur/data/local/tables/item_pesanan_dapur_table.dart';
import '../../features/dapur/data/local/meja_dao.dart';
import '../../features/dapur/data/local/tables/meja_table.dart';
import '../../features/dapur/data/local/tables/pesanan_dapur_table.dart';
import '../../features/dapur/data/local/tables/stasiun_dapur_table.dart';
import '../../features/fitur/data/local/fitur_dao.dart';
import '../../features/fitur/data/local/tables/batas_fitur_table.dart';
import '../../features/fitur/data/local/tables/fitur_aktif_table.dart';
import '../../features/fitur/data/local/tables/fitur_table.dart';
import '../../features/fitur/data/local/tables/paket_fitur_table.dart';
import '../../features/fitur/data/local/tables/status_fitur_toko_table.dart';
import '../../features/order/data/local/tables/tipe_order_pajak_table.dart';
import '../../features/order/data/local/tables/tipe_order_table.dart';
import '../../features/order/data/local/tipe_order_dao.dart';
import '../../features/pelanggan/data/local/pelanggan_dao.dart';
import '../../features/pelanggan/data/local/tables/aturan_poin_table.dart';
import '../../features/pelanggan/data/local/tables/level_member_table.dart';
import '../../features/pelanggan/data/local/tables/pelanggan_table.dart';
import '../../features/pelanggan/data/local/tables/riwayat_poin_table.dart';
import '../../features/produk/data/local/harga_dao.dart';
import '../../features/produk/data/local/produk_dao.dart';
import '../../features/produk/data/local/satuan_dao.dart';
import '../../features/produk/data/local/tables/bundling_item_table.dart';
import '../../features/produk/data/local/tables/grup_modifier_table.dart';
import '../../features/produk/data/local/tables/harga_grosir_table.dart';
import '../../features/produk/data/local/tables/harga_outlet_table.dart';
import '../../features/produk/data/local/tables/kategori_table.dart';
import '../../features/produk/data/local/tables/modifier_table.dart';
import '../../features/produk/data/local/tables/produk_grup_modifier_table.dart';
import '../../features/produk/data/local/tables/produk_pajak_table.dart';
import '../../features/produk/data/local/tables/produk_table.dart';
import '../../features/produk/data/local/tables/produk_varian_table.dart';
import '../../features/produk/data/local/tables/resep_table.dart';
import '../../features/produk/data/local/tables/satuan_table.dart';
import '../../features/promo/data/local/pajak_dao.dart';
import '../../features/promo/data/local/promo_dao.dart';
import '../../features/promo/data/local/tables/pajak_table.dart';
import '../../features/promo/data/local/tables/promo_produk_table.dart';
import '../../features/promo/data/local/tables/promo_table.dart';
import '../../features/shift/data/local/shift_dao.dart';
import '../../features/shift/data/local/tables/kas_shift_table.dart';
import '../../features/shift/data/local/tables/shift_table.dart';
import '../../features/stok/data/local/stok_dao.dart';
import '../../features/stok/data/local/tables/batch_stok_table.dart';
import '../../features/stok/data/local/tables/mutasi_stok_table.dart';
import '../../features/stok/data/local/tables/stok_table.dart';
import '../../features/survei/data/local/tables/item_jawaban_survei_table.dart';
import '../../features/survei/data/local/tables/jawaban_survei_table.dart';
import '../../features/survei/data/local/tables/pertanyaan_survei_table.dart';
import '../../features/survei/data/local/tables/survei_table.dart';
import '../../features/transaksi/data/local/tables/item_refund_table.dart';
import '../../features/transaksi/data/local/tables/item_transaksi_modifier_table.dart';
import '../../features/transaksi/data/local/tables/item_transaksi_table.dart';
import '../../features/transaksi/data/local/tables/metode_bayar_table.dart';
import '../../features/transaksi/data/local/tables/pembayaran_table.dart';
import '../../features/transaksi/data/local/tables/pesanan_batal_table.dart';
import '../../features/transaksi/data/local/tables/refund_table.dart';
import '../../features/transaksi/data/local/tables/transaksi_pajak_table.dart';
import '../../features/transaksi/data/local/tables/transaksi_promo_table.dart';
import '../../features/transaksi/data/local/tables/transaksi_table.dart';
import '../../features/transaksi/data/local/metode_bayar_dao.dart';
import '../../features/transaksi/data/local/transaksi_dao.dart';
import 'pairing_dao.dart';
import 'pengaturan_printer_dao.dart';
import 'pengguna_dao.dart';
import 'tables/akses_outlet_table.dart';
import 'tables/izin_table.dart';
import 'tables/outlets_table.dart';
import 'tables/pengaturan_outlet_table.dart';
import 'tables/pengaturan_printer_table.dart';
import 'tables/pengguna_table.dart';
import 'tables/perangkat_table.dart';
import 'tables/role_izin_table.dart';
import 'tables/role_izin_sync_table.dart';
import 'tables/role_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Outlets,
    PengaturanOutlet,
    Pengguna,
    Perangkat,
    Role,
    RoleIzinSync,
    Izin,
    RoleIzin,
    AksesOutlet,
    Kategori,
    Satuan,
    Produk,
    ProdukVarian,
    HargaOutlet,
    GrupModifier,
    Modifier,
    ProdukGrupModifier,
    Resep,
    ProdukPajak,
    BundlingItem,
    HargaGrosir,
    Stok,
    MutasiStok,
    BatchStok,
    Pelanggan,
    RiwayatPoin,
    LevelMember,
    AturanPoin,
    Pajak,
    Promo,
    PromoProduk,
    MetodeBayar,
    Shift,
    KasShift,
    Transaksi,
    ItemTransaksi,
    ItemTransaksiModifier,
    TransaksiPajak,
    TransaksiPromo,
    Pembayaran,
    Refund,
    ItemRefund,
    PesananBatal,
    Fitur,
    PaketFitur,
    StatusFiturToko,
    FiturAktif,
    BatasFitur,
    TipeOrder,
    TipeOrderPajak,
    Meja,
    StasiunDapur,
    PesananDapur,
    ItemPesananDapur,
    AntreanHarian,
    Absensi,
    Survei,
    PertanyaanSurvei,
    JawabanSurvei,
    ItemJawabanSurvei,
    PengaturanPrinter,
  ],
  daos: [
    ProdukDao,
    SatuanDao,
    StokDao,
    ShiftDao,
    TransaksiDao,
    PajakDao,
    PenggunaDao,
    PelangganDao,
    PromoDao,
    TipeOrderDao,
    MejaDao,
    MetodeBayarDao,
    PairingDao,
    FiturDao,
    HargaDao,
    PengaturanPrinterDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) => m.createAll(),
        onUpgrade: (Migrator m, int from, int to) async {
          // v1 -> v2: tabel cache gating paket (StatusFiturToko/FiturAktif/
          // BatasFitur) - baru, tidak ada data lama yang perlu dipindahkan.
          if (from < 2) {
            await m.createTable(statusFiturToko);
            await m.createTable(fiturAktif);
            await m.createTable(batasFitur);
          }
          // v2 -> v3 (tahap 3b-1, kasbon): pembayaran.shiftId + disinkronPada
          // (cicilan/pelunasan bisa dibayar di shift lain & disync terpisah
          // dari transaksi induknya), pelanggan.batasKasbon (opsional).
          if (from < 3) {
            await m.addColumn(pembayaran, pembayaran.shiftId);
            await m.addColumn(pembayaran, pembayaran.disinkronPada);
            await m.addColumn(pelanggan, pelanggan.batasKasbon);
          }
          // v3 -> v4 (tahap 4, printer): pengaturan printer Bluetooth lokal
          // per HP - baru, tidak ada data lama yang perlu dipindahkan.
          if (from < 4) {
            await m.createTable(pengaturanPrinter);
          }
          // v4 -> v5 (temuan#2, rapikan F3.E) - antrean pembatalan pesanan
          // tersimpan yang belum tersync ke server - baru, tidak ada data
          // lama yang perlu dipindahkan.
          if (from < 5) {
            await m.createTable(pesananBatal);
          }
          // v5 -> v6 (temuan A.2, rapikan tahap 5) - snapshot struk per
          // transaksi, utk cetak ulang identik - kolom baru nullable,
          // transaksi lama otomatis NULL (fallback rekonstruksi lama).
          if (from < 6) {
            await m.addColumn(transaksi, transaksi.snapshotStruk);
          }
          // v6 -> v7 (tahap 5b, satukan identitas karyawan) - kolom baru
          // nullable/berdefault, karyawan lokal lama otomatis NULL/0
          // (belum termigrasi - lihat PenggunaRepository.
          // migrasikanKaryawanLokalKeServer) + tabel role_izin_sync baru.
          if (from < 7) {
            await m.addColumn(pengguna, pengguna.serverPenggunaId);
            await m.addColumn(pengguna, pengguna.percobaanGagal);
            await m.addColumn(pengguna, pengguna.terkunciSampai);
            await m.createTable(roleIzinSync);
            await m.addColumn(pesananBatal, pesananBatal.penggunaId);
          }
          // v7 -> v8 (modul 10, tukar poin checkout) - kolom baru
          // berdefault 0, transaksi lama otomatis dianggap "tidak menukar
          // poin" (benar, krn fitur ini belum ada saat itu dibuat).
          if (from < 8) {
            await m.addColumn(transaksi, transaksi.poinDitukar);
            await m.addColumn(transaksi, transaksi.diskonPoin);
          }
          // v8 -> v9 (alur status pesanan IMOGI) - pelacak sinkron status; kolom
          // nullable, transaksi lama otomatis dianggap tidak ada perubahan status.
          if (from < 9) {
            await m.addColumn(transaksi, transaksi.statusPesananDiubahPada);
            await m.addColumn(transaksi, transaksi.statusPesananDisinkronPada);
          }
          // v9 -> v10 - pengaturan nomor antrian (awalan dan angka awal).
          if (from < 10) {
            await m.addColumn(pengaturanOutlet, pengaturanOutlet.antreanAwalan);
            await m.addColumn(pengaturanOutlet, pengaturanOutlet.antreanMulai);
          }
          // v10 -> v11 - kategori masuk tiket dapur (bawaan ikut tercetak).
          if (from < 11) {
            await m.addColumn(kategori, kategori.masukTiketDapur);
          }
          // v11 -> v12 - estimasi selesai pesanan (menit, per outlet).
          if (from < 12) {
            await m.addColumn(pengaturanOutlet, pengaturanOutlet.estimasiMenit);
          }
          // v12 -> v13 - batas margin produk (persen, per outlet).
          if (from < 13) {
            await m.addColumn(pengaturanOutlet, pengaturanOutlet.batasMargin);
          }
        },
      );

  // sqlcipher_flutter_libs sudah dinyatakan EOL oleh maintainer-nya (lihat
  // pub.dev); penggantinya memakai package:sqlite3 v3.x + native assets
  // hooks (source: sqlite3mc) yang masih memerlukan setup toolchain
  // terpisah. Enkripsi database lokal belum aktif di sini - susulkan
  // sebelum rilis produksi, lihat catatan risiko di ringkasan tugas ini.
  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'apps_pos.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
