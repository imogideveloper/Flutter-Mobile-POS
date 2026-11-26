import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/auto_sync.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../produk/domain/produk.dart';
import '../../../produk/presentation/providers/produk_providers.dart';

/// Pembelian ke pemasok dan hutang pemasok (IMOGI no. 71, versi sederhana untuk UMKM): catat pembelian, terima barang
/// (stok bertambah dan HPP ikut harga beli terakhir, dihitung server), lalu tandai lunas. Pembelian yang sudah diterima
/// tetapi belum lunas adalah utang ke pemasok. Butuh internet.
final _uang = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

int _rp(Object? v) => double.parse(v.toString()).round();

class Pemasok {
  const Pemasok({required this.id, required this.nama});
  final String id;
  final String nama;
}

class PembelianRingkas {
  const PembelianRingkas({
    required this.id,
    required this.nomor,
    required this.tanggal,
    required this.status,
    required this.statusBayar,
    required this.total,
    required this.pemasokId,
    required this.items,
  });

  factory PembelianRingkas.fromJson(Map<String, dynamic> j) => PembelianRingkas(
        id: j['id'] as String,
        nomor: j['nomor'] as String,
        tanggal: DateTime.parse(j['tanggal'] as String),
        status: j['status'] as String,
        statusBayar: j['status_bayar'] as String,
        total: _rp(j['total']),
        pemasokId: j['supplier_id'] as String?,
        items: [
          for (final i in j['items'] as List)
            '${(i as Map<String, dynamic>)['nama_produk']} ${double.parse(i['qty'].toString()).toStringAsFixed(0)} x '
                '${_uang.format(_rp(i['harga_satuan']))}',
        ],
      );

  final String id;
  final String nomor;
  final DateTime tanggal;
  final String status; // draft|dipesan|diterima|batal
  final String statusBayar; // belum|sebagian|lunas
  final int total;
  final String? pemasokId;
  final List<String> items;

  bool get diterima => status == 'diterima';
  bool get lunas => statusBayar == 'lunas';

  /// Utang ke pemasok: barang sudah diterima tetapi belum dibayar.
  bool get utang => diterima && !lunas;
}

/// Total utang ke pemasok dari daftar pembelian.
int totalUtangPemasok(Iterable<PembelianRingkas> daftar) =>
    daftar.where((p) => p.utang).fold(0, (a, p) => a + p.total);

class DataPembelian {
  const DataPembelian({required this.pembelian, required this.pemasok});
  final List<PembelianRingkas> pembelian;
  final List<Pemasok> pemasok;
}

Future<String> _token(Ref ref) async {
  final sesi = await ref.read(authSessionStoreProvider).muat();
  if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
  return sesi.accessToken;
}

final dataPembelianProvider = FutureProvider.autoDispose<DataPembelian>((ref) async {
  final api = ref.read(backendApiProvider);
  final token = await _token(ref);
  final pembelian = await api.getJson(accessToken: token, path: '/pembelian') as List;
  final pemasok = await api.getJson(accessToken: token, path: '/supplier') as List;
  final daftar = [for (final p in pembelian) PembelianRingkas.fromJson(p as Map<String, dynamic>)]
    ..sort((a, b) => b.tanggal.compareTo(a.tanggal));
  return DataPembelian(
    pembelian: daftar,
    pemasok: [
      for (final s in pemasok) Pemasok(id: (s as Map<String, dynamic>)['id'] as String, nama: s['nama'] as String),
    ],
  );
});

class PembelianPage extends ConsumerWidget {
  const PembelianPage({super.key});

  Future<void> _aksi(BuildContext context, WidgetRef ref, String path, String berhasil) async {
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
      await ref.read(backendApiProvider).postJson(accessToken: sesi.accessToken, path: path);
      ref.invalidate(dataPembelianProvider);
      // Stok dan HPP baru dari server ikut turun ke HP.
      picuSyncSetelahTransaksi(ref);
      if (context.mounted) showAppToast(context, message: berhasil, variant: ToastVariant.success);
    } on BackendException catch (e) {
      if (context.mounted) {
        showAppToast(context,
            message: e.tidakAdaKoneksi ? 'Butuh internet.' : e.message, variant: ToastVariant.danger);
      }
    }
  }

  void _detail(BuildContext context, WidgetRef ref, PembelianRingkas p, String namaPemasok) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${p.nomor} · $namaPemasok', style: AppTypography.bodyEmphasis),
            Text(_tanggal.format(p.tanggal), style: AppTypography.secondary),
            const SizedBox(height: AppSpacing.md),
            for (final i in p.items) Text(i, style: AppTypography.body),
            const SizedBox(height: AppSpacing.sm),
            Text('Total ${_uang.format(p.total)}', style: AppTypography.bodyEmphasis),
            const SizedBox(height: AppSpacing.lg),
            if (!p.diterima)
              FilledButton(
                key: const Key('pembelian.terima'),
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_aksi(context, ref, '/pembelian/${p.id}/terima', 'Barang diterima, stok bertambah'));
                },
                child: const Text('Barang sudah diterima'),
              ),
            if (!p.lunas) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                key: const Key('pembelian.lunas'),
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(_aksi(context, ref, '/pembelian/${p.id}/lunas', 'Pembelian ditandai lunas'));
                },
                child: const Text('Tandai lunas (sudah dibayar)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dataPembelianProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pembelian & pemasok')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('pembelian.tambah'),
        onPressed: () async {
          final simpan = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => PembelianFormPage(pemasok: data.value?.pemasok ?? const [])),
          );
          if (simpan == true) ref.invalidate(dataPembelianProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('Catat pembelian'),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              e is BackendException && e.tidakAdaKoneksi ? 'Butuh internet untuk memuat pembelian.' : 'Gagal memuat: $e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (d) {
          final namaPemasok = {for (final s in d.pemasok) s.id: s.nama};
          final utang = d.pembelian.where((p) => p.utang).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 96),
            children: [
              AppCard(
                key: const Key('pembelian.utang'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Utang ke pemasok', style: AppTypography.secondary),
                    Text(_uang.format(totalUtangPemasok(d.pembelian)), style: AppTypography.totalPrice),
                    Text(
                      utang.isEmpty ? 'Semua pembelian sudah lunas' : '${utang.length} pembelian belum dibayar',
                      style: AppTypography.secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (d.pembelian.isEmpty)
                const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  message: 'Belum ada pembelian. Tekan "Catat pembelian" saat belanja ke pemasok.',
                )
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final p in d.pembelian)
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                          key: Key('pembelian.baris.${p.id}'),
                          title: Text('${p.nomor} · ${namaPemasok[p.pemasokId] ?? 'Tanpa pemasok'}'),
                          subtitle: Text(
                            '${_tanggal.format(p.tanggal)} · ${p.diterima ? 'Diterima' : 'Belum diterima'} · '
                            '${p.lunas ? 'Lunas' : 'Belum dibayar'}',
                            style: AppTypography.secondary.copyWith(
                              color: p.utang ? AppColors.warningTextStrong : null,
                            ),
                          ),
                          trailing: Text(_uang.format(p.total), style: AppTypography.bodyEmphasis),
                          onTap: () => _detail(context, ref, p, namaPemasok[p.pemasokId] ?? 'Tanpa pemasok'),
                        ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BarisBeli {
  _BarisBeli({required this.produk, required this.qty, required this.harga});
  final Produk produk;
  final double qty;
  final int harga;
  int get subtotal => (qty * harga).round();
}

/// Form catat pembelian: pemasok (pilih atau tambah baru), daftar barang, dan status barang/pembayaran.
class PembelianFormPage extends ConsumerStatefulWidget {
  const PembelianFormPage({super.key, required this.pemasok});

  final List<Pemasok> pemasok;

  @override
  ConsumerState<PembelianFormPage> createState() => _PembelianFormPageState();
}

class _PembelianFormPageState extends ConsumerState<PembelianFormPage> {
  late final List<Pemasok> _pemasok = [...widget.pemasok];
  String? _pemasokId;
  final _baris = <_BarisBeli>[];
  bool _diterima = true;
  bool _dibayar = true;
  bool _menyimpan = false;

  int get _total => _baris.fold(0, (a, b) => a + b.subtotal);

  Future<String> _token() async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
    return sesi.accessToken;
  }

  Future<void> _tambahPemasok() async {
    final nama = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pemasok baru'),
        content: TextField(
          key: const Key('pembelian.namaPemasok'),
          controller: nama,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama pemasok'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || nama.text.trim().isEmpty) return;
    try {
      final hasil = await ref.read(backendApiProvider).postJson(
            accessToken: await _token(),
            path: '/supplier',
            body: {'nama': nama.text.trim()},
          ) as Map<String, dynamic>;
      setState(() {
        _pemasok.add(Pemasok(id: hasil['id'] as String, nama: hasil['nama'] as String));
        _pemasokId = hasil['id'] as String;
      });
    } on BackendException catch (e) {
      if (mounted) showAppToast(context, message: e.message, variant: ToastVariant.danger);
    }
  }

  Future<void> _tambahBarang(List<Produk> produk) async {
    if (produk.isEmpty) return;
    Produk dipilih = produk.first;
    final qty = TextEditingController(text: '1');
    final harga = TextEditingController(text: formatRupiahDigits(dipilih.hpp));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Tambah barang'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Produk>(
                key: const Key('pembelian.produk'),
                initialValue: dipilih,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Barang'),
                items: [for (final p in produk) DropdownMenuItem(value: p, child: Text(p.nama))],
                onChanged: (p) => setDialog(() {
                  dipilih = p ?? dipilih;
                  harga.text = formatRupiahDigits(dipilih.hpp);
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('pembelian.qty'),
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Jumlah'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('pembelian.harga'),
                controller: harga,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, RupiahInputFormatter()],
                decoration: const InputDecoration(labelText: 'Harga beli per satuan', prefixText: 'Rp '),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(
              key: const Key('pembelian.simpanBarang'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tambah'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = double.tryParse(qty.text.replaceAll(',', '.')) ?? 0;
    final h = parseRupiahInput(harga.text) ?? 0;
    if (q <= 0) {
      if (mounted) showAppToast(context, message: 'Jumlah harus lebih dari 0', variant: ToastVariant.warning);
      return;
    }
    setState(() => _baris.add(_BarisBeli(produk: dipilih, qty: q, harga: h)));
  }

  Future<void> _simpan() async {
    if (_baris.isEmpty) {
      showAppToast(context, message: 'Tambahkan minimal satu barang', variant: ToastVariant.warning);
      return;
    }
    setState(() => _menyimpan = true);
    try {
      final api = ref.read(backendApiProvider);
      final token = await _token();
      final sekarang = DateTime.now();
      final dibuat = await api.postJson(
        accessToken: token,
        path: '/pembelian',
        body: {
          'outlet_id': ref.read(currentOutletIdProvider),
          'supplier_id': ?_pemasokId,
          'nomor': 'PB-${DateFormat('yyMMdd-HHmmss').format(sekarang)}',
          'tanggal': DateFormat('yyyy-MM-dd').format(sekarang),
          'items': [
            for (final b in _baris) {'produk_id': b.produk.id, 'qty': b.qty.toString(), 'harga_satuan': '${b.harga}'},
          ],
        },
      ) as Map<String, dynamic>;
      final id = dibuat['id'] as String;
      if (_diterima) await api.postJson(accessToken: token, path: '/pembelian/$id/terima');
      if (_dibayar) await api.postJson(accessToken: token, path: '/pembelian/$id/lunas');
      picuSyncSetelahTransaksi(ref);
      if (mounted) Navigator.of(context).pop(true);
    } on BackendException catch (e) {
      if (mounted) {
        showAppToast(context,
            message: e.tidakAdaKoneksi ? 'Butuh internet untuk mencatat pembelian.' : e.message,
            variant: ToastVariant.danger);
      }
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final produk = ref.watch(produkAktifProvider).value ?? const <Produk>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Catat pembelian')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: const Key('pembelian.pemasok'),
                  initialValue: _pemasokId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Pemasok'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tanpa pemasok')),
                    for (final s in _pemasok) DropdownMenuItem<String?>(value: s.id, child: Text(s.nama)),
                  ],
                  onChanged: (v) => setState(() => _pemasokId = v),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                key: const Key('pembelian.tambahPemasok'),
                tooltip: 'Pemasok baru',
                onPressed: _tambahPemasok,
                icon: const Icon(Icons.person_add_alt_outlined),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Barang dibeli', style: AppTypography.bodyEmphasis),
                for (var i = 0; i < _baris.length; i++)
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_baris[i].produk.nama),
                    subtitle: Text(
                      '${_baris[i].qty.toStringAsFixed(_baris[i].qty % 1 == 0 ? 0 : 2)} x ${_uang.format(_baris[i].harga)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_uang.format(_baris[i].subtotal)),
                        IconButton(
                          tooltip: 'Hapus',
                          onPressed: () => setState(() => _baris.removeAt(i)),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('pembelian.tambahBarang'),
                  onPressed: produk.isEmpty ? null : () => _tambahBarang(produk),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah barang'),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('Total ${_uang.format(_total)}', style: AppTypography.bodyEmphasis, textAlign: TextAlign.end),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            key: const Key('pembelian.diterima'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Barang sudah diterima'),
            subtitle: const Text('Stok bertambah dan harga beli dipakai sebagai HPP'),
            value: _diterima,
            onChanged: (v) => setState(() => _diterima = v),
          ),
          SwitchListTile(
            key: const Key('pembelian.dibayar'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Sudah dibayar'),
            subtitle: const Text('Matikan bila dibayar belakangan (jadi utang ke pemasok)'),
            value: _dibayar,
            onChanged: (v) => setState(() => _dibayar = v),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('pembelian.simpan'),
            onPressed: _menyimpan ? null : _simpan,
            child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan pembelian'),
          ),
        ],
      ),
    );
  }
}
