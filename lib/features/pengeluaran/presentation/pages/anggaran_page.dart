import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/pengeluaran.dart';

int _rp(Object? v) => double.parse('$v').round();

/// Satu baris anggaran per kategori biaya untuk satu bulan.
class BarisAnggaran {
  const BarisAnggaran({
    required this.kategori,
    required this.anggaran,
    required this.realisasi,
    required this.proyeksi,
    required this.status,
  });

  factory BarisAnggaran.dariJson(Map<String, dynamic> j) => BarisAnggaran(
        kategori: j['kategori'] as String,
        anggaran: _rp(j['anggaran']),
        realisasi: _rp(j['realisasi']),
        proyeksi: _rp(j['proyeksi']),
        status: j['status'] as String,
      );

  final String kategori;
  final int anggaran;
  final int realisasi;
  final int proyeksi;
  final String status; // aman | waspada | lewat | tanpa_anggaran

  /// 0..1 untuk batang kemajuan (dipotong di 1 saat melewati anggaran).
  double get rasio => anggaran <= 0 ? 0 : (realisasi / anggaran).clamp(0.0, 1.0);
}

String bulanIso(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}';

/// Anggaran & proyeksi arus kas (IMOGI no. 82). Butuh internet; angka dihitung server.
class AnggaranPage extends ConsumerStatefulWidget {
  const AnggaranPage({super.key});

  @override
  ConsumerState<AnggaranPage> createState() => _AnggaranPageState();
}

class _AnggaranPageState extends ConsumerState<AnggaranPage> {
  DateTime _bulan = DateTime(DateTime.now().year, DateTime.now().month);
  List<BarisAnggaran> _baris = const [];
  Map<String, dynamic> _ringkas = const {};
  String? _error;
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<String> _token() async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
    return sesi.accessToken;
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final json = await ref.read(backendApiProvider).getJson(
        accessToken: await _token(),
        path: '/anggaran',
        query: {'bulan': bulanIso(_bulan)},
      );
      _ringkas = Map<String, dynamic>.from(json as Map);
      _baris = [for (final b in _ringkas['baris'] as List) BarisAnggaran.dariJson(Map<String, dynamic>.from(b as Map))];
    } on BackendException catch (e) {
      _baris = const [];
      _error = e.tidakAdaKoneksi ? 'Butuh internet untuk melihat anggaran.' : e.message;
    } catch (e) {
      _baris = const [];
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  void _gantiBulan(int selisih) {
    _bulan = DateTime(_bulan.year, _bulan.month + selisih);
    _muat();
  }

  Future<void> _atur({String? kategori, int? awal}) async {
    final hasil = await showDialog<(String, int)>(
      context: context,
      builder: (_) => _AturAnggaranDialog(kategoriAwal: kategori, jumlahAwal: awal),
    );
    if (hasil == null || !mounted) return;
    try {
      await ref.read(backendApiProvider).putJsonBody(
        accessToken: await _token(),
        path: '/anggaran',
        body: {'bulan': bulanIso(_bulan), 'kategori': hasil.$1, 'jumlah': '${hasil.$2}'},
      );
      if (!mounted) return;
      showAppToast(context, message: 'Anggaran disimpan', variant: ToastVariant.success);
      await _muat();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  Future<void> _salin() async {
    final asal = DateTime(_bulan.year, _bulan.month - 1);
    try {
      final json = await ref.read(backendApiProvider).postJson(
        accessToken: await _token(),
        path: '/anggaran/salin',
        body: {'dari': bulanIso(asal), 'ke': bulanIso(_bulan)},
      );
      if (!mounted) return;
      final n = (json as Map)['disalin'] as int;
      showAppToast(
        context,
        message: n == 0 ? 'Semua kategori sudah punya anggaran' : '$n anggaran disalin dari ${bulanIso(asal)}',
        variant: ToastVariant.success,
      );
      await _muat();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  String _fmt(int n) => '${n < 0 ? '-' : ''}Rp ${formatRupiahDigits(n.abs())}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anggaran & proyeksi')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('anggaran.atur'),
        onPressed: _atur,
        icon: const Icon(Icons.add),
        label: const Text('Atur anggaran'),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('anggaran.sebelumnya'),
                onPressed: () => _gantiBulan(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(bulanIso(_bulan), key: const Key('anggaran.bulan'), style: AppTypography.cardTitle),
              IconButton(
                key: const Key('anggaran.berikutnya'),
                onPressed: () => _gantiBulan(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          TextButton.icon(
            key: const Key('anggaran.salin'),
            onPressed: _salin,
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('Salin anggaran dari bulan lalu'),
          ),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? EmptyState(icon: Icons.cloud_off_outlined, message: _error!)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, 96),
                        children: [
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Proyeksi akhir bulan', style: AppTypography.secondary),
                                Text('Penjualan ${_fmt(_rp(_ringkas['penjualan_proyeksi']))}',
                                    key: const Key('anggaran.proyeksiPenjualan')),
                                Text('Biaya ${_fmt(_rp(_ringkas['total_proyeksi']))}'),
                                Text(
                                  'Selisih kasar ${_fmt(_rp(_ringkas['arus_kas_proyeksi']))}',
                                  key: const Key('anggaran.arusKas'),
                                  style: AppTypography.cardTitle,
                                ),
                                Text(
                                  'Hari ke-${_ringkas['hari_berjalan']} dari ${_ringkas['jumlah_hari']}. '
                                  'Perkiraan linear, bukan laporan arus kas akuntansi.',
                                  style: AppTypography.secondary,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (_baris.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(AppSpacing.xl),
                              child: Text('Belum ada anggaran atau biaya bulan ini. Tekan "Atur anggaran".'),
                            ),
                          for (final b in _baris) _kartu(b),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _kartu(BarisAnggaran b) {
    final warna = switch (b.status) {
      'lewat' => AppColors.dangerText,
      'waspada' => AppColors.warningText,
      _ => AppColors.primary,
    };
    final label = switch (b.status) {
      'lewat' => 'Melebihi anggaran',
      'waspada' => 'Hampir habis',
      'tanpa_anggaran' => 'Belum dianggarkan',
      _ => 'Aman',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: () => _atur(kategori: b.kategori, awal: b.anggaran),
        child: AppCard(
          key: Key('anggaran.baris.${b.kategori}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(labelKategoriPengeluaran(b.kategori), style: AppTypography.cardTitle)),
                  Text(label, style: TextStyle(color: warna, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              if (b.anggaran > 0) LinearProgressIndicator(value: b.rasio, color: warna, minHeight: 6),
              const SizedBox(height: AppSpacing.xs),
              Text('Anggaran ${_fmt(b.anggaran)} - terpakai ${_fmt(b.realisasi)}'),
              Text('Proyeksi akhir bulan ${_fmt(b.proyeksi)}', style: AppTypography.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _AturAnggaranDialog extends StatefulWidget {
  const _AturAnggaranDialog({this.kategoriAwal, this.jumlahAwal});

  final String? kategoriAwal;
  final int? jumlahAwal;

  @override
  State<_AturAnggaranDialog> createState() => _AturAnggaranDialogState();
}

class _AturAnggaranDialogState extends State<_AturAnggaranDialog> {
  late String _kategori = widget.kategoriAwal ?? kategoriPengeluaran.keys.first;
  late final _jumlah = TextEditingController(
    text: (widget.jumlahAwal ?? 0) > 0 ? formatRupiahDigits(widget.jumlahAwal!) : '',
  );

  @override
  void dispose() {
    _jumlah.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Atur anggaran'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('anggaran.kategori'),
            initialValue: _kategori,
            items: [
              for (final k in kategoriPengeluaran.entries) DropdownMenuItem(value: k.key, child: Text(k.value)),
            ],
            onChanged: (v) => setState(() => _kategori = v ?? _kategori),
            decoration: const InputDecoration(labelText: 'Kategori biaya'),
          ),
          TextField(
            key: const Key('anggaran.jumlah'),
            controller: _jumlah,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, RupiahInputFormatter()],
            decoration: const InputDecoration(labelText: 'Anggaran bulan ini', prefixText: 'Rp '),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          key: const Key('anggaran.simpan'),
          onPressed: () => Navigator.pop(context, (_kategori, parseRupiahInput(_jumlah.text) ?? 0)),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
