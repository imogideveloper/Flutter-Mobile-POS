import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../produk/domain/grup_tambahan.dart';
import '../../../produk/domain/produk.dart';
import '../../domain/item_keranjang.dart';

final _rupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

/// Lembar pilih varian/tambahan produk (dokumen IMOGI no. 42). Mengembalikan
/// pilihan kasir, atau null bila dibatalkan.
Future<List<ModifierPilihan>?> tampilkanPilihTambahan(
  BuildContext context, {
  required Produk produk,
  required List<GrupTambahan> grup,
}) {
  return showModalBottomSheet<List<ModifierPilihan>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => PilihTambahanSheet(produk: produk, grup: grup),
  );
}

class PilihTambahanSheet extends StatefulWidget {
  const PilihTambahanSheet({super.key, required this.produk, required this.grup});

  final Produk produk;
  final List<GrupTambahan> grup;

  @override
  State<PilihTambahanSheet> createState() => _PilihTambahanSheetState();
}

class _PilihTambahanSheetState extends State<PilihTambahanSheet> {
  /// grupId -> id opsi terpilih (urut dipilih).
  final Map<String, List<String>> _pilih = {};
  bool _sudahCoba = false;

  List<String> _terpilih(GrupTambahan g) => _pilih[g.id] ?? const [];

  void _ketuk(GrupTambahan g, OpsiTambahan o) {
    setState(() {
      final saat = [..._terpilih(g)];
      if (saat.contains(o.id)) {
        // Grup wajib pilih-tunggal tidak boleh dikosongkan dengan ketukan kedua.
        if (!(g.pilihTunggal && g.wajib)) saat.remove(o.id);
      } else if (g.pilihTunggal) {
        saat
          ..clear()
          ..add(o.id);
      } else if (g.maksPilih == 0 || saat.length < g.maksPilih) {
        saat.add(o.id);
      }
      _pilih[g.id] = saat;
    });
  }

  List<ModifierPilihan> get _hasil => [
        for (final g in widget.grup)
          for (final o in g.opsi)
            if (_terpilih(g).contains(o.id)) ModifierPilihan(modifierId: o.id, nama: o.nama, harga: o.harga),
      ];

  int get _tambahan => _hasil.fold(0, (a, m) => a + m.harga);

  String? get _galat {
    for (final g in widget.grup) {
      final pesan = g.validasi(_terpilih(g).length);
      if (pesan != null) return pesan;
    }
    return null;
  }

  void _simpan() {
    if (_galat != null) {
      setState(() => _sudahCoba = true);
      return;
    }
    Navigator.of(context).pop(_hasil);
  }

  String _aturan(GrupTambahan g) {
    if (g.pilihTunggal) return g.wajib ? 'Wajib pilih 1' : 'Pilih 1 (opsional)';
    final maks = g.maksPilih == 0 ? '' : ', maks ${g.maksPilih}';
    return g.wajib ? 'Wajib minimal ${g.minPilih}$maks' : 'Opsional$maks';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.produk.hargaJual + _tambahan;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.produk.nama, style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                key: const Key('tambahan.tutup'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            children: [
              for (final g in widget.grup) ...[
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Row(
                    children: [
                      Text(g.nama, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _aturan(g),
                        style: TextStyle(
                          fontSize: 12,
                          color: _sudahCoba && g.validasi(_terpilih(g).length) != null
                              ? AppColors.dangerText
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final o in g.opsi)
                  InkWell(
                    key: Key('tambahan.opsi.${o.id}'),
                    onTap: () => _ketuk(g, o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          Icon(
                            g.pilihTunggal
                                ? (_terpilih(g).contains(o.id) ? Icons.radio_button_checked : Icons.radio_button_off)
                                : (_terpilih(g).contains(o.id) ? Icons.check_box : Icons.check_box_outline_blank),
                            color: _terpilih(g).contains(o.id) ? AppColors.primary : AppColors.textSecondary,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: Text(o.nama)),
                          if (o.harga != 0) Text('+${_rupiah.format(o.harga)}'),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_sudahCoba && _galat != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(_galat!, key: const Key('tambahan.galat'), style: const TextStyle(color: AppColors.dangerText)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('tambahan.simpan'),
                    onPressed: _simpan,
                    child: Text('Tambah · ${_rupiah.format(total)}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
