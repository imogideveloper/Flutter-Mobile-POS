// Setiap file di shared/fixtures/harga/*.json dibaca di sini DAN di
// backend/tests/test_harga_fixtures.py (Python) - keduanya harus
// menghasilkan angka yang identik, supaya kalkulator.py dan
// kalkulator.dart tidak diam-diam melenceng. Lihat docs/aturan_harga.md.
import 'dart:convert';
import 'dart:io';

import 'package:apps_pos/core/harga/kalkulator.dart' as k;
import 'package:flutter_test/flutter_test.dart';

k.ItemInput _item(Map<String, dynamic> d) {
  return k.ItemInput(
    produkId: d['produk_id'] as String,
    varianId: d['varian_id'] as String?,
    namaProduk: (d['nama_produk'] as String?) ?? '',
    qty: d['qty'] as num,
    hargaJual: (d['harga_jual'] as num).toInt(),
    hargaOutlet: (d['harga_outlet'] as num?)?.toInt(),
    hargaGrosirTiers: ((d['harga_grosir_tiers'] as List?) ?? const [])
        .map((t) => k.HargaGrosirTier(
              minQty: (t as Map<String, dynamic>)['min_qty'] as num,
              harga: (t['harga'] as num).toInt(),
              outletId: t['outlet_id'] as String?,
            ))
        .toList(),
    modifiers: ((d['modifiers'] as List?) ?? const [])
        .map((m) => k.ModifierInput(nama: (m as Map<String, dynamic>)['nama'] as String, harga: (m['harga'] as num).toInt()))
        .toList(),
    pajakProduk: d['pajak_produk'] == null
        ? null
        : (d['pajak_produk'] as List).map((p) => _pajak(p as Map<String, dynamic>)).toList(),
  );
}

k.PajakInput _pajak(Map<String, dynamic> d) {
  return k.PajakInput(
    id: d['id'] as String,
    nama: d['nama'] as String,
    persen: d['persen'] as num,
    termasukHarga: d['termasuk_harga'] as bool,
    urutan: (d['urutan'] as num?)?.toInt() ?? 0,
  );
}

k.PromoInput? _promo(Map<String, dynamic>? d) {
  if (d == null) return null;
  return k.PromoInput(
    id: d['id'] as String,
    nama: d['nama'] as String,
    tipe: d['tipe'] as String,
    cakupan: d['cakupan'] as String,
    nilai: d['nilai'] as num,
    minBelanja: ((d['min_belanja'] as num?) ?? 0).toInt(),
    maksDiskon: (d['maks_diskon'] as num?)?.toInt(),
    produkIds: ((d['produk_ids'] as List?) ?? const []).map((e) => e as String).toSet(),
  );
}

k.TipeOrderInput? _tipeOrder(Map<String, dynamic>? d) {
  if (d == null) return null;
  return k.TipeOrderInput(
    id: d['id'] as String,
    markupPersen: (d['markup_persen'] as num?) ?? 0,
    pajakIds: ((d['pajak_ids'] as List?) ?? const []).map((e) => e as String).toSet(),
  );
}

k.TransaksiInput _input(Map<String, dynamic> d) {
  return k.TransaksiInput(
    items: (d['items'] as List).map((i) => _item(i as Map<String, dynamic>)).toList(),
    fiturAktif: ((d['fitur_aktif'] as List?) ?? const []).map((e) => e as String).toSet(),
    promo: _promo(d['promo'] as Map<String, dynamic>?),
    diskonMemberPersen: d['diskon_member_persen'] as num?,
    tipeOrder: _tipeOrder(d['tipe_order'] as Map<String, dynamic>?),
    pajakDefault: ((d['pajak_default'] as List?) ?? const []).map((p) => _pajak(p as Map<String, dynamic>)).toList(),
    serviceDefault: ((d['service_default'] as List?) ?? const []).map((p) => _pajak(p as Map<String, dynamic>)).toList(),
    pembulatan: (d['pembulatan'] as num?)?.toInt() ?? 0,
  );
}

List<File> _semuaFixture() {
  Directory dir = Directory('shared/fixtures/harga');
  if (!dir.existsSync()) {
    dir = Directory('${Directory.current.path}/../shared/fixtures/harga');
  }
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void main() {
  final fixtures = _semuaFixture();

  test('ada minimal 25 fixture harga', () {
    expect(fixtures.length, greaterThanOrEqualTo(25));
  });

  for (final file in fixtures) {
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final nama = data['nama'] as String;

    test('fixture: $nama (${file.path.split(Platform.pathSeparator).last})', () {
      final hasil = k.hitung(_input(data['input'] as Map<String, dynamic>));
      final exp = data['expected'] as Map<String, dynamic>;

      expect(hasil.subtotal, (exp['subtotal'] as num).toInt());
      expect(hasil.diskonMember, (exp['diskon_member'] as num).toInt());
      expect(hasil.diskonPromo, (exp['diskon_promo'] as num).toInt());
      expect(hasil.totalDiskon, (exp['total_diskon'] as num).toInt());
      expect(hasil.service, (exp['service'] as num).toInt());
      expect(hasil.pajak, (exp['pajak'] as num).toInt());
      expect(hasil.totalSebelumPembulatan, (exp['total_sebelum_pembulatan'] as num).toInt());
      expect(hasil.pembulatan, (exp['pembulatan'] as num).toInt());
      expect(hasil.total, (exp['total'] as num).toInt());

      final itemsExp = exp['items'] as List;
      expect(hasil.items.length, itemsExp.length);
      for (var i = 0; i < itemsExp.length; i++) {
        final ie = itemsExp[i] as Map<String, dynamic>;
        expect(hasil.items[i].produkId, ie['produk_id']);
        expect(hasil.items[i].hargaSatuan, (ie['harga_satuan'] as num).toInt());
        expect(hasil.items[i].diskon, (ie['diskon'] as num).toInt());
        expect(hasil.items[i].subtotal, (ie['subtotal'] as num).toInt());
      }

      final serviceExp = exp['rincian_service'] as List;
      expect(hasil.rincianService.length, serviceExp.length);
      for (var i = 0; i < serviceExp.length; i++) {
        final re = serviceExp[i] as Map<String, dynamic>;
        expect(hasil.rincianService[i].nama, re['nama']);
        expect(hasil.rincianService[i].jumlah, (re['jumlah'] as num).toInt());
        expect(hasil.rincianService[i].termasukHarga, re['termasuk_harga']);
      }

      final pajakExp = [...(exp['rincian_pajak'] as List).cast<Map<String, dynamic>>()]
        ..sort((a, b) => (a['nama'] as String).compareTo(b['nama'] as String));
      final pajakHasil = [...hasil.rincianPajak]..sort((a, b) => a.nama.compareTo(b.nama));
      expect(pajakHasil.length, pajakExp.length);
      for (var i = 0; i < pajakExp.length; i++) {
        expect(pajakHasil[i].nama, pajakExp[i]['nama']);
        expect(pajakHasil[i].jumlah, (pajakExp[i]['jumlah'] as num).toInt());
        expect(pajakHasil[i].termasukHarga, pajakExp[i]['termasuk_harga']);
      }
    });
  }
}
