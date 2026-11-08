import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/harga/kalkulator.dart' as k;
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../promo/domain/pajak.dart' as domain_pajak;
import '../../promo/domain/promo.dart' as domain_promo;
import '../../promo/domain/rincian_pajak.dart';
import '../../produk/data/local/produk_dao.dart';
import '../../stok/data/local/stok_dao.dart';
import '../../stok/data/local/tables/mutasi_stok_table.dart' show MutasiJenis;
import 'dart:convert';

import '../domain/detail_transaksi.dart';
import '../domain/hasil_transaksi.dart';
import '../domain/item_keranjang.dart';
import '../domain/pesanan_status.dart';
import '../domain/ringkasan_transaksi.dart';
import '../domain/split_pembayaran.dart';
import 'local/tables/pembayaran_table.dart' show PembayaranJenis, PembayaranStatus;
import 'local/tables/transaksi_table.dart' show StatusBayarTransaksi, StatusPesanan, TransaksiStatus;
import 'local/transaksi_dao.dart';

/// Temuan#1 (rapikan F3) - cocokkan satu baris rincian pajak/service hasil
/// hitung (nama+persen, TANPA id - lihat RincianPajakOutput di
/// kalkulator.dart) ke daftar Pajak AKTIF toko (yang PUNYA id). Match
/// pertama menang kalau >1 pajak kebetulan nama+persen-nya identik (edge
/// case jarang) - null kalau tidak ketemu sama sekali, server tetap
/// terima (dicatat "tidak dikenal" di audit_log, bukan ditolak).
String? _cariPajakId(List<domain_pajak.Pajak> daftar, {required String nama, required num persen}) {
  for (final p in daftar) {
    if (p.nama == nama && p.persen == persen) return p.id;
  }
  return null;
}

/// Dilempar saat void dicoba pada transaksi yang sudah di-void.
class TransaksiSudahDivoidException implements Exception {
  const TransaksiSudahDivoidException();

  @override
  String toString() => 'Transaksi ini sudah di-void sebelumnya';
}

class TransaksiRepository {
  TransaksiRepository(this._transaksiDao, this._stokDao, this._produkDao);

  /// Baris tambahan (varian/topping) yang dipilih pada tiap item, untuk disimpan
  /// bersama item-nya. [idItem] sejajar dengan [items].
  List<ItemTransaksiModifierCompanion> _modifierCompanions(List<ItemKeranjang> items, List<String> idItem, int now) => [
        for (var i = 0; i < items.length; i++)
          for (final m in items[i].modifiers)
            ItemTransaksiModifierCompanion.insert(
              id: generateId(),
              itemTransaksiId: idItem[i],
              modifierId: Value(m.modifierId),
              nama: m.nama,
              harga: Value(m.harga),
              createdAt: now,
              updatedAt: now,
            ),
      ];

  static List<ModifierPilihan> _modifierItem(String itemId, List<ItemTransaksiModifierRow> semua) => [
        for (final r in semua)
          if (r.itemTransaksiId == itemId) ModifierPilihan(modifierId: r.modifierId, nama: r.nama, harga: r.harga),
      ];

  final TransaksiDao _transaksiDao;
  final StokDao _stokDao;
  final ProdukDao _produkDao;

  /// Menyimpan transaksi + item + pembayaran + rincian pajak, lalu ikut
  /// mendebet stok lewat StokDao.catatMutasi (jenis penjualan) untuk item
  /// yang lacakStok - semua dalam satu transaction() yang sama (drift
  /// menyatukan transaction() bersarang jadi satu unit atomik), supaya
  /// penjualan tidak pernah tercatat tanpa stok ikut berkurang.
  ///
  /// [hasil] WAJIB berasal dari pemanggilan k.hitung() yang SAMA dengan
  /// yang dipakai utk menampilkan rincian di layar Keranjang/Bayar
  /// (lib/core/harga/kalkulator.dart) - repository ini TIDAK menghitung
  /// apa pun sendiri, cuma menyalin hasilnya ke drift (satu mesin hitung
  /// tunggal, tahap 3a bagian A). [hasil.items] harus SAMA URUTAN dan
  /// JUMLAH dengan [items] (dipasangkan per index).
  Future<HasilTransaksi> checkout({
    required String tokoId,
    required String outletId,
    required String shiftId,
    required String penggunaId,
    required String metodeBayarId,
    required List<ItemKeranjang> items,
    required k.HasilKalkulasi hasil,
    required int totalBayar,
    String? pelangganId,
    String? tipeOrderId,
    String? catatan,
    domain_promo.Promo? promo,
    // Kasbon (tahap 3b-1) - cuma relevan kalau totalBayar < hasil.total.
    // Default 7 hari (aturan #4), kasir boleh ubah lewat BayarKasbonPage.
    // Validasi "wajib pelanggan"/gating fitur 'kasbon'/'dp_kasbon' adalah
    // tanggung jawab UI (FiturTerkunci + picker wajib) - repository ini
    // SELALU mempercayai parameter yang dioper, sama prinsip dgn harga
    // (satu mesin hitung, bukan validasi ulang di tiap layer).
    int? jatuhTempoHari,
    // Penanda manual utk QRIS statis (tahap 4 bagian A.1) - diisi UI
    // SETELAH kasir menekan konfirmasi "Saya sudah cek dana masuk", belum
    // ada gateway sungguhan yang mengisi ini otomatis lewat webhook.
    String? payloadGateway,
    // Split payment (F3.A) - OPSIONAL. Kosong/null = perilaku lama (satu
    // baris Pembayaran pakai metodeBayarId+totalBayar di atas). Diisi =
    // beberapa metode sekaligus, jumlah SEMUA baris WAJIB persis ==
    // totalBayar (dicek pemanggil/UI - repository ini percaya apa adanya,
    // sama prinsip dgn harga/field lain di checkout()).
    List<SplitPembayaran>? splitPembayaran,
    // F3.E - diisi kalau checkout ini adalah PEMBAYARAN dari pesanan
    // tersimpan (open bill): draft lama (id BEDA dari transaksiId baru di
    // sini) dihapus dlm transaction() yang SAMA, atomik dgn insert
    // transaksi final - supaya tidak pernah ada jendela waktu draft masih
    // kelihatan "tersimpan" PADAHAL sudah lunas jadi transaksi baru.
    String? gantikanPesananTersimpanId,
    // Temuan#1 (rapikan F3) - daftar Pajak/Service AKTIF toko ini saat
    // checkout (dari pajakAktifProvider di pemanggil) - dipakai HANYA utk
    // mencocokkan pajakId per baris rincian (match by nama+persen, lihat
    // _cariPajakId) supaya SyncRepository bisa kirim pajak_id yang BENAR
    // ke server saat push offline, bukan selalu null. Kosong/default =
    // semua baris pajakId null (server tetap terima, cuma tercatat
    // "pajak_id tidak dikenal" di audit_log - lihat checkout_service.py).
    List<domain_pajak.Pajak> daftarPajakAktif = const [],
    // Modul 10 (tukar poin) - diskonPoin DIPOTONG DARI `hasil.total`
    // SETELAH pajak/service (bukan ikut basis hitung pajak lewat
    // kalkulator.dart - pola sama persis dgn backend checkout_service.py,
    // lihat docstring CheckoutIn.poin_ditukar di sana). Repository ini
    // TIDAK mengurangi pelanggan.poin sendiri (TransaksiRepository tidak
    // kenal PelangganDao) - pemanggil WAJIB panggil
    // PelangganRepository.catatPoin(...) sendiri setelah checkout() ini
    // sukses, pakai poinDitukar yang sama.
    int poinDitukar = 0,
    int diskonPoin = 0,
    // Pembuat nomor antrian (null = antrian mati). Dipanggil DI DALAM
    // transaction checkout supaya nomor tidak terlewat kalau checkout gagal.
    Future<String?> Function()? buatNomorAntrean,
    // Status awal pesanan (alur IMOGI). null = fitur status pesanan mati.
    StatusPesanan? statusAwal,
  }) async {
    final now = nowEpochMs();
    final transaksiId = generateId();
    String? nomorAntrean;
    final totalDiskonFinal = hasil.totalDiskon + diskonPoin;
    final totalFinal = hasil.total - diskonPoin;
    final kembalian = totalBayar >= totalFinal ? totalBayar - totalFinal : 0;
    final nomorStruk = 'STR$now';
    final rincianGabungan = [...hasil.rincianService, ...hasil.rincianPajak];
    final produkStokMenipis = <String>[];

    final lunas = totalBayar >= totalFinal;
    final statusBayar = lunas
        ? StatusBayarTransaksi.lunas
        : (totalBayar == 0 ? StatusBayarTransaksi.belumBayar : StatusBayarTransaksi.sebagian);
    final sisaTagihan = lunas ? 0 : totalFinal - totalBayar;
    final jatuhTempo =
        lunas ? null : now + (jatuhTempoHari ?? 7) * Duration.millisecondsPerDay;

    await _transaksiDao.transaction(() async {
      if (gantikanPesananTersimpanId != null) {
        await _transaksiDao.hapusPesananTersimpan(gantikanPesananTersimpanId);
      }
      nomorAntrean = await buatNomorAntrean?.call();
      final idItem = [for (final _ in items) generateId()];
      await _transaksiDao.simpanTransaksiLengkap(
        transaksi_: TransaksiCompanion.insert(
          id: transaksiId,
          tokoId: tokoId,
          outletId: outletId,
          shiftId: Value(shiftId),
          penggunaId: penggunaId,
          pelangganId: Value(pelangganId),
          tipeOrderId: Value(tipeOrderId),
          catatan: Value(catatan),
          nomorStruk: nomorStruk,
          nomorAntrean: Value(nomorAntrean),
          statusPesanan: Value(statusAwal),
          tanggal: now,
          status: TransaksiStatus.selesai,
          // totalDiskon/totalPajak GABUNGAN (member+promo, service+pajak) -
          // sama persis konvensi kolom backend (lihat checkout_service.py).
          // totalDiskon/total DI SINI sudah termasuk diskonPoin (tukar
          // poin) - lihat totalDiskonFinal/totalFinal di atas.
          subtotal: Value(hasil.subtotal),
          totalDiskon: Value(totalDiskonFinal),
          totalPajak: Value(hasil.service + hasil.pajak),
          pembulatan: Value(hasil.pembulatan),
          total: Value(totalFinal),
          totalBayar: Value(totalBayar),
          kembalian: Value(kembalian),
          statusBayar: Value(statusBayar),
          sisaTagihan: Value(sisaTagihan),
          jatuhTempo: Value(jatuhTempo),
          poinDitukar: Value(poinDitukar),
          diskonPoin: Value(diskonPoin),
          createdAt: now,
          updatedAt: now,
        ),
        items: [
          for (var i = 0; i < items.length; i++)
            ItemTransaksiCompanion.insert(
              id: idItem[i],
              transaksiId: transaksiId,
              produkId: items[i].produkId,
              namaProduk: items[i].namaProduk,
              qty: items[i].qty,
              hargaSatuan: hasil.items[i].hargaSatuan,
              subtotal: hasil.items[i].subtotal,
              createdAt: now,
              updatedAt: now,
            ),
        ],
        modifierList: _modifierCompanions(items, idItem, now),
        // Kasbon murni (totalBayar == 0, belum bayar sama sekali di awal) -
        // TIDAK ada baris Pembayaran sama sekali, sama konvensi dgn backend
        // checkout_service.py (baris pembayaran baru ada begitu ada uang
        // yang benar2 diterima - cicilan/pelunasan belakangan lewat
        // PelunasanPage/catatPembayaranKasbon).
        pembayaranList: [
          if (splitPembayaran != null && splitPembayaran.isNotEmpty)
            for (final baris in splitPembayaran)
              PembayaranCompanion.insert(
                id: generateId(),
                transaksiId: transaksiId,
                metodeBayarId: baris.metodeBayarId,
                shiftId: Value(shiftId),
                jumlah: baris.jumlah,
                jenis: Value(lunas ? PembayaranJenis.penuh : PembayaranJenis.dp),
                status: PembayaranStatus.berhasil,
                refGateway: Value(baris.nomorReferensi),
                payloadGateway: Value(
                  baris.empatDigitAkhirKartu == null
                      ? null
                      : jsonEncode({'empat_digit_akhir_kartu': baris.empatDigitAkhirKartu}),
                ),
                dibayarPada: Value(now),
                disinkronPada: Value(now),
                createdAt: now,
                updatedAt: now,
              )
          else if (totalBayar > 0)
            PembayaranCompanion.insert(
              id: generateId(),
              transaksiId: transaksiId,
              metodeBayarId: metodeBayarId,
              shiftId: Value(shiftId),
              jumlah: totalBayar,
              jenis: Value(lunas ? PembayaranJenis.penuh : PembayaranJenis.dp),
              status: PembayaranStatus.berhasil,
              payloadGateway: Value(payloadGateway),
              dibayarPada: Value(now),
              // "Lahir tersync" - baris ini ikut terkirim lewat payload
              // checkout transaksinya sendiri (backend membuat baris
              // pembayarannya SENDIRI dari total_bayar, bukan dari sini),
              // jadi TIDAK PERNAH perlu dipush lewat jalur pembayaran
              // standalone (lihat SyncRepository._pushPembayaranStandalone)
              // - beda dari cicilan/pelunasan belakangan lewat
              // catatPembayaranKasbon yang memang lahir belum-sync.
              disinkronPada: Value(now),
              createdAt: now,
              updatedAt: now,
            ),
        ],
        pajakList: [
          for (final rincian in rincianGabungan)
            TransaksiPajakCompanion.insert(
              id: generateId(),
              transaksiId: transaksiId,
              pajakId: Value(_cariPajakId(daftarPajakAktif, nama: rincian.nama, persen: rincian.persen)),
              nama: rincian.nama,
              persen: rincian.persen.toDouble(),
              jumlah: rincian.jumlah,
              createdAt: now,
              updatedAt: now,
            ),
        ],
        promoList: [
          if (hasil.diskonMember > 0)
            TransaksiPromoCompanion.insert(
              id: generateId(),
              transaksiId: transaksiId,
              nama: 'Diskon member',
              jumlahDiskon: hasil.diskonMember,
              createdAt: now,
              updatedAt: now,
            ),
          if (promo != null && hasil.diskonPromo > 0)
            TransaksiPromoCompanion.insert(
              id: generateId(),
              transaksiId: transaksiId,
              promoId: Value(promo.id),
              nama: promo.nama,
              jumlahDiskon: hasil.diskonPromo,
              createdAt: now,
              updatedAt: now,
            ),
          if (diskonPoin > 0)
            TransaksiPromoCompanion.insert(
              id: generateId(),
              transaksiId: transaksiId,
              nama: 'Tukar poin',
              jumlahDiskon: diskonPoin,
              createdAt: now,
              updatedAt: now,
            ),
        ],
      );

      for (final item in items) {
        if (!item.lacakStok) continue;
        final hasilMutasi = await _stokDao.catatMutasi(
          tokoId: tokoId,
          outletId: outletId,
          produkId: item.produkId,
          jenis: MutasiJenis.penjualan,
          qty: -item.qty,
          refTipe: 'transaksi',
          refId: transaksiId,
          dibuatOleh: penggunaId,
        );
        // batasMinimum 0 = belum diatur sama sekali - jangan dianggap
        // "menipis" (sama aturan dgn StokItem.stokMenipis & job backend
        // cek_stok_menipis_dan_notifikasi).
        if (hasilMutasi.batasMinimum > 0 && hasilMutasi.saldoSetelah <= hasilMutasi.batasMinimum) {
          produkStokMenipis.add(item.namaProduk);
        }
      }
    });

    return HasilTransaksi(
      id: transaksiId,
      nomorStruk: nomorStruk,
      nomorAntrean: nomorAntrean,
      tanggal: now,
      items: items,
      subtotal: hasil.subtotal,
      // Label baris diskon di struk (satu baris gabungan, lihat
      // HasilTransaksi.namaPromo) - promo MENANG kalau keduanya terpakai
      // sekaligus (jarang, diskon_poin tetap ikut masuk totalDiskon di
      // bawah meski labelnya tidak kelihatan terpisah - keterbatasan yg
      // diakui, bukan ditutupi).
      namaPromo: promo != null && hasil.diskonPromo > 0
          ? promo.nama
          : (diskonPoin > 0 ? 'Tukar poin' : null),
      totalDiskon: totalDiskonFinal,
      rincianPajak: [
        for (final r in rincianGabungan)
          RincianPajak(
            nama: r.nama,
            persen: r.persen.toDouble(),
            jumlah: r.jumlah,
            termasukHarga: r.termasukHarga,
          ),
      ],
      totalPajak: hasil.service + hasil.pajak,
      total: totalFinal,
      totalBayar: totalBayar,
      kembalian: kembalian,
      statusBayar: statusBayar.name,
      sisaTagihan: sisaTagihan,
      jatuhTempo: jatuhTempo,
      produkStokMenipis: produkStokMenipis,
    );
  }

  /// Cicilan/pelunasan kasbon (tahap 3b-1) - dipakai PelunasanPage, bisa
  /// offline (murni tulis lokal, disync belakangan lewat SyncRepository
  /// baca Pembayaran.disinkronPada). [shiftId] = shift TEMPAT uang ini
  /// BENAR2 diterima (boleh beda dari shift transaksi asalnya).
  Future<void> catatPembayaranKasbon({
    required String transaksiId,
    required String metodeBayarId,
    required String shiftId,
    required int jumlah,
    // Penanda manual utk QRIS statis (tahap 4 bagian A.1) - lihat
    // dokumentasi param yang sama di checkout().
    String? payloadGateway,
  }) {
    final now = nowEpochMs();
    return _transaksiDao.catatPembayaranKasbon(
      pembayaranTanpaJenis: PembayaranCompanion.insert(
        id: generateId(),
        transaksiId: transaksiId,
        metodeBayarId: metodeBayarId,
        shiftId: Value(shiftId),
        jumlah: jumlah,
        status: PembayaranStatus.berhasil,
        payloadGateway: Value(payloadGateway),
        dibayarPada: Value(now),
        createdAt: now,
        updatedAt: now,
      ),
      now: now,
    );
  }

  /// Riwayat - semua transaksi outlet + info ringkas (jumlah item, metode
  /// bayar) untuk ditampilkan di list tanpa join berat.
  Stream<List<RingkasanTransaksi>> watchRiwayat(String outletId) {
    return _transaksiDao.watchTransaksiOutlet(outletId).asyncMap((rows) async {
      final hasil = <RingkasanTransaksi>[];
      for (final row in rows) {
        final jumlahItem = await _transaksiDao.jumlahItemTransaksi(row.id);
        final bayar = await _transaksiDao.pembayaranUtamaTransaksi(row.id);
        final jumlahPembayaran = await _transaksiDao.jumlahPembayaranTransaksi(row.id);
        hasil.add(
          RingkasanTransaksi(
            id: row.id,
            nomorStruk: row.nomorStruk,
            tanggal: row.tanggal,
            status: row.status,
            total: row.total,
            jumlahItem: jumlahItem,
            pelangganId: row.pelangganId,
            metodeBayarId: bayar?.metodeBayarId,
            jumlahPembayaran: jumlahPembayaran,
          ),
        );
      }
      return hasil;
    });
  }

  /// Detail satu transaksi lama (layar Riwayat > detail) - gabungan item,
  /// pajak, promo, pembayaran. [namaPelanggan] sengaja diambil dari
  /// pemanggil (bukan query cross-fitur ke tabel pelanggan di sini) supaya
  /// repository ini tidak perlu tahu soal modul pelanggan.
  Future<DetailTransaksi> detailTransaksi(
    String transaksiId, {
    String? namaPelanggan,
  }) async {
    final row = await _transaksiDao.transaksiById(transaksiId);
    final items = await _transaksiDao.itemUntukTransaksi(transaksiId);
    final pajak = await _transaksiDao.pajakUntukTransaksi(transaksiId);
    // namaPromo HANYA utk promo kode sungguhan (promoId != null) - baris
    // diskon member (promoId null) punya nama generik "Diskon member" yang
    // tidak informatif ditampilkan sbg "nama promo" di detail transaksi.
    final promo = (await _transaksiDao.semuaPromoUntukTransaksi(transaksiId))
        .where((p) => p.promoId != null)
        .firstOrNull;
    final bayar = await _transaksiDao.pembayaranUtamaTransaksi(transaksiId);
    final jumlahPembayaran = await _transaksiDao.jumlahPembayaranTransaksi(transaksiId);
    final modifierRows = await _transaksiDao.modifierUntukItemList([for (final i in items) i.id]);

    return DetailTransaksi(
      id: row.id,
      nomorStruk: row.nomorStruk,
      nomorAntrean: row.nomorAntrean,
      tanggal: row.tanggal,
      status: row.status,
      items: [
        for (final item in items)
          ItemKeranjang(
            produkId: item.produkId,
            namaProduk: item.namaProduk,
            // item_transaksi.harga_satuan = harga akhir per unit (sudah termasuk tambahan);
            // ItemKeranjang.hargaSatuan adalah harga dasar, jadi tambahan dikurangkan.
            hargaSatuan: item.hargaSatuan - _modifierItem(item.id, modifierRows).fold<int>(0, (a, m) => a + m.harga),
            qty: item.qty,
            lacakStok: true,
            modifiers: _modifierItem(item.id, modifierRows),
          ),
      ],
      subtotal: row.subtotal,
      namaPromo: promo?.nama,
      totalDiskon: row.totalDiskon,
      rincianPajak: [
        for (final p in pajak)
          RincianPajak(
            nama: p.nama,
            persen: p.persen,
            jumlah: p.jumlah,
            termasukHarga: false,
          ),
      ],
      totalPajak: row.totalPajak,
      total: row.total,
      totalBayar: row.totalBayar,
      kembalian: row.kembalian,
      metodeBayarId: bayar?.metodeBayarId,
      jumlahPembayaran: jumlahPembayaran,
      namaPelanggan: namaPelanggan,
      alasanVoid: row.alasanVoid,
      snapshotStruk: row.snapshotStruk,
    );
  }

  /// Void transaksi LAMA dari layar Riwayat - beda dengan [voidTransaksi] di
  /// bawah (dipakai tepat setelah checkout): di sini item & lacakStok harus
  /// direkonstruksi dari item_transaksi + master Produk saat ini (snapshot
  /// lama tidak menyimpan lacakStok), baru panggil logika void yang sama.
  Future<void> voidTransaksiLama({
    required String transaksiId,
    required String tokoId,
    required String outletId,
    required String alasan,
    required String disetujuiOleh,
  }) async {
    final rows = await _transaksiDao.itemUntukTransaksi(transaksiId);
    final items = <ItemKeranjang>[];
    for (final row in rows) {
      final produk = await _produkDao.produkById(row.produkId);
      items.add(
        ItemKeranjang(
          produkId: row.produkId,
          namaProduk: row.namaProduk,
          hargaSatuan: row.hargaSatuan,
          qty: row.qty,
          lacakStok: produk?.lacakStok ?? false,
        ),
      );
    }

    await voidTransaksi(
      transaksiId: transaksiId,
      tokoId: tokoId,
      outletId: outletId,
      alasan: alasan,
      disetujuiOleh: disetujuiOleh,
      items: items,
    );
  }

  /// Ubah status pesanan (Baru, Diproses, Siap, Selesai, ...). Dicatat waktunya
  /// supaya ikut terkirim ke server lewat sync.
  Future<void> ubahStatusPesanan(String transaksiId, StatusPesanan status) =>
      _transaksiDao.ubahStatusPesanan(transaksiId, status, nowEpochMs());

  /// Pesanan bernomor status milik [outletId] sejak awal hari [sekarang] (waktu setempat).
  Future<List<PesananStatus>> pesananHariIni(String outletId, {DateTime? sekarang}) async {
    final w = sekarang ?? DateTime.now();
    final awalHari = DateTime(w.year, w.month, w.day).millisecondsSinceEpoch;
    final rows = await _transaksiDao.pesananBerstatus(outletId: outletId, sejakMs: awalHari);
    final item = await _transaksiDao.itemUntukTransaksiList([for (final r in rows) r.id]);
    return [
      for (final r in rows)
        PesananStatus(
          id: r.id,
          nomorStruk: r.nomorStruk,
          nomorAntrean: r.nomorAntrean,
          tanggal: r.tanggal,
          status: r.statusPesanan!,
          pelangganId: r.pelangganId,
          ringkasanItem: [
            for (final i in item.where((x) => x.transaksiId == r.id))
              '${i.qty == i.qty.roundToDouble() ? i.qty.toInt() : i.qty}x ${i.namaProduk}',
          ].join(', '),
        ),
    ];
  }

  /// Void transaksi: tandai statusnya + balikkan stok yang sudah terdebet
  /// saat checkout (jenis voidTransaksi, qty positif) untuk item yang
  /// lacakStok - dalam satu transaction() yang sama seperti checkout.
  /// Pemanggil (UI) wajib pastikan PIN/izin sudah divalidasi SEBELUM
  /// memanggil ini - repository ini tidak mengecek otorisasi.
  Future<void> voidTransaksi({
    required String transaksiId,
    required String tokoId,
    required String outletId,
    required String alasan,
    required String disetujuiOleh,
    required List<ItemKeranjang> items,
  }) async {
    final now = nowEpochMs();

    await _transaksiDao.transaction(() async {
      // Void hanya sekali. Tanpa pengecekan ini, tiap void ulang mencatat
      // mutasi stok lagi dan stok bertambah terus (BUG-013).
      final saatIni = await _transaksiDao.transaksiById(transaksiId);
      if (saatIni.status == TransaksiStatus.dibatalkan) {
        throw const TransaksiSudahDivoidException();
      }

      await _transaksiDao.voidTransaksi(
        transaksiId: transaksiId,
        alasan: alasan,
        disetujuiOleh: disetujuiOleh,
        now: now,
      );

      for (final item in items) {
        if (!item.lacakStok) continue;
        await _stokDao.catatMutasi(
          tokoId: tokoId,
          outletId: outletId,
          produkId: item.produkId,
          jenis: MutasiJenis.voidTransaksi,
          qty: item.qty,
          refTipe: 'transaksi',
          refId: transaksiId,
          dibuatOleh: disetujuiOleh,
        );
      }
    });
  }

  /// F3.E - "Simpan pesanan" (open bill): TIDAK memotong stok, TIDAK
  /// membuat baris Pembayaran, nomor struk masih berupa placeholder
  /// 'DRAFT...' (bukan final - nomor struk sungguhan baru diberikan saat
  /// benar2 dibayar lewat checkout()). [draftIdSebelumnya] diisi kalau
  /// mengedit draft yang SUDAH tersimpan sebelumnya (hapus+insert ulang -
  /// "upsert" sederhana, cukup krn draft belum pernah disync sbg
  /// penjualan sungguhan). Kembalikan id transaksi draft.
  Future<String> simpanPesanan({
    required String tokoId,
    required String outletId,
    required String penggunaId,
    required List<ItemKeranjang> items,
    required k.HasilKalkulasi hasil,
    String? draftIdSebelumnya,
    String? pelangganId,
    String? tipeOrderId,
    String? catatan,
  }) async {
    final now = nowEpochMs();
    final transaksiId = draftIdSebelumnya ?? generateId();
    final nomorStruk = 'DRAFT$now';

    await _transaksiDao.transaction(() async {
      if (draftIdSebelumnya != null) {
        await _transaksiDao.hapusPesananTersimpan(draftIdSebelumnya);
      }
      final idItem = [for (final _ in items) generateId()];
      await _transaksiDao.simpanTransaksiLengkap(
        transaksi_: TransaksiCompanion.insert(
          id: transaksiId,
          tokoId: tokoId,
          outletId: outletId,
          penggunaId: penggunaId,
          pelangganId: Value(pelangganId),
          tipeOrderId: Value(tipeOrderId),
          catatan: Value(catatan),
          nomorStruk: nomorStruk,
          tanggal: now,
          status: TransaksiStatus.tersimpan,
          subtotal: Value(hasil.subtotal),
          total: Value(hasil.total),
          totalBayar: const Value(0),
          kembalian: const Value(0),
          statusBayar: const Value(StatusBayarTransaksi.belumBayar),
          createdAt: now,
          updatedAt: now,
        ),
        items: [
          for (var i = 0; i < items.length; i++)
            ItemTransaksiCompanion.insert(
              id: idItem[i],
              transaksiId: transaksiId,
              produkId: items[i].produkId,
              namaProduk: items[i].namaProduk,
              qty: items[i].qty,
              hargaSatuan: hasil.items[i].hargaSatuan,
              subtotal: hasil.items[i].subtotal,
              createdAt: now,
              updatedAt: now,
            ),
        ],
        modifierList: _modifierCompanions(items, idItem, now),
        pembayaranList: const [],
      );
    });
    return transaksiId;
  }

  /// Daftar pesanan tersimpan (open bill) di outlet ini - SELALU di
  /// device ini saja (F3.E.4, versi pertama per-HP).
  Stream<List<TransaksiRow>> watchPesananTersimpan(String outletId) =>
      _transaksiDao.watchPesananTersimpan(outletId);

  /// Rekonstruksi item draft jadi ItemKeranjang siap dimuat ke keranjang
  /// (F3.E.3) - lacakStok diambil ULANG dari master Produk SAAT INI (sama
  /// pola dgn voidTransaksiLama di atas), bukan disimpan di item_transaksi.
  Future<List<ItemKeranjang>> itemUntukResumePesanan(String transaksiId) async {
    final rows = await _transaksiDao.itemUntukTransaksi(transaksiId);
    final modifierRows = await _transaksiDao.modifierUntukItemList([for (final r in rows) r.id]);
    final items = <ItemKeranjang>[];
    for (final row in rows) {
      final produk = await _produkDao.produkById(row.produkId);
      final modifiers = _modifierItem(row.id, modifierRows);
      items.add(ItemKeranjang(
        produkId: row.produkId,
        namaProduk: row.namaProduk,
        // harga tersimpan = harga akhir per unit; dasar = akhir dikurangi tambahan
        hargaSatuan: row.hargaSatuan - modifiers.fold<int>(0, (a, m) => a + m.harga),
        qty: row.qty,
        lacakStok: produk?.lacakStok ?? false,
        modifiers: modifiers,
      ));
    }
    return items;
  }

  /// Temuan#2 (rapikan F3.E) - batalkan pesanan tersimpan: draft LOKAL
  /// (hard delete, sama alasan dgn sebelumnya - draft belum pernah jadi
  /// penjualan sungguhan, tidak perlu jejak permanen DI HP) TAPI alasan +
  /// snapshot isi/total SEKARANG dicatat ke antrean `pesanan_batal` lokal
  /// (disinkronPada null) SEBELUM draft dihapus, supaya tetap bisa dikirim
  /// ke server (audit_log siapa/kapan/isi/total/alasan) kapan pun
  /// koneksi tersedia - "online langsung" dicoba oleh PEMANGGIL (UI) SEGERA
  /// setelah method ini return (lihat pesanan_tersimpan_list_page.dart),
  /// "offline lewat push" otomatis lewat SyncRepository kalau percobaan
  /// langsung itu gagal/tidak dicoba. [disetujuiOleh] diisi UI kalau kasir
  /// sudah diminta approval PIN owner/manajer (lihat core/auth/pin_approval.dart).
  ///
  /// Return id baris antrean (= [transaksiId]) supaya pemanggil bisa
  /// menandainya sudah sync kalau push online langsung berhasil.
  Future<String> batalkanPesanan(
    String transaksiId,
    String alasan, {
    String? disetujuiOleh,
    String? penggunaId,
  }) async {
    final now = nowEpochMs();
    final items = await _transaksiDao.itemUntukTransaksi(transaksiId);
    final transaksi = await _transaksiDao.transaksiById(transaksiId);
    final isiPesanan = jsonEncode([
      for (final item in items)
        {'produk_id': item.produkId, 'nama_produk': item.namaProduk, 'qty': item.qty},
    ]);

    await _transaksiDao.transaction(() async {
      await _transaksiDao.catatPembatalanPesanan(
        PesananBatalCompanion.insert(
          id: transaksiId,
          alasan: alasan,
          disetujuiOleh: Value(disetujuiOleh),
          penggunaId: Value(penggunaId),
          isiPesanan: isiPesanan,
          total: transaksi.total,
          nomorStruk: transaksi.nomorStruk,
          dibatalkanPada: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _transaksiDao.hapusPesananTersimpan(transaksiId);
    });
    return transaksiId;
  }

  /// Dipanggil pemanggil (UI) SETELAH berhasil push [batalkanPesanan]
  /// langsung ke server (jalur online) - supaya baris antrean yang sama
  /// tidak dipush ULANG lewat SyncRepository nanti.
  Future<void> tandaiPembatalanPesananSudahSync(String id) =>
      _transaksiDao.tandaiPembatalanPesananSudahSync([id], nowEpochMs());

  /// Temuan A.2 (tahap 5) - lihat TransaksiDao.simpanSnapshotStruk.
  Future<void> simpanSnapshotStruk(String transaksiId, String snapshotJson) =>
      _transaksiDao.simpanSnapshotStruk(transaksiId, snapshotJson);
}
