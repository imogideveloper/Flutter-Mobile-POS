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
import '../../domain/pelanggan.dart';
import '../providers/pelanggan_providers.dart';

/// Pelanggan dengan saldo deposit (> 0).
class SaldoDeposit {
  const SaldoDeposit({required this.pelangganId, required this.nama, required this.saldo});

  factory SaldoDeposit.dariJson(Map<String, dynamic> j) => SaldoDeposit(
        pelangganId: j['pelanggan_id'] as String,
        nama: j['nama'] as String,
        saldo: double.parse('${j['saldo']}').round(),
      );

  final String pelangganId;
  final String nama;
  final int saldo;
}

/// Deposit pelanggan / pendapatan diterima di muka (IMOGI no. 79). Butuh internet. Top-up menambah saldo; "Pakai"
/// dicatat kasir saat pelanggan memakai deposit (belum jadi metode bayar otomatis di kasir).
class DepositPage extends ConsumerStatefulWidget {
  const DepositPage({super.key});

  @override
  ConsumerState<DepositPage> createState() => _DepositPageState();
}

class _DepositPageState extends ConsumerState<DepositPage> {
  List<SaldoDeposit> _saldo = const [];
  int _total = 0;
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
      final json = await ref.read(backendApiProvider).getJson(accessToken: await _token(), path: '/deposit/ringkasan');
      final m = json as Map;
      _total = double.parse('${m['total_saldo']}').round();
      _saldo = [for (final p in m['pelanggan'] as List) SaldoDeposit.dariJson(Map<String, dynamic>.from(p as Map))];
    } on BackendException catch (e) {
      _error = e.tidakAdaKoneksi ? 'Butuh internet untuk melihat deposit.' : e.message;
    } catch (e) {
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _catat({String? pelangganId}) async {
    final semua = ref.read(pelangganAktifProvider).value ?? const <Pelanggan>[];
    if (semua.isEmpty) {
      showAppToast(context, message: 'Belum ada pelanggan', variant: ToastVariant.warning);
      return;
    }
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CatatDepositDialog(pelanggan: [for (final p in semua) (p.id, p.nama)], awalId: pelangganId),
    );
    if (body == null || !mounted) return;
    try {
      await ref.read(backendApiProvider).postJson(accessToken: await _token(), path: '/deposit', body: body);
      if (!mounted) return;
      showAppToast(context, message: 'Deposit dicatat', variant: ToastVariant.success);
      await _muat();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  Future<void> _riwayat(SaldoDeposit s) async {
    try {
      final json = await ref.read(backendApiProvider).getJson(
            accessToken: await _token(),
            path: '/deposit/pelanggan/${s.pelangganId}',
          );
      final mutasi = [for (final m in (json as Map)['riwayat'] as List) Map<String, dynamic>.from(m as Map)];
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text('Riwayat deposit ${s.nama}', style: AppTypography.cardTitle),
                const SizedBox(height: AppSpacing.sm),
                for (final m in mutasi)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(switch (m['jenis']) {
                      'topup' => 'Top-up',
                      'pakai' => 'Pakai',
                      _ => 'Koreksi',
                    }),
                    subtitle: Text([
                      (m['dibuat'] as String).substring(0, 10),
                      if ((m['catatan'] as String?) != null) m['catatan'] as String,
                    ].join(' - ')),
                    trailing: Text(
                      '${m['jenis'] == 'topup' ? '+' : '-'}${_rp(double.parse('${m['jumlah']}').round())}',
                      key: Key('deposit.mutasi.${m['id']}'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  String _rp(int n) => 'Rp ${formatRupiahDigits(n)}';

  @override
  Widget build(BuildContext context) {
    ref.watch(pelangganAktifProvider); // tetap hidup supaya daftar pelanggan siap saat dialog dibuka
    return Scaffold(
      appBar: AppBar(title: const Text('Deposit pelanggan')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('deposit.catat'),
        onPressed: _catat,
        icon: const Icon(Icons.add),
        label: const Text('Catat deposit'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(icon: Icons.cloud_off_outlined, message: _error!)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, 96),
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pendapatan diterima di muka', style: AppTypography.secondary),
                          Text(_rp(_total), key: const Key('deposit.total'), style: AppTypography.cardTitle),
                          Text('${_saldo.length} pelanggan punya saldo', style: AppTypography.secondary),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (_saldo.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.xl),
                        child: Text('Belum ada saldo deposit. Tekan "Catat deposit" untuk top-up.'),
                      ),
                    for (final s in _saldo)
                      ListTile(
                        key: Key('deposit.baris.${s.pelangganId}'),
                        title: Text(s.nama),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_rp(s.saldo), style: AppTypography.cardTitle),
                            IconButton(
                              key: Key('deposit.riwayat.${s.pelangganId}'),
                              tooltip: 'Riwayat',
                              onPressed: () => _riwayat(s),
                              icon: const Icon(Icons.history),
                            ),
                          ],
                        ),
                        onTap: () => _catat(pelangganId: s.pelangganId),
                      ),
                  ],
                ),
    );
  }
}

class _CatatDepositDialog extends StatefulWidget {
  const _CatatDepositDialog({required this.pelanggan, this.awalId});

  final List<(String, String)> pelanggan;
  final String? awalId;

  @override
  State<_CatatDepositDialog> createState() => _CatatDepositDialogState();
}

class _CatatDepositDialogState extends State<_CatatDepositDialog> {
  late String _pelangganId =
      widget.pelanggan.any((p) => p.$1 == widget.awalId) ? widget.awalId! : widget.pelanggan.first.$1;
  String _jenis = 'topup';
  final _jumlah = TextEditingController();
  final _catatan = TextEditingController();
  String? _salah;

  @override
  void dispose() {
    _jumlah.dispose();
    _catatan.dispose();
    super.dispose();
  }

  void _simpan() {
    final jumlah = parseRupiahInput(_jumlah.text);
    if (jumlah == null || jumlah <= 0) {
      setState(() => _salah = 'Jumlah wajib diisi');
      return;
    }
    if (_jenis == 'koreksi' && _catatan.text.trim().isEmpty) {
      setState(() => _salah = 'Koreksi wajib diberi catatan');
      return;
    }
    Navigator.pop(context, {
      'pelanggan_id': _pelangganId,
      'jenis': _jenis,
      'jumlah': '$jumlah',
      if (_catatan.text.trim().isNotEmpty) 'catatan': _catatan.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catat deposit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('deposit.pelanggan'),
              initialValue: _pelangganId,
              isExpanded: true,
              items: [for (final p in widget.pelanggan) DropdownMenuItem(value: p.$1, child: Text(p.$2))],
              onChanged: (v) => setState(() => _pelangganId = v ?? _pelangganId),
              decoration: const InputDecoration(labelText: 'Pelanggan'),
            ),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<String>(
              key: const Key('deposit.jenis'),
              segments: const [
                ButtonSegment(value: 'topup', label: Text('Top-up')),
                ButtonSegment(value: 'pakai', label: Text('Pakai')),
                ButtonSegment(value: 'koreksi', label: Text('Koreksi')),
              ],
              selected: {_jenis},
              onSelectionChanged: (s) => setState(() => _jenis = s.first),
            ),
            TextField(
              key: const Key('deposit.jumlah'),
              controller: _jumlah,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, RupiahInputFormatter()],
              decoration: const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
            ),
            TextField(controller: _catatan, decoration: const InputDecoration(labelText: 'Catatan')),
            if (_salah != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_salah!, key: const Key('deposit.salah'), style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(key: const Key('deposit.simpan'), onPressed: _simpan, child: const Text('Simpan')),
      ],
    );
  }
}
