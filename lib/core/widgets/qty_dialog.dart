import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Isian jumlah manual (mis. 24 botol sekaligus). Mengembalikan jumlah, atau null
/// bila dibatalkan. Jumlah 0 berarti hapus dari keranjang; pemanggil yang menanganinya.
Future<double?> tampilkanIsiJumlah(BuildContext context, {required String judul, required num awal}) {
  final controller = TextEditingController(text: awal % 1 == 0 ? awal.toStringAsFixed(0) : awal.toString());
  controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  return showDialog<double>(
    context: context,
    builder: (ctx) {
      void simpan() {
        final nilai = double.tryParse(controller.text.trim().replaceAll(',', '.'));
        if (nilai == null || nilai < 0) return;
        Navigator.of(ctx).pop(nilai);
      }

      return AlertDialog(
        title: Text(judul, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: TextField(
          key: const Key('qty.isi'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(labelText: 'Jumlah', helperText: '0 = hapus dari keranjang'),
          onSubmitted: (_) => simpan(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
          FilledButton(key: const Key('qty.simpan'), onPressed: simpan, child: const Text('Simpan')),
        ],
      );
    },
  );
}
