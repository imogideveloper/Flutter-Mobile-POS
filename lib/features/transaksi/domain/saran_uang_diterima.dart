/// Tombol nominal cepat di layar bayar tunai: uang pas lalu pecahan uang kertas terdekat di atas total.
///
/// Dulu tombol kedua memakai `total + 25.000`, yang menghasilkan angka yang tidak pernah dipegang
/// pelanggan (mis. total 18.711 menjadi 43.711). Pelanggan membayar dengan lembar 50.000 / 100.000.
List<int> saranUangDiterima(int total) {
  if (total <= 0) return const [];
  int naikKe(int kelipatan) => ((total + kelipatan - 1) ~/ kelipatan) * kelipatan;
  // Set menjaga urutan sisip dan membuang duplikat (total 50.000: pas = lembar 50.000).
  return {total, naikKe(50000), naikKe(100000)}.toList();
}
