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
import '../../../../core/database/app_database.dart' show MetodeBayarRow;
import '../../../transaksi/data/local/tables/metode_bayar_table.dart';
import '../../../transaksi/presentation/providers/transaksi_providers.dart';

/// Satu baris rekonsiliasi (tanggal penjualan x metode): tercatat di POS, diterima di rekening, selisih.
class BarisRekonsiliasi {
  const BarisRekonsiliasi({
    required this.tanggal,
    required this.metodeBayarId,
    required this.metodeNama,
    required this.tercatat,
    required this.diterima,
    required this.biaya,
    required this.selisih,
    required this.status,
  });

  factory BarisRekonsiliasi.dariJson(Map<String, dynamic> j) => BarisRekonsiliasi(
        tanggal: j['tanggal'] as String,
        metodeBayarId: j['metode_bayar_id'] as String,
        metodeNama: j['metode_nama'] as String,
        tercatat: _int(j['tercatat']),
        diterima: _int(j['diterima']),
        biaya: _int(j['biaya']),
        selisih: _int(j['selisih']),
        status: j['status'] as String,
      );

  final String tanggal;
  final String metodeBayarId;
  final String metodeNama;
  final int tercatat;
  final int diterima;
  final int biaya;
  final int selisih;
  final String status; // cocok | selisih | belum_dicatat

  static int _int(Object? v) => double.parse('$v').round();
}

String tanggalIso(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// Settlement & rekonsiliasi QRIS/e-wallet (IMOGI no. 74). Butuh internet. Pemilik mencatat dana yang masuk
/// rekening, lalu membandingkannya dengan penjualan non-tunai di POS (7 hari terakhir).
class SettlementPage extends ConsumerStatefulWidget {
  const SettlementPage({super.key});

  @override
  ConsumerState<SettlementPage> createState() => _SettlementPageState();
}

class _SettlementPageState extends ConsumerState<SettlementPage> {
  List<BarisRekonsiliasi> _baris = const [];
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
      final sekarang = DateTime.now();
      final json = await ref.read(backendApiProvider).getJson(
        accessToken: await _token(),
        path: '/settlement/rekonsiliasi',
        query: {'dari': tanggalIso(sekarang.subtract(const Duration(days: 6))), 'sampai': tanggalIso(sekarang)},
      );
      _baris = [
        for (final b in (json as Map)['baris'] as List) BarisRekonsiliasi.dariJson(Map<String, dynamic>.from(b as Map)),
      ];
    } on BackendException catch (e) {
      _baris = const [];
      _error = e.tidakAdaKoneksi ? 'Butuh internet untuk melihat rekonsiliasi.' : e.message;
    } catch (e) {
      _baris = const [];
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _catat({BarisRekonsiliasi? untuk}) async {
    final metode = (ref.read(metodeBayarAktifProvider).value ?? const <MetodeBayarRow>[])
        .where((m) => m.tipe != MetodeBayarTipe.tunai)
        .toList();
    if (!mounted) return;
    if (metode.isEmpty) {
      showAppToast(context, message: 'Belum ada metode pembayaran non-tunai', variant: ToastVariant.warning);
      return;
    }
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CatatSettlementDialog(
        metode: [for (final m in metode) (m.id, m.nama)],
        awalMetodeId: untuk?.metodeBayarId,
        awalTanggal: untuk?.tanggal,
        awalJumlah: untuk?.tercatat,
      ),
    );
    if (hasil == null || !mounted) return;
    try {
      await ref.read(backendApiProvider).postJson(accessToken: await _token(), path: '/settlement', body: hasil);
      if (!mounted) return;
      showAppToast(context, message: 'Settlement dicatat', variant: ToastVariant.success);
      await _muat();
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  String _rp(int n) => '${n < 0 ? '-' : ''}Rp ${formatRupiahDigits(n.abs())}';

  @override
  Widget build(BuildContext context) {
    ref.watch(metodeBayarAktifProvider); // tetap hidup supaya daftar metode siap saat dialog dibuka
    return Scaffold(
      appBar: AppBar(title: const Text('Settlement QRIS & e-wallet')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('settlement.catat'),
        onPressed: _catat,
        icon: const Icon(Icons.add),
        label: const Text('Catat dana masuk'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(icon: Icons.cloud_off_outlined, message: _error!)
              : _baris.isEmpty
                  ? const EmptyState(
                      icon: Icons.account_balance_outlined,
                      message: 'Belum ada penjualan non-tunai dalam 7 hari terakhir',
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      children: [for (final b in _baris) _kartu(b)],
                    ),
    );
  }

  Widget _kartu(BarisRekonsiliasi b) {
    final (label, warna) = switch (b.status) {
      'cocok' => ('Cocok', AppColors.primary),
      'selisih' => ('Selisih ${_rp(b.selisih)}', AppColors.dangerText),
      _ => ('Belum dicatat', AppColors.warningText),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        key: Key('settlement.baris.${b.tanggal}.${b.metodeBayarId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${b.tanggal} - ${b.metodeNama}', style: AppTypography.cardTitle)),
                Text(label, style: TextStyle(color: warna, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Tercatat di POS: ${_rp(b.tercatat)}'),
            Text('Diterima: ${_rp(b.diterima)}   Biaya: ${_rp(b.biaya)}'),
            if (b.status != 'cocok')
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => _catat(untuk: b), child: const Text('Catat dana masuk')),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatatSettlementDialog extends StatefulWidget {
  const _CatatSettlementDialog({required this.metode, this.awalMetodeId, this.awalTanggal, this.awalJumlah});

  final List<(String, String)> metode;
  final String? awalMetodeId;
  final String? awalTanggal;
  final int? awalJumlah;

  @override
  State<_CatatSettlementDialog> createState() => _CatatSettlementDialogState();
}

class _CatatSettlementDialogState extends State<_CatatSettlementDialog> {
  late String _metodeId = widget.metode.any((m) => m.$1 == widget.awalMetodeId)
      ? widget.awalMetodeId!
      : widget.metode.first.$1;
  late DateTime _tanggal = widget.awalTanggal != null
      ? DateTime.parse(widget.awalTanggal!)
      : DateTime.now().subtract(const Duration(days: 1));
  late final _jumlah = TextEditingController(
    text: widget.awalJumlah == null ? '' : formatRupiahDigits(widget.awalJumlah!),
  );
  final _biaya = TextEditingController();
  final _referensi = TextEditingController();

  @override
  void dispose() {
    _jumlah.dispose();
    _biaya.dispose();
    _referensi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catat dana masuk'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('settlement.metode'),
              initialValue: _metodeId,
              items: [for (final m in widget.metode) DropdownMenuItem(value: m.$1, child: Text(m.$2))],
              onChanged: (v) => setState(() => _metodeId = v ?? _metodeId),
              decoration: const InputDecoration(labelText: 'Metode'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tanggal penjualan'),
              subtitle: Text(tanggalIso(_tanggal)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final t = await showDatePicker(
                  context: context,
                  initialDate: _tanggal,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (t != null) setState(() => _tanggal = t);
              },
            ),
            TextField(
              key: const Key('settlement.jumlah'),
              controller: _jumlah,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, RupiahInputFormatter()],
              decoration: const InputDecoration(labelText: 'Jumlah diterima (bersih)', prefixText: 'Rp '),
            ),
            TextField(
              key: const Key('settlement.biaya'),
              controller: _biaya,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, RupiahInputFormatter()],
              decoration: const InputDecoration(labelText: 'Biaya / potongan penyedia', prefixText: 'Rp '),
            ),
            TextField(
              controller: _referensi,
              decoration: const InputDecoration(labelText: 'Referensi (opsional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          key: const Key('settlement.simpan'),
          onPressed: () {
            final jumlah = parseRupiahInput(_jumlah.text);
            if (jumlah == null) return;
            Navigator.pop(context, {
              'metode_bayar_id': _metodeId,
              'tanggal': tanggalIso(_tanggal),
              'jumlah_diterima': '$jumlah',
              'biaya': '${parseRupiahInput(_biaya.text) ?? 0}',
              if (_referensi.text.trim().isNotEmpty) 'referensi': _referensi.text.trim(),
            });
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
