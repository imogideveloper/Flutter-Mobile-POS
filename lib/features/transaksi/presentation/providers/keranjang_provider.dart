import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../produk/domain/produk.dart';
import '../../../promo/domain/promo.dart';
import '../../../pelanggan/domain/ulang_tahun.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart' show pelangganAktifProvider;
import '../../../promo/presentation/providers/promo_providers.dart';
import '../../domain/item_keranjang.dart';

class KeranjangNotifier extends Notifier<List<ItemKeranjang>> {
  @override
  List<ItemKeranjang> build() => [];

  /// Menambah satu unit [produk]. [modifiers] = pilihan tambahan (varian/topping);
  /// pilihan berbeda menjadi baris terpisah, pilihan sama menambah qty barisnya.
  void tambah(Produk produk, {List<ModifierPilihan> modifiers = const []}) {
    final baru = ItemKeranjang(
      produkId: produk.id,
      namaProduk: produk.nama,
      hargaSatuan: produk.hargaJual,
      qty: 1,
      lacakStok: produk.lacakStok,
      modifiers: modifiers,
    );
    final index = state.indexWhere((item) => item.kunciBaris == baru.kunciBaris);
    if (index == -1) {
      state = [...state, baru];
      return;
    }
    ubahQty(baru.kunciBaris, state[index].qty + 1);
  }

  /// [kunciBaris] = ItemKeranjang.kunciBaris (sama dengan produkId untuk item tanpa tambahan).
  void ubahQty(String kunciBaris, double qty) {
    if (qty <= 0) {
      hapus(kunciBaris);
      return;
    }
    state = [
      for (final item in state)
        if (item.kunciBaris == kunciBaris) item.copyWith(qty: qty) else item,
    ];
  }

  void hapus(String kunciBaris) {
    state = state.where((item) => item.kunciBaris != kunciBaris).toList();
  }

  void kosongkan() {
    state = [];
    ref.read(keranjangPelangganIdProvider.notifier).state = null;
    ref.read(keranjangPromoIdProvider.notifier).state = null;
    ref.read(keranjangTipeOrderIdProvider.notifier).state = null;
    ref.read(keranjangCatatanProvider.notifier).state = null;
    ref.read(keranjangPoinDitukarProvider.notifier).state = 0;
    ref.read(draftPesananDibukaProvider.notifier).state = null;
  }

  /// F3.E.3 - buka kembali pesanan tersimpan (open bill) ke keranjang,
  /// GANTI isi keranjang saat ini (bukan digabung) - sesuai pola "satu
  /// transaksi aktif dalam satu waktu" yang sudah dipakai di seluruh app
  /// ini. Harga TIDAK disalin dari draft lama - keranjang akan menghitung
  /// ulang dari harga PRODUK SAAT INI lewat mesin hitung yang sama
  /// (hasilHargaKeranjangProvider), sesuai F3.E.3 ("harga dihitung ulang
  /// saat dibuka kembali").
  void muatDariPesananTersimpan({
    required String draftId,
    required List<ItemKeranjang> items,
    String? pelangganId,
    String? tipeOrderId,
    String? catatan,
  }) {
    state = items;
    ref.read(keranjangPelangganIdProvider.notifier).state = pelangganId;
    ref.read(keranjangTipeOrderIdProvider.notifier).state = tipeOrderId;
    ref.read(keranjangCatatanProvider.notifier).state = catatan;
    ref.read(keranjangPromoIdProvider.notifier).state = null;
    ref.read(keranjangPoinDitukarProvider.notifier).state = 0;
    ref.read(draftPesananDibukaProvider.notifier).state = draftId;
  }
}

/// Diisi dgn id draft kalau keranjang SAAT INI adalah hasil "buka kembali"
/// pesanan tersimpan - BayarPage/dkk pakai ini (bukan null) utk tahu
/// draft mana yang harus dihapus (lewat
/// TransaksiRepository.checkout(gantikanPesananTersimpanId: ...)) begitu
/// pembayaran ini sukses. null kalau keranjang ini transaksi baru biasa.
final draftPesananDibukaProvider = StateProvider<String?>((ref) => null);

final keranjangProvider =
    NotifierProvider<KeranjangNotifier, List<ItemKeranjang>>(
      KeranjangNotifier.new,
    );

final subtotalKeranjangProvider = Provider<int>((ref) {
  final items = ref.watch(keranjangProvider);
  return items.fold<int>(0, (sum, item) => sum + item.subtotal);
});

/// Metadata keranjang di LUAR daftar item - dipilih dari header layar
/// Keranjang (pelanggan, promo, tipe order) atau dialog catatan pesanan.
/// Provider terpisah (bukan digabung ke `ItemKeranjang`/state list di
/// atas) supaya operasi tambah/ubah qty per-item tidak perlu menyalin
/// metadata ini setiap kali.
final keranjangPelangganIdProvider = StateProvider<String?>((ref) => null);
final keranjangPromoIdProvider = StateProvider<String?>((ref) => null);
final keranjangTipeOrderIdProvider = StateProvider<String?>((ref) => null);
final keranjangCatatanProvider = StateProvider<String?>((ref) => null);
// Modul 10 (tukar poin) - jumlah POIN (bukan Rupiah) yang kasir pilih utk
// ditukar jadi diskon checkout ini. 0 = tidak menukar poin sama sekali.
final keranjangPoinDitukarProvider = StateProvider<int>((ref) => 0);

/// Apakah pelanggan di keranjang berulang tahun hari ini (IMOGI no. 56).
final keranjangPelangganUlangTahunProvider = Provider<bool>((ref) {
  final pelangganId = ref.watch(keranjangPelangganIdProvider);
  if (pelangganId == null) return false;
  final daftar = ref.watch(pelangganAktifProvider).maybeWhen(data: (v) => v, orElse: () => const []);
  for (final p in daftar) {
    if (p.id == pelangganId) return ulangTahunHariIni(p.tanggalLahir, DateTime.now());
  }
  return false;
});

/// Promo yang sedang terpilih (null kalau tidak ada/tidak valid lagi). Promo khusus ulang tahun
/// tidak berlaku bila pelanggan di keranjang tidak berulang tahun hari ini, termasuk bila pelanggan
/// diganti setelah promo dipilih. Semua jalur bayar memakai provider ini.
final keranjangPromoProvider = Provider<Promo?>((ref) {
  final promoId = ref.watch(keranjangPromoIdProvider);
  if (promoId == null) return null;
  final ulangTahun = ref.watch(keranjangPelangganUlangTahunProvider);
  final semua = ref
      .watch(promoAktifProvider)
      .maybeWhen(data: (v) => v, orElse: () => const []);
  for (final promo in semua) {
    if (promo.id == promoId) {
      if (promo.khususUlangTahun && !ulangTahun) return null;
      return promo;
    }
  }
  return null;
});
