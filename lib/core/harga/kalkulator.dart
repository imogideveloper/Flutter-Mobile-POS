/// Mesin hitung harga - cermin 1:1 dari
/// `backend/app/services/harga/kalkulator.py`. Urutan hitung & aturan
/// pembulatan didokumentasikan di `docs/aturan_harga.md` - UBAH DOKUMEN
/// ITU DULU kalau mau ubah urutan, lalu samakan kedua modul ini.
///
/// Murni (tidak sentuh DB/network) - dites lewat fixture JSON bersama di
/// `shared/fixtures/harga/` (dibaca juga oleh pytest), supaya keranjang
/// Flutter & checkout server tidak bisa diam-diam melenceng.
///
/// Uang selalu `int` rupiah, pembulatan HALF_UP ke rupiah di SETIAP
/// komponen (tiap baris, diskon, service, tiap pajak) - tidak pernah
/// `double` untuk nilai uang (persen tetap `num`).
library;

int bulatkan(num nilai) => nilai.round();

class HargaGrosirTier {
  const HargaGrosirTier({required this.minQty, required this.harga, this.outletId});

  final num minQty;
  final int harga;
  final String? outletId; // null = tier umum (berlaku semua outlet)
}

class ModifierInput {
  const ModifierInput({required this.nama, required this.harga});

  final String nama;
  final int harga;
}

class PajakInput {
  const PajakInput({
    required this.id,
    required this.nama,
    required this.persen,
    required this.termasukHarga,
    this.urutan = 0,
  });

  final String id;
  final String nama;
  final num persen;
  final bool termasukHarga;
  final int urutan;
}

class PromoInput {
  const PromoInput({
    required this.id,
    required this.nama,
    required this.tipe, // persen|nominal
    required this.cakupan, // produk|transaksi
    required this.nilai,
    this.minBelanja = 0,
    this.maksDiskon,
    this.produkIds = const <String>{},
  });

  final String id;
  final String nama;
  final String tipe;
  final String cakupan;
  final num nilai;
  final int minBelanja;
  final int? maksDiskon;
  final Set<String> produkIds; // relevan kalau cakupan='produk'
}

class TipeOrderInput {
  const TipeOrderInput({required this.id, this.markupPersen = 0, this.pajakIds = const <String>{}});

  final String id;
  final num markupPersen;
  final Set<String> pajakIds; // id pajak tipe 'service' lewat tipe_order_pajak
}

class ItemInput {
  const ItemInput({
    required this.produkId,
    required this.varianId,
    required this.namaProduk,
    required this.qty,
    required this.hargaJual,
    this.hargaOutlet,
    this.hargaGrosirTiers = const <HargaGrosirTier>[],
    this.modifiers = const <ModifierInput>[],
    this.pajakProduk,
    this.diskonOverride,
  });

  final String produkId;
  final String? varianId;
  final String namaProduk;
  final num qty;
  final int hargaJual;
  final int? hargaOutlet;
  final List<HargaGrosirTier> hargaGrosirTiers;
  final List<ModifierInput> modifiers;
  // null = pakai pajakDefault toko; list (termasuk kosong) = override
  // produk_pajak produk ini (dipakai HANYA kalau fitur pajak_per_produk aktif).
  final List<PajakInput>? pajakProduk;
  // Dipakai HANYA oleh checkout server (lihat kalkulator.py) - keranjang
  // Flutter TIDAK PERNAH mengisi ini, selalu null (hitung dari `promo`).
  final int? diskonOverride;
}

class TransaksiInput {
  const TransaksiInput({
    required this.items,
    this.fiturAktif = const <String>{},
    this.promo,
    this.diskonMemberPersen,
    this.tipeOrder,
    this.pajakDefault = const <PajakInput>[],
    this.serviceDefault = const <PajakInput>[],
    this.pembulatan = 0,
  });

  final List<ItemInput> items;
  final Set<String> fiturAktif;
  final PromoInput? promo;
  final num? diskonMemberPersen;
  final TipeOrderInput? tipeOrder;
  final List<PajakInput> pajakDefault; // tipe 'pajak', aktif, milik toko
  final List<PajakInput> serviceDefault; // tipe 'service', aktif, milik toko
  final int pembulatan; // 0|100|500|1000, dari pengaturan_outlet
}

class RincianItemOutput {
  const RincianItemOutput({
    required this.produkId,
    required this.varianId,
    required this.qty,
    required this.hargaSatuan,
    required this.diskon,
    required this.subtotal,
  });

  final String produkId;
  final String? varianId;
  final num qty;
  final int hargaSatuan; // snapshot per-unit final - SEBELUM promo-produk
  final int diskon; // hasil promo cakupan 'produk' utk baris ini
  final int subtotal; // bulatkan(qty*hargaSatuan) - diskon
}

class RincianPajakOutput {
  const RincianPajakOutput({
    required this.nama,
    required this.persen,
    required this.jumlah,
    required this.termasukHarga,
  });

  final String nama;
  final num persen;
  final int jumlah;
  final bool termasukHarga;
}

class HasilKalkulasi {
  const HasilKalkulasi({
    required this.items,
    required this.subtotal,
    required this.diskonMember,
    required this.diskonPromo,
    required this.totalDiskon,
    required this.service,
    required this.rincianService,
    required this.pajak,
    required this.rincianPajak,
    required this.totalSebelumPembulatan,
    required this.pembulatan,
    required this.total,
  });

  final List<RincianItemOutput> items;
  final int subtotal;
  final int diskonMember;
  final int diskonPromo;
  final int totalDiskon;
  final int service;
  final List<RincianPajakOutput> rincianService;
  final int pajak;
  final List<RincianPajakOutput> rincianPajak;
  final int totalSebelumPembulatan;
  final int pembulatan; // selisih akibat pembulatan akhir (bisa negatif)
  final int total; // SUDAH dibulatkan - ini yang ditagih ke pelanggan
}

HargaGrosirTier? _pilihTierGrosir(num qty, List<HargaGrosirTier> tiers) {
  final terpenuhi = tiers.where((t) => qty >= t.minQty).toList();
  if (terpenuhi.isEmpty) return null;
  final minQtyTerbesar = terpenuhi.map((t) => t.minQty).reduce((a, b) => a > b ? a : b);
  final kandidat = terpenuhi.where((t) => t.minQty == minQtyTerbesar).toList();
  final khususOutlet = kandidat.where((t) => t.outletId != null).toList();
  return khususOutlet.isNotEmpty ? khususOutlet.first : kandidat.first;
}

int _hargaSatuanItem(ItemInput item, Set<String> fiturAktif, TipeOrderInput? tipeOrder) {
  int basis = item.hargaOutlet ?? item.hargaJual;

  if (fiturAktif.contains('harga_grosir')) {
    final tier = _pilihTierGrosir(item.qty, item.hargaGrosirTiers);
    if (tier != null) basis = tier.harga;
  }

  if (fiturAktif.contains('tipe_order') && tipeOrder != null && tipeOrder.markupPersen != 0) {
    basis = bulatkan(basis * (1 + tipeOrder.markupPersen / 100));
  }

  final tambahanModifier = item.modifiers.fold<int>(0, (sum, m) => sum + m.harga);
  return basis + tambahanModifier;
}

int _diskonPromoNilai(int basis, PromoInput promo) {
  if (basis < promo.minBelanja) return 0;
  int mentah;
  if (promo.tipe == 'persen') {
    mentah = bulatkan(basis * promo.nilai / 100);
  } else if (promo.tipe == 'nominal') {
    mentah = bulatkan(promo.nilai);
  } else {
    throw ArgumentError('Tipe promo tidak dikenal: ${promo.tipe}');
  }
  var diskon = mentah.clamp(0, basis);
  if (promo.maksDiskon != null && diskon > promo.maksDiskon!) {
    diskon = promo.maksDiskon!;
  }
  return diskon;
}

({int total, List<RincianPajakOutput> rincian}) _cascadePajak(int basis, List<PajakInput> daftar) {
  final terurut = [...daftar]..sort((a, b) => a.urutan.compareTo(b.urutan));
  var base = basis;
  var total = 0;
  final rincian = <RincianPajakOutput>[];
  for (final p in terurut) {
    final jumlah = bulatkan(base * p.persen / 100);
    rincian.add(RincianPajakOutput(nama: p.nama, persen: p.persen, jumlah: jumlah, termasukHarga: p.termasukHarga));
    if (!p.termasukHarga) {
      total += jumlah;
      base += jumlah;
    }
  }
  return (total: total, rincian: rincian);
}

({int dibulatkan, int selisih}) _bulatkanTotal(int total, int pembulatan) {
  if (pembulatan <= 0) return (dibulatkan: total, selisih: 0);
  final dibulatkan = (total / pembulatan).round() * pembulatan;
  return (dibulatkan: dibulatkan, selisih: dibulatkan - total);
}

HasilKalkulasi hitung(TransaksiInput data) {
  final fitur = data.fiturAktif;

  final itemHasil = <RincianItemOutput>[];
  for (final item in data.items) {
    final hargaSatuan = _hargaSatuanItem(item, fitur, data.tipeOrder);
    final garisKotor = bulatkan(item.qty * hargaSatuan);

    int diskonItem;
    if (item.diskonOverride != null) {
      diskonItem = item.diskonOverride!;
    } else if (data.promo != null && data.promo!.cakupan == 'produk' && data.promo!.produkIds.contains(item.produkId)) {
      diskonItem = _diskonPromoNilai(garisKotor, data.promo!);
    } else {
      diskonItem = 0;
    }

    itemHasil.add(RincianItemOutput(
      produkId: item.produkId,
      varianId: item.varianId,
      qty: item.qty,
      hargaSatuan: hargaSatuan,
      diskon: diskonItem,
      subtotal: garisKotor - diskonItem,
    ));
  }

  final subtotal = itemHasil.fold<int>(0, (sum, i) => sum + i.subtotal);

  var diskonMember = 0;
  if (fitur.contains('diskon_member') && data.diskonMemberPersen != null && data.diskonMemberPersen! > 0) {
    diskonMember = bulatkan(subtotal * data.diskonMemberPersen! / 100).clamp(0, subtotal);
  }

  final basisSetelahMember = subtotal - diskonMember;

  var diskonPromoTransaksi = 0;
  if (data.promo != null && data.promo!.cakupan == 'transaksi') {
    diskonPromoTransaksi = _diskonPromoNilai(subtotal, data.promo!).clamp(0, basisSetelahMember);
  }

  final basisSetelahDiskon = basisSetelahMember - diskonPromoTransaksi;
  final totalDiskon = diskonMember + diskonPromoTransaksi;

  var serviceList = data.serviceDefault;
  if (fitur.contains('service_per_tipe_order') && data.tipeOrder != null) {
    serviceList = data.serviceDefault.where((p) => data.tipeOrder!.pajakIds.contains(p.id)).toList();
  }

  final hasilService = _cascadePajak(basisSetelahDiskon, serviceList);
  final serviceTotal = hasilService.total;
  final rincianService = hasilService.rincian;
  final basisPajak = basisSetelahDiskon + serviceTotal;

  final adaOverride = fitur.contains('pajak_per_produk') && data.items.any((i) => i.pajakProduk != null);

  int pajakTotal;
  List<RincianPajakOutput> rincianPajak;

  if (!adaOverride || subtotal == 0) {
    final hasilPajak = _cascadePajak(basisPajak, data.pajakDefault);
    pajakTotal = hasilPajak.total;
    rincianPajak = hasilPajak.rincian;
  } else {
    pajakTotal = 0;
    final gabungan = <String, _KunciPajak>{};
    var sisaBasis = basisPajak;
    final n = data.items.length;
    for (var idx = 0; idx < n; idx++) {
      final item = data.items[idx];
      final hasilItem = itemHasil[idx];
      int basisItem;
      if (idx == n - 1) {
        basisItem = sisaBasis;
      } else {
        final proporsi = subtotal != 0 ? hasilItem.subtotal / subtotal : 0;
        basisItem = bulatkan(basisPajak * proporsi);
        sisaBasis -= basisItem;
      }
      final daftar = item.pajakProduk ?? data.pajakDefault;
      final hasilItemPajak = _cascadePajak(basisItem, daftar);
      pajakTotal += hasilItemPajak.total;
      for (final r in hasilItemPajak.rincian) {
        final key = '${r.nama}|${r.persen}|${r.termasukHarga}';
        final existing = gabungan[key];
        if (existing == null) {
          gabungan[key] = _KunciPajak(nama: r.nama, persen: r.persen, termasukHarga: r.termasukHarga, jumlah: r.jumlah);
        } else {
          existing.jumlah += r.jumlah;
        }
      }
    }
    rincianPajak = gabungan.values
        .map((k) => RincianPajakOutput(nama: k.nama, persen: k.persen, jumlah: k.jumlah, termasukHarga: k.termasukHarga))
        .toList();
  }

  final totalSebelumPembulatan = basisPajak + pajakTotal;
  final hasilBulat = _bulatkanTotal(totalSebelumPembulatan, data.pembulatan);

  return HasilKalkulasi(
    items: itemHasil,
    subtotal: subtotal,
    diskonMember: diskonMember,
    diskonPromo: diskonPromoTransaksi,
    totalDiskon: totalDiskon,
    service: serviceTotal,
    rincianService: rincianService,
    pajak: pajakTotal,
    rincianPajak: rincianPajak,
    totalSebelumPembulatan: totalSebelumPembulatan,
    pembulatan: hasilBulat.selisih,
    total: hasilBulat.dibulatkan,
  );
}

class _KunciPajak {
  _KunciPajak({required this.nama, required this.persen, required this.termasukHarga, required this.jumlah});

  final String nama;
  final num persen;
  final bool termasukHarga;
  int jumlah;
}
