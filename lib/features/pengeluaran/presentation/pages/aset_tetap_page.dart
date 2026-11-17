import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import 'settlement_page.dart' show tanggalIso;

/// Aset tetap beserta penyusutan garis lurus per hari ini, dari server.
class AsetTetapItem {
  const AsetTetapItem({
    required this.id,
    required this.nama,
    required this.hargaPerolehan,
    required this.umurBulan,
    required this.bulanBerjalan,
    required this.akumulasi,
    required this.nilaiBuku,
    required this.penyusutanBulanIni,
  });

  factory AsetTetapItem.dariJson(Map<String, dynamic> j) => AsetTetapItem(
        id: j['id'] as String,
        nama: j['nama'] as String,
        hargaPerolehan: _int(j['harga_perolehan']),
        umurBulan: j['umur_bulan'] as int,
        bulanBerjalan: j['bulan_berjalan'] as int,
        akumulasi: _int(j['akumulasi_penyusutan']),
        nilaiBuku: _int(j['nilai_buku']),
        penyusutanBulanIni: _int(j['penyusutan_bulan_ini']),
      );

  final String id;
  final String nama;
  final int hargaPerolehan;
  final int umurBulan;
  final int bulanBerjalan;
  final int akumulasi;
  final int nilaiBuku;
  final int penyusutanBulanIni;

  static int _int(Object? v) => double.parse('$v').round();
}

/// Aset tetap & penyusutan (IMOGI no. 83). Butuh internet; penyusutan dihitung server.
class AsetTetapPage extends ConsumerStatefulWidget {
  const AsetTetapPage({super.key});

  @override
  ConsumerState<AsetTetapPage> createState() => _AsetTetapPageState();
}

class _AsetTetapPageState extends ConsumerState<AsetTetapPage> {
  List<AsetTetapItem> _aset = const [];
  int _totalBuku = 0;
  int _totalBulanIni = 0;
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
      final json = await ref.read(backendApiProvider).getJson(accessToken: await _token(), path: '/aset-tetap');
      final m = json as Map;
      _aset = [for (final a in m['aset'] as List) AsetTetapItem.dariJson(Map<String, dynamic>.from(a as Map))];
      _totalBuku = AsetTetapItem._int(m['total_nilai_buku']);
      _totalBulanIni = AsetTetapItem._int(m['total_penyusutan_bulan_ini']);
    } on BackendException catch (e) {
      _aset = const [];
      _error = e.tidakAdaKoneksi ? 'Butuh internet untuk melihat aset tetap.' : e.message;
    } catch (e) {
      _aset = const [];
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _tambah() async {
    final body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _TambahAsetDialog());
    if (body == null || !mounted) return;
    try {
      await ref.read(backendApiProvider).postJson(accessToken: await _token(), path: '/aset-tetap', body: body);
      if (!mounted) return;
      showAppToast(context, message: 'Aset ditambahkan', variant: ToastVariant.success);
      await _muat();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  Future<void> _hapus(AsetTetapItem a) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus aset?'),
        content: Text('"${a.nama}" tidak akan dihitung lagi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    try {
      await ref.read(backendApiProvider).deleteJson(accessToken: await _token(), path: '/aset-tetap/${a.id}');
      await _muat();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  String _rp(int n) => 'Rp ${formatRupiahDigits(n)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aset tetap & penyusutan')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('aset.tambah'),
        onPressed: _tambah,
        icon: const Icon(Icons.add),
        label: const Text('Tambah aset'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(icon: Icons.cloud_off_outlined, message: _error!)
              : _aset.isEmpty
                  ? const EmptyState(icon: Icons.precision_manufacturing_outlined, message: 'Belum ada aset tetap')
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      children: [
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total nilai buku', style: AppTypography.secondary),
                              Text(_rp(_totalBuku), key: const Key('aset.totalBuku'), style: AppTypography.cardTitle),
                              Text('Penyusutan bulan ini: ${_rp(_totalBulanIni)}'),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final a in _aset)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.md),
                            child: AppCard(
                              key: Key('aset.${a.id}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(a.nama, style: AppTypography.cardTitle)),
                                      IconButton(
                                        tooltip: 'Hapus',
                                        onPressed: () => _hapus(a),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                  Text('Perolehan ${_rp(a.hargaPerolehan)} - umur ${a.umurBulan} bulan'),
                                  Text('Berjalan ${a.bulanBerjalan} bulan - akumulasi ${_rp(a.akumulasi)}'),
                                  Text('Nilai buku ${_rp(a.nilaiBuku)}'),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _TambahAsetDialog extends StatefulWidget {
  const _TambahAsetDialog();

  @override
  State<_TambahAsetDialog> createState() => _TambahAsetDialogState();
}

class _TambahAsetDialogState extends State<_TambahAsetDialog> {
  final _nama = TextEditingController();
  final _harga = TextEditingController();
  final _residu = TextEditingController();
  final _umur = TextEditingController(text: '48');
  DateTime _tanggal = DateTime.now();
  String? _salah;

  @override
  void dispose() {
    _nama.dispose();
    _harga.dispose();
    _residu.dispose();
    _umur.dispose();
    super.dispose();
  }

  void _simpan() {
    final harga = parseRupiahInput(_harga.text);
    final residu = parseRupiahInput(_residu.text) ?? 0;
    final umur = int.tryParse(_umur.text.trim());
    String? salah;
    if (_nama.text.trim().isEmpty) {
      salah = 'Nama aset wajib diisi';
    } else if (harga == null || harga <= 0) {
      salah = 'Harga perolehan wajib diisi';
    } else if (residu >= harga) {
      salah = 'Nilai residu harus lebih kecil dari harga';
    } else if (umur == null || umur <= 0) {
      salah = 'Umur (bulan) wajib diisi';
    }
    if (salah != null) {
      setState(() => _salah = salah);
      return;
    }
    Navigator.pop(context, {
      'nama': _nama.text.trim(),
      'tanggal_perolehan': tanggalIso(_tanggal),
      'harga_perolehan': '$harga',
      'nilai_residu': '$residu',
      'umur_bulan': umur,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah aset tetap'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(key: const Key('aset.nama'), controller: _nama, decoration: const InputDecoration(labelText: 'Nama aset')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tanggal perolehan'),
              subtitle: Text(tanggalIso(_tanggal)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final t = await showDatePicker(
                  context: context,
                  initialDate: _tanggal,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (t != null) setState(() => _tanggal = t);
              },
            ),
            TextField(
              key: const Key('aset.harga'),
              controller: _harga,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, RupiahInputFormatter()],
              decoration: const InputDecoration(labelText: 'Harga perolehan', prefixText: 'Rp '),
            ),
            TextField(
              key: const Key('aset.residu'),
              controller: _residu,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, RupiahInputFormatter()],
              decoration: const InputDecoration(labelText: 'Nilai residu', prefixText: 'Rp '),
            ),
            TextField(
              key: const Key('aset.umur'),
              controller: _umur,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Umur manfaat (bulan)'),
            ),
            if (_salah != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_salah!, key: const Key('aset.salah'), style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(key: const Key('aset.simpan'), onPressed: _simpan, child: const Text('Simpan')),
      ],
    );
  }
}
