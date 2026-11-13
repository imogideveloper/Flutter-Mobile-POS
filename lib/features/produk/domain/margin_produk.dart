/// Margin produk dan penandanya (IMOGI no. 37, Harga beli & margin). FUNGSI MURNI supaya mudah dites.
///
/// Margin (%) = (harga jual - HPP) / harga jual x 100. Produk ditandai rendah bila margin di bawah
/// batas yang diatur per outlet (bawaan 50% untuk makanan dan minuman). HPP kosong tidak dianggap
/// margin 100%: ditandai tersendiri karena angkanya belum bisa dipercaya.
library;

enum StatusMargin {
  /// Harga jual belum diisi (atau produk tidak dijual): tidak ada yang dinilai.
  tidakDinilai,

  /// HPP belum diisi, margin tidak akurat.
  hppKosong,

  /// Margin di bawah batas.
  rendah,

  /// Margin sama dengan atau di atas batas.
  aman,
}

const batasMarginBawaan = 50;

/// Margin dalam persen dibulatkan; null bila harga jual belum diisi.
int? marginPersen({required int hargaJual, required int hpp}) {
  if (hargaJual <= 0) return null;
  return ((hargaJual - hpp) * 100 / hargaJual).round();
}

StatusMargin statusMargin({required int hargaJual, required int hpp, int batasPersen = batasMarginBawaan}) {
  if (hargaJual <= 0) return StatusMargin.tidakDinilai;
  if (hpp <= 0) return StatusMargin.hppKosong;
  // Perbandingan dengan bilangan bulat supaya tidak terpengaruh pembulatan: (jual - hpp)/jual < batas/100.
  return (hargaJual - hpp) * 100 < batasPersen * hargaJual ? StatusMargin.rendah : StatusMargin.aman;
}
