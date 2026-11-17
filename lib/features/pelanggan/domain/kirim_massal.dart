import 'pelanggan.dart';

/// Pesan WhatsApp ke banyak pelanggan (IMOGI no. 57). Aplikasi TIDAK mengirim otomatis: tiap pesan dibuka di
/// WhatsApp dan dikirim kasir sendiri (satu per satu), supaya tidak menyerupai spam dan tanpa biaya gateway.

/// "081234567890" / "+62812..." / "62812..." menjadi "62812..." (format wa.me). Null bila bukan nomor yang masuk akal
/// (kurang dari 8 atau lebih dari 15 digit setelah dibersihkan).
String? nomorWhatsApp(String? noHp) {
  if (noHp == null) return null;
  final digit = noHp.replaceAll(RegExp(r'[^0-9]'), '');
  if (digit.isEmpty) return null;
  final ke62 = digit.startsWith('62')
      ? digit
      : digit.startsWith('0')
          ? '62${digit.substring(1)}'
          : '62$digit';
  return ke62.length >= 10 && ke62.length <= 15 ? ke62 : null;
}

/// Pelanggan yang bisa dikirimi pesan: punya nomor WhatsApp yang sah. [levelMemberId] (opsional) menyaring
/// per level member; [kataCari] mencocokkan nama atau nomor. Nomor yang sama hanya muncul sekali.
List<Pelanggan> kandidatPenerima(
  Iterable<Pelanggan> semua, {
  String? levelMemberId,
  String kataCari = '',
}) {
  final cari = kataCari.trim().toLowerCase();
  final sudah = <String>{};
  final hasil = <Pelanggan>[];
  for (final p in semua) {
    final nomor = nomorWhatsApp(p.noHp);
    if (nomor == null) continue;
    if (levelMemberId != null && p.levelMemberId != levelMemberId) continue;
    if (cari.isNotEmpty && !p.nama.toLowerCase().contains(cari) && !(p.noHp ?? '').contains(cari)) continue;
    if (!sudah.add(nomor)) continue;
    hasil.add(p);
  }
  return hasil;
}

/// Mengisi {nama} dan {toko} pada [templat]. Nama kosong menjadi "Kak"; {toko} kosong dihapus.
String isiPesanMassal(String templat, {required String namaPelanggan, String? namaToko}) {
  final nama = namaPelanggan.trim().isEmpty ? 'Kak' : namaPelanggan.trim();
  return templat.replaceAll('{nama}', nama).replaceAll('{toko}', (namaToko ?? '').trim()).trim();
}
