import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pemeriksa gaya tampilan: dua kolom isian (TextField, TextFormField, dropdown) yang berurutan dalam satu
/// daftar anak TANPA widget jarak di antaranya membuat label mengambang kolom bawah menabrak tepi kolom atas
/// (ditemukan di HP 2026-11-23/24: dialog Tambah Level Member, Grup baru, dan belasan layar lain).
///
/// Cara memperbaiki bila tes ini gagal: sisipkan `const SizedBox(height: AppSpacing.lg),` sebelum kolom yang
/// disebut. Tes ini heuristik berbasis teks; widget isian yang dibungkus pembantu sendiri tidak terjaring.
final _tipe = RegExp(r'TextFormField|TextField|DropdownButtonFormField(<[^>(]*>)?|AppTextField|DropdownMenu(<[^>(]*>)?');
final _awalKolom = RegExp(r'^\s*(' + _tipe.pattern + r')\s*\(');

int _seimbang(String s) => '('.allMatches(s).length - ')'.allMatches(s).length;

int _indent(String s) => s.length - s.trimLeft().length;

List<String> _cariKolomMenempel(String nama, List<String> baris) {
  final hasil = <String>[];
  for (var i = 0; i < baris.length; i++) {
    if (!_awalKolom.hasMatch(baris[i])) continue;

    var akhir = -1;
    if (_seimbang(baris[i]) == 0 && baris[i].trimRight().endsWith('),')) {
      akhir = i;
    } else {
      final indent = _indent(baris[i]);
      for (var k = i + 1; k < baris.length; k++) {
        final t = baris[k].trim();
        if (t.isEmpty) continue;
        if (_indent(baris[k]) == indent && t.startsWith(')')) {
          akhir = k;
          break;
        }
        if (_indent(baris[k]) < indent) break;
      }
    }
    if (akhir < 0) continue;

    var m = akhir + 1;
    while (m < baris.length && baris[m].trim().isEmpty) {
      m++;
    }
    if (m < baris.length && _awalKolom.hasMatch(baris[m])) hasil.add('$nama:${m + 1}');
  }
  return hasil;
}

void main() {
  test('pemeriksa mengenali kolom menempel, baik satu baris maupun banyak baris', () {
    expect(
      _cariKolomMenempel('x.dart', [
        '  TextField(controller: a),',
        '  TextField(controller: b),',
      ]),
      ['x.dart:2'],
    );
    expect(
      _cariKolomMenempel('x.dart', [
        '  TextFormField(',
        '    controller: a,',
        '  ),',
        '  DropdownButtonFormField<int>(',
        '    items: [],',
        '  ),',
      ]),
      ['x.dart:4'],
    );
    expect(
      _cariKolomMenempel('x.dart', [
        '  TextField(controller: a),',
        '  const SizedBox(height: AppSpacing.lg),',
        '  TextField(controller: b),',
      ]),
      isEmpty,
    );
  });

  test('tidak ada dua kolom isian berurutan tanpa jarak di seluruh lib/', () {
    final temuan = <String>[];
    for (final berkas in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!berkas.path.endsWith('.dart')) continue;
      final nama = berkas.path.split(Platform.pathSeparator).join('/');
      final baris = berkas.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
      temuan.addAll(_cariKolomMenempel(nama, baris));
    }
    expect(temuan, isEmpty, reason: 'Kolom menempel (sisipkan SizedBox(height: AppSpacing.lg) sebelumnya):\n${temuan.join('\n')}');
  });
}
