// Setiap file di shared/fixtures/refund/*.json dibaca di sini DAN di
// backend/tests/test_refund_fixtures.py (Python) - keduanya harus
// menghasilkan angka yang identik. Lihat docs/aturan_harga.md bagian
// "Refund proporsional (F3.D)".
import 'dart:convert';
import 'dart:io';

import 'package:apps_pos/core/harga/refund_kalkulator.dart' as rk;
import 'package:flutter_test/flutter_test.dart';

rk.ItemRefundInput _item(Map<String, dynamic> d) {
  return rk.ItemRefundInput(
    itemTransaksiId: d['item_transaksi_id'] as String,
    qty: d['qty'] as num,
    hargaSatuan: (d['harga_satuan'] as num).toInt(),
    diskon: (d['diskon'] as num).toInt(),
    subtotal: (d['subtotal'] as num).toInt(),
  );
}

rk.RefundLineInput _line(Map<String, dynamic> d) {
  return rk.RefundLineInput(
    itemTransaksiId: d['item_transaksi_id'] as String,
    qtyRefund: d['qty_refund'] as num,
  );
}

List<File> _semuaFixture() {
  Directory dir = Directory('shared/fixtures/refund');
  if (!dir.existsSync()) {
    dir = Directory('${Directory.current.path}/../shared/fixtures/refund');
  }
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void main() {
  final fixtures = _semuaFixture();

  test('ada minimal 6 fixture refund', () {
    expect(fixtures.length, greaterThanOrEqualTo(6));
  });

  for (final file in fixtures) {
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final nama = data['nama'] as String;

    test('fixture: $nama (${file.path.split(Platform.pathSeparator).last})', () {
      final input = data['input'] as Map<String, dynamic>;
      final items = (input['items'] as List).map((i) => _item(i as Map<String, dynamic>)).toList();
      final refundLines =
          (input['refund_lines'] as List).map((r) => _line(r as Map<String, dynamic>)).toList();

      final hasil = rk.hitungRefundProporsional(
        items: items,
        diskonTransaksiTotal: (input['diskon_transaksi_total'] as num).toInt(),
        pajakServiceTotal: (input['pajak_service_total'] as num).toInt(),
        refundLines: refundLines,
      );

      final expLines = (data['expected'] as Map<String, dynamic>)['lines'] as List;
      final expById = {
        for (final l in expLines)
          (l as Map<String, dynamic>)['item_transaksi_id'] as String: (l['jumlah'] as num).toInt(),
      };

      expect(hasil.length, expById.length);
      for (final baris in hasil) {
        expect(baris.jumlah, expById[baris.itemTransaksiId], reason: baris.itemTransaksiId);
      }
    });
  }
}
