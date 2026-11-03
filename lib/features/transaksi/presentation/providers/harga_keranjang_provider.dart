import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/harga/kalkulator.dart' as k;
import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../fitur/presentation/providers/feature_gate_provider.dart';
import '../../../order/presentation/providers/tipe_order_providers.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';
import '../../../produk/data/local/harga_dao.dart';
import '../../../promo/data/local/tables/pajak_table.dart' show PajakTipe;
import '../../../promo/presentation/providers/pajak_providers.dart';
import 'keranjang_provider.dart';

final hargaDaoProvider = Provider<HargaDao>((ref) {
  return ref.watch(appDatabaseProvider).hargaDao;
});

/// Satu-shot (FutureProvider, bukan `.watch()`) - lihat catatan deadlock
/// nested-watch di feature_gate_provider.dart, pola yang sama dihindari
/// di sini juga. Diinvalidate manual setelah sync (lihat sync_repository
/// pemanggil) tidak diperlukan krn provider ini otomatis rebuild tiap
/// kali salah satu `ref.watch` di dalamnya berubah (keranjang/outletId),
/// cukup utk kebutuhan tampilan harga real-time di keranjang.
final hargaOutletUntukOutletProvider =
    FutureProvider.family<List<HargaOutletRow>, String>((ref, outletId) {
      return ref.watch(hargaDaoProvider).hargaOutletUntukOutlet(outletId);
    });

final hargaGrosirUntukKeranjangProvider = FutureProvider<List<HargaGrosirRow>>((
  ref,
) {
  final produkIds = ref
      .watch(keranjangProvider)
      .map((i) => i.produkId)
      .toList();
  return ref.watch(hargaDaoProvider).hargaGrosirUntukProduk(produkIds);
});

final pengaturanOutletProvider =
    FutureProvider.family<PengaturanOutletRow?, String>((ref, outletId) {
      return ref.watch(hargaDaoProvider).ambilPengaturanOutlet(outletId);
    });

final pajakPerProdukUntukKeranjangProvider =
    FutureProvider<Map<String, List<PajakRow>>>((ref) {
      final produkIds = ref
          .watch(keranjangProvider)
          .map((i) => i.produkId)
          .toList();
      return ref.watch(pajakDaoProvider).pajakUntukProduk(produkIds);
    });

final tipeOrderPajakSemuaProvider = FutureProvider<List<TipeOrderPajakRow>>((
  ref,
) {
  return ref.watch(tipeOrderDaoProvider).semuaTipeOrderPajak();
});

/// Hasil hitung keranjang LENGKAP (subtotal, diskon member, diskon promo,
/// service, tiap pajak, pembulatan, total) lewat mesin yang SAMA dgn
/// server (lib/core/harga/kalkulator.dart <-> backend/app/services/harga/
/// kalkulator.py - lihat docs/aturan_harga.md). Angka ini JUGA yang
/// dipakai TransaksiRepository.checkout() utk menyimpan ke drift dan
/// struk (tahap 3a bagian A - satu mesin hitung tunggal).
///
/// Simplifikasi yang disengaja utk sesi ini (lihat laporan tahap 3a):
/// - promo cakupan='produk' belum didukung di keranjang (promo_produk
///   lokal belum ada link-nya) - cuma cakupan='transaksi' yang dikirim
///   ke mesin, sama dgn simplifikasi di checkout_service.py server.
/// - `ItemKeranjang` tidak melacak varianId - harga_outlet/harga_grosir
///   per-varian tidak berlaku di keranjang (selalu dicocokkan sbg
///   varianId null).
final hasilHargaKeranjangProvider = Provider<k.HasilKalkulasi>((ref) {
  final items = ref.watch(keranjangProvider);
  final tokoId = ref.watch(currentTokoIdProvider);
  final outletId = ref.watch(currentOutletIdProvider);

  final fiturAktif = ref
      .watch(featureGateProvider)
      .maybeWhen(
        data: (gate) => gate.kodeAktif,
        orElse: () => const <String>{},
      );

  final promo = ref.watch(keranjangPromoProvider);
  final promoUntukMesin = (promo == null || promo.cakupan.name != 'transaksi')
      ? null
      : k.PromoInput(
          id: promo.id,
          nama: promo.nama,
          tipe: promo.tipe.name,
          cakupan: promo.cakupan.name,
          nilai: promo.nilai,
          minBelanja: promo.minBelanja,
          maksDiskon: promo.maksDiskon,
        );

  final pelangganId = ref.watch(keranjangPelangganIdProvider);
  double? diskonMemberPersen;
  if (pelangganId != null) {
    final semuaPelanggan = ref
        .watch(pelangganAktifProvider)
        .maybeWhen(data: (v) => v, orElse: () => const []);
    final pelanggan = semuaPelanggan.firstWhereOrNull(
      (p) => p.id == pelangganId,
    );
    if (pelanggan?.levelMemberId != null) {
      final semuaLevel = ref
          .watch(levelMemberProvider)
          .maybeWhen(data: (v) => v, orElse: () => const []);
      final level = semuaLevel.firstWhereOrNull(
        (l) => l.id == pelanggan!.levelMemberId,
      );
      diskonMemberPersen = level?.diskonPersen;
    }
  }

  final tipeOrderId = ref.watch(keranjangTipeOrderIdProvider);
  final tipeOrderPajakRows = ref
      .watch(tipeOrderPajakSemuaProvider)
      .maybeWhen(data: (v) => v, orElse: () => const <TipeOrderPajakRow>[]);
  k.TipeOrderInput? tipeOrderInput;
  if (tipeOrderId != null) {
    final semuaTipeOrder = ref
        .watch(tipeOrderAktifProvider)
        .maybeWhen(data: (v) => v, orElse: () => const []);
    final tipeOrder = semuaTipeOrder.firstWhereOrNull(
      (t) => t.id == tipeOrderId,
    );
    if (tipeOrder != null) {
      final pajakIds = tipeOrderPajakRows
          .where((r) => r.tipeOrderId == tipeOrderId)
          .map((r) => r.pajakId)
          .toSet();
      tipeOrderInput = k.TipeOrderInput(
        id: tipeOrder.id,
        markupPersen: tipeOrder.markupPersen,
        pajakIds: pajakIds,
      );
    }
  }

  final semuaPajak = ref
      .watch(pajakAktifProvider(tokoId))
      .maybeWhen(data: (v) => v, orElse: () => const []);
  final pajakDefault = semuaPajak
      .where((p) => p.tipe == PajakTipe.pajak)
      .map(
        (p) => k.PajakInput(
          id: p.id,
          nama: p.nama,
          persen: p.persen,
          termasukHarga: p.termasukHarga,
          urutan: p.urutan,
        ),
      )
      .toList();
  final serviceDefault = semuaPajak
      .where((p) => p.tipe == PajakTipe.service)
      .map(
        (p) => k.PajakInput(
          id: p.id,
          nama: p.nama,
          persen: p.persen,
          termasukHarga: p.termasukHarga,
          urutan: p.urutan,
        ),
      )
      .toList();

  final hargaOutletRows = ref
      .watch(hargaOutletUntukOutletProvider(outletId))
      .maybeWhen(data: (v) => v, orElse: () => const []);
  final hargaOutletMap = <(String, String?), int>{
    for (final r in hargaOutletRows) (r.produkId, r.varianId): r.hargaJual,
  };

  final hargaGrosirRows = ref
      .watch(hargaGrosirUntukKeranjangProvider)
      .maybeWhen(data: (v) => v, orElse: () => const []);

  final produkPajakMap = ref
      .watch(pajakPerProdukUntukKeranjangProvider)
      .maybeWhen(data: (v) => v, orElse: () => const {});

  final itemInputs = items.map((item) {
    final tiers = hargaGrosirRows
        .where((r) => r.produkId == item.produkId && r.varianId == null)
        .map(
          (r) => k.HargaGrosirTier(
            minQty: r.minQty,
            harga: r.harga,
            outletId: r.outletId,
          ),
        )
        .toList();
    final pajakProdukRows = produkPajakMap[item.produkId];
    return k.ItemInput(
      produkId: item.produkId,
      varianId: null,
      namaProduk: item.namaProduk,
      qty: item.qty,
      hargaJual: item.hargaSatuan,
      hargaOutlet: hargaOutletMap[(item.produkId, null)],
      hargaGrosirTiers: tiers,
      pajakProduk: pajakProdukRows
          ?.map(
            (p) => k.PajakInput(
              id: p.id,
              nama: p.nama,
              persen: p.persen,
              termasukHarga: p.termasukHarga,
              urutan: p.urutan,
            ),
          )
          .toList(),
    );
  }).toList();

  final pengaturan = ref
      .watch(pengaturanOutletProvider(outletId))
      .maybeWhen(data: (v) => v, orElse: () => null);
  final pembulatan = pengaturan?.pembulatan ?? 0;

  return k.hitung(
    k.TransaksiInput(
      items: itemInputs,
      fiturAktif: fiturAktif,
      promo: promoUntukMesin,
      diskonMemberPersen: diskonMemberPersen,
      tipeOrder: tipeOrderInput,
      pajakDefault: pajakDefault,
      serviceDefault: serviceDefault,
      pembulatan: pembulatan,
    ),
  );
});

/// Diskon (Rupiah) dari poin yang dipilih kasir utk ditukar
/// (keranjangPoinDitukarProvider) - DIPOTONG DARI TOTAL SETELAH pajak,
/// BUKAN ikut basis hitung pajak lewat k.hitung() di atas (pola sama
/// persis dgn backend, lihat docstring CheckoutIn.poin_ditukar di
/// backend/app/schemas/transaksi.py). 0 kalau tidak ada pelanggan
/// terpilih, aturan poin tidak aktif, atau poinDitukar<=0.
final diskonPoinKeranjangProvider = Provider<int>((ref) {
  final poinDitukar = ref.watch(keranjangPoinDitukarProvider);
  if (poinDitukar <= 0) return 0;
  final pelangganId = ref.watch(keranjangPelangganIdProvider);
  if (pelangganId == null) return 0;

  final aturan = ref.watch(aturanPoinProvider).maybeWhen(data: (v) => v, orElse: () => null);
  if (aturan == null || !aturan.aktif || aturan.nilaiTukarPoin <= 0) return 0;

  final total = ref.watch(hasilHargaKeranjangProvider).total;
  final nilai = poinDitukar * aturan.nilaiTukarPoin;
  return nilai > total ? total : nilai;
});

/// Total AKHIR yang harus dibayar kasir - `hasilHargaKeranjangProvider.
/// total` dikurangi `diskonPoinKeranjangProvider`. Dipakai layar
/// Bayar/Struk sbg pengganti `hasil.total` langsung begitu ada poin yg
/// ditukar.
final totalSetelahPoinProvider = Provider<int>((ref) {
  final total = ref.watch(hasilHargaKeranjangProvider).total;
  final diskonPoin = ref.watch(diskonPoinKeranjangProvider);
  return total - diskonPoin;
});
