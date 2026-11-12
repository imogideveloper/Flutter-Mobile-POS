/// Teks WhatsApp untuk mengabari pelanggan bahwa pesanannya siap (IMOGI no. 26).
/// FUNGSI MURNI supaya mudah dites. [namaPelanggan] dan [namaToko] boleh kosong.
String pesanPesananSiap({
  required String judul,
  required bool antar,
  String? namaPelanggan,
  String? namaToko,
}) {
  final sapaan = (namaPelanggan == null || namaPelanggan.trim().isEmpty) ? 'Halo' : 'Halo ${namaPelanggan.trim()}';
  final tempat = (namaToko == null || namaToko.trim().isEmpty) ? '' : ' di ${namaToko.trim()}';
  final inti = antar
      ? 'sudah siap dan akan segera diantar'
      : 'sudah siap, silakan diambil';
  return '$sapaan, pesanan $judul$tempat $inti. Terima kasih!';
}
