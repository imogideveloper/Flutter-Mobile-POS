import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Kirim WhatsApp" (tahap 4 bagian D.5) - kalau pelanggan punya no HP,
/// buka tautan wa.me langsung ke nomor itu (format wajib "62..." tanpa
/// "+"/"0" di depan - lihat [_ke62]); kalau tidak ada, pakai share sheet
/// biasa (user pilih sendiri tujuannya, termasuk bisa WhatsApp juga).
Future<void> kirimStrukWhatsApp({required String teks, String? noHpPelanggan}) async {
  final noHp = noHpPelanggan == null ? null : _ke62(noHpPelanggan);
  if (noHp != null) {
    final uri = Uri.parse('https://wa.me/$noHp?text=${Uri.encodeComponent(teks)}');
    final berhasil = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (berhasil) return;
    // WhatsApp tidak terpasang/gagal dibuka - lanjut ke share sheet biasa
    // drpd diam2 gagal tanpa alternatif.
  }
  await SharePlus.instance.share(ShareParams(text: teks));
}

/// "081234567890" / "+62812..." / "62812..." semua jadi "62812..." (format
/// yang dipakai wa.me, tanpa "+"). Karakter non-digit (spasi/strip/kurung)
/// dibuang dulu.
String _ke62(String noHp) {
  final digit = noHp.replaceAll(RegExp(r'[^0-9]'), '');
  if (digit.startsWith('62')) return digit;
  if (digit.startsWith('0')) return '62${digit.substring(1)}';
  return '62$digit';
}
