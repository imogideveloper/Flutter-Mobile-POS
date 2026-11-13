import '../../produk/domain/kategori.dart';
import '../../produk/domain/produk.dart';

/// Penyaring produk di layar kasir (IMOGI no. 36: tab kategori di kasir). FUNGSI MURNI.
///
/// [kataCari] mencocokkan nama atau SKU (huruf kecil); [kategoriId] null = semua kategori.
/// Produk tanpa kategori hanya tampil pada "Semua" dan saat mencari.
List<Produk> saringProdukKasir(List<Produk> items, {String kataCari = '', String? kategoriId}) {
  final kata = kataCari.trim().toLowerCase();
  return [
    for (final p in items)
      if ((kategoriId == null || p.kategoriId == kategoriId) &&
          (kata.isEmpty || p.nama.toLowerCase().contains(kata) || (p.sku?.toLowerCase().contains(kata) ?? false)))
        p,
  ];
}

/// Kategori yang punya minimal satu produk, mengikuti urutan kategori (kolom urutan, lalu nama).
/// Kategori kosong tidak ditampilkan supaya kasir tidak mengetuk tab yang kosong.
List<Kategori> kategoriDenganProduk(List<Kategori> kategori, List<Produk> items) {
  final dipakai = {for (final p in items) ?p.kategoriId};
  final hasil = [for (final k in kategori) if (dipakai.contains(k.id)) k];
  hasil.sort((a, b) {
    final u = a.urutan.compareTo(b.urutan);
    return u != 0 ? u : a.nama.toLowerCase().compareTo(b.nama.toLowerCase());
  });
  return hasil;
}
