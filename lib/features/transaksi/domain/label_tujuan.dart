import 'dart:convert';

/// Label tujuan pembayaran (IMOGI no. 18): daftar tujuan uang untuk rekonsiliasi,
/// mis. QRIS -> GoPay, OVO, ShopeePay, BCA. Disimpan sebagai teks dipisah koma di
/// `metode_bayar.label_tujuan`; kasir memilih satu saat menerima pembayaran.
/// Aturan sama dengan server (backend/app/services/label_pembayaran.py).
const maksLabelTujuan = 10;
const maksPanjangLabelTujuan = 30;

/// Daftar label dari teks tersimpan (kosong bila null/kosong).
List<String> daftarLabelTujuan(String? csv) {
  if (csv == null) return const [];
  return [
    for (final bagian in csv.split(','))
      if (bagian.trim().isNotEmpty) bagian.trim(),
  ];
}

/// Rapikan isian pengguna: potong spasi, buang kosong dan duplikat (tanpa membedakan huruf
/// besar/kecil). Mengembalikan (hasil, galat); [hasil] null bila kosong.
({String? hasil, String? galat}) normalisasiLabelTujuan(String mentah) {
  final terlihat = <String>{};
  final hasil = <String>[];
  for (final bagian in mentah.split(',')) {
    final label = bagian.trim().split(RegExp(r'\s+')).join(' ');
    if (label.isEmpty || !terlihat.add(label.toLowerCase())) continue;
    if (label.length > maksPanjangLabelTujuan) {
      return (hasil: null, galat: 'Label "${label.substring(0, 12)}..." lebih dari $maksPanjangLabelTujuan karakter');
    }
    hasil.add(label);
  }
  if (hasil.length > maksLabelTujuan) {
    return (hasil: null, galat: 'Maksimal $maksLabelTujuan label per metode bayar');
  }
  return (hasil: hasil.isEmpty ? null : hasil.join(','), galat: null);
}

/// Galat bila metode punya label tujuan tetapi kasir belum memilih (rekonsiliasi butuh tujuan);
/// null bila valid. [pilihan] = label terpilih, boleh null.
String? validasiLabelTujuan({required List<String> tersedia, required String? pilihan}) {
  if (tersedia.isEmpty) return null;
  if (pilihan == null || pilihan.isEmpty) return 'Pilih label tujuan pembayaran';
  if (!tersedia.contains(pilihan)) return 'Label tujuan tidak dikenal';
  return null;
}

/// Isi `payload_gateway` pembayaran manual: 4 digit akhir kartu dan/atau label tujuan.
/// null bila tidak ada keduanya. Kunci sama dengan yang dibaca laporan (lokal dan server).
String? payloadPembayaranManual({String? empatDigitAkhirKartu, String? labelTujuan}) {
  final isi = <String, dynamic>{
    if (empatDigitAkhirKartu != null) 'empat_digit_akhir_kartu': empatDigitAkhirKartu,
    if (labelTujuan != null && labelTujuan.isNotEmpty) 'label_tujuan': labelTujuan,
  };
  return isi.isEmpty ? null : jsonEncode(isi);
}
