import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _formatRibuan = NumberFormat.decimalPattern('id_ID');

/// TextInputFormatter yang menampilkan pemisah ribuan ("50000" -> "50.000")
/// sambil mengetik, tanpa prefix "Rp" (pakai InputDecoration.prefixText utk
/// itu). Kursor selalu didorong ke akhir - cukup utk field angka uang yang
/// diisi dengan mengetik dari kiri/backspace dari kanan (bukan field yang
/// sering diedit di tengah).
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final angka = int.parse(digitsOnly);
    final formatted = _formatRibuan.format(angka);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Format angka jadi string "50.000" - dipakai saat MENGISI controller dari
/// kode (mis. tombol nominal cepat), bukan dari ketikan pengguna (itu
/// tugasnya [RupiahInputFormatter]).
String formatRupiahDigits(int value) => _formatRibuan.format(value);

/// Ambil nilai integer murni dari text field yang pakai [RupiahInputFormatter]
/// (mis. "50.000" -> 50000). Aman dipanggil pada string kosong (-> null).
int? parseRupiahInput(String text) {
  final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) return null;
  return int.parse(digitsOnly);
}
