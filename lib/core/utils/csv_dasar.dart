/// Pembaca dan penulis CSV dasar, dipakai impor/ekspor produk dan pelanggan. FUNGSI MURNI.

/// Membaca teks CSV menjadi daftar baris berisi sel. Pemisah (koma atau titik koma, umum di Excel
/// Indonesia) dideteksi dari baris pertama yang tidak kosong; BOM di awal dibuang; sel bertanda petik
/// boleh memuat pemisah, baris baru, dan petik ganda (ditulis dua petik). Baris kosong dilewati.
List<List<String>> bacaBarisCsv(String teks) {
  final isi = teks.startsWith('﻿') ? teks.substring(1) : teks;
  return _uraiCsv(isi, _deteksiPemisah(isi)).where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

/// Satu sel untuk ditulis ke CSV: diberi tanda petik bila perlu, dan sel berawalan `= + - @` (selain
/// angka murni) diberi apostrof agar tidak dibaca Excel sebagai rumus.
String selCsv(String nilai) {
  var v = nilai;
  if (v.isNotEmpty && '=+-@'.contains(v[0]) && double.tryParse(v) == null) v = "'$v";
  if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r') || v.contains(';')) {
    v = '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

String _deteksiPemisah(String isi) {
  final barisPertama = isi.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final koma = ','.allMatches(barisPertama).length;
  final titikKoma = ';'.allMatches(barisPertama).length;
  return titikKoma > koma ? ';' : ',';
}

List<List<String>> _uraiCsv(String isi, String pemisah) {
  final rows = <List<String>>[];
  var row = <String>[];
  final sel = StringBuffer();
  var dalamPetik = false;

  void akhiriSel() {
    row.add(sel.toString());
    sel.clear();
  }

  void akhiriBaris() {
    akhiriSel();
    rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < isi.length; i++) {
    final c = isi[i];
    if (dalamPetik) {
      if (c == '"') {
        if (i + 1 < isi.length && isi[i + 1] == '"') {
          sel.write('"');
          i++;
        } else {
          dalamPetik = false;
        }
      } else {
        sel.write(c);
      }
    } else if (c == '"') {
      dalamPetik = true;
    } else if (c == pemisah) {
      akhiriSel();
    } else if (c == '\n') {
      akhiriBaris();
    } else if (c == '\r') {
      // dilewati; \n yang menutup baris
    } else {
      sel.write(c);
    }
  }
  if (sel.isNotEmpty || row.isNotEmpty) akhiriBaris();
  return rows;
}
