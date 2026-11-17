import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/empty_state.dart';

/// Survei pelanggan (IMOGI no. 59). Butuh internet: survei dan jawabannya disimpan di server.
/// Pemilik membuat survei (pertanyaan rating 1-5, pilihan, atau teks), kasir mengisikan jawaban pelanggan,
/// pemilik melihat hasilnya.
class PertanyaanSurveiBaru {
  PertanyaanSurveiBaru({this.teks = '', this.tipe = 'rating', this.opsi = '', this.wajib = false});

  String teks;
  String tipe; // rating | pilihan | teks
  String opsi; // dipisah koma, hanya untuk tipe pilihan
  bool wajib;

  Map<String, dynamic> toJson() => {
        'teks': teks.trim(),
        'tipe': tipe,
        'wajib': wajib,
        if (tipe == 'pilihan')
          'opsi': [for (final o in opsi.split(',')) if (o.trim().isNotEmpty) o.trim()],
      };
}

/// Pesan kesalahan bila [daftar] belum layak dikirim; null bila layak.
String? validasiSurveiBaru(String judul, List<PertanyaanSurveiBaru> daftar) {
  if (judul.trim().isEmpty) return 'Judul survei wajib diisi';
  if (daftar.isEmpty) return 'Tambah minimal satu pertanyaan';
  for (final q in daftar) {
    if (q.teks.trim().isEmpty) return 'Teks pertanyaan wajib diisi';
    if (q.tipe == 'pilihan' && q.opsi.split(',').where((o) => o.trim().isNotEmpty).length < 2) {
      return 'Pertanyaan pilihan butuh minimal 2 opsi (pisahkan dengan koma)';
    }
  }
  return null;
}

Future<dynamic> _panggil(
  WidgetRef ref,
  Future<dynamic> Function(String token) aksi,
) async {
  final sesi = await ref.read(authSessionStoreProvider).muat();
  if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
  return aksi(sesi.accessToken);
}

String _pesanError(Object e) {
  if (e is BackendException) return e.tidakAdaKoneksi ? 'Butuh internet.' : e.message;
  return 'Gagal: $e';
}

final _surveiProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final sesi = await ref.read(authSessionStoreProvider).muat();
  if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
  final json = await ref.read(backendApiProvider).getJson(accessToken: sesi.accessToken, path: '/survei');
  return [for (final s in json as List) Map<String, dynamic>.from(s as Map)];
});

class SurveiPage extends ConsumerWidget {
  const SurveiPage({super.key});

  Future<void> _buat(BuildContext context, WidgetRef ref) async {
    final dibuat = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const BuatSurveiPage()));
    if (dibuat == true) ref.invalidate(_surveiProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_surveiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Survei pelanggan')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('survei.buat'),
        onPressed: () => _buat(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Buat survei'),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.cloud_off_outlined, message: _pesanError(e)),
        data: (daftar) => daftar.isEmpty
            ? const EmptyState(icon: Icons.poll_outlined, message: 'Belum ada survei')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [for (final s in daftar) _KartuSurvei(survei: s)],
              ),
      ),
    );
  }
}

class _KartuSurvei extends ConsumerWidget {
  const _KartuSurvei({required this.survei});

  final Map<String, dynamic> survei;

  Future<void> _ubahAktif(BuildContext context, WidgetRef ref, bool aktif) async {
    try {
      await _panggil(
        ref,
        (t) => ref.read(backendApiProvider).patchJson(accessToken: t, path: '/survei/${survei['id']}', body: {'aktif': aktif}),
      );
      ref.invalidate(_surveiProvider);
    } catch (e) {
      if (context.mounted) showAppToast(context, message: _pesanError(e), variant: ToastVariant.danger);
    }
  }

  Future<void> _hapus(BuildContext context, WidgetRef ref) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus survei?'),
        content: Text('"${survei['judul']}" tidak akan muncul lagi. Jawaban yang sudah masuk tetap tersimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ya != true) return;
    try {
      await _panggil(ref, (t) => ref.read(backendApiProvider).deleteJson(accessToken: t, path: '/survei/${survei['id']}'));
      ref.invalidate(_surveiProvider);
    } catch (e) {
      if (context.mounted) showAppToast(context, message: _pesanError(e), variant: ToastVariant.danger);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aktif = survei['aktif'] == true;
    final jumlah = (survei['pertanyaan'] as List).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${survei['judul']}', style: AppTypography.cardTitle)),
                Switch(
                  key: Key('survei.aktif.${survei['id']}'),
                  value: aktif,
                  onChanged: (v) => _ubahAktif(context, ref, v),
                ),
              ],
            ),
            Text('$jumlah pertanyaan${aktif ? '' : ' - nonaktif'}', style: AppTypography.secondary),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                FilledButton.tonal(
                  key: Key('survei.isi.${survei['id']}'),
                  onPressed: aktif
                      ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IsiSurveiPage(survei: survei)))
                      : null,
                  child: const Text('Isi jawaban'),
                ),
                OutlinedButton(
                  key: Key('survei.hasil.${survei['id']}'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => HasilSurveiPage(surveiId: '${survei['id']}', judul: '${survei['judul']}')),
                  ),
                  child: const Text('Hasil'),
                ),
                TextButton(onPressed: () => _hapus(context, ref), child: const Text('Hapus')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BuatSurveiPage extends ConsumerStatefulWidget {
  const BuatSurveiPage({super.key});

  @override
  ConsumerState<BuatSurveiPage> createState() => _BuatSurveiPageState();
}

class _BuatSurveiPageState extends ConsumerState<BuatSurveiPage> {
  final _judul = TextEditingController();
  final _daftar = <PertanyaanSurveiBaru>[PertanyaanSurveiBaru(teks: 'Seberapa puas Anda dengan layanan kami?')];
  bool _menyimpan = false;

  @override
  void dispose() {
    _judul.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    final salah = validasiSurveiBaru(_judul.text, _daftar);
    if (salah != null) {
      showAppToast(context, message: salah, variant: ToastVariant.warning);
      return;
    }
    setState(() => _menyimpan = true);
    try {
      await _panggil(
        ref,
        (t) => ref.read(backendApiProvider).postJson(
              accessToken: t,
              path: '/survei',
              body: {'judul': _judul.text.trim(), 'pertanyaan': [for (final q in _daftar) q.toJson()]},
            ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _menyimpan = false);
        showAppToast(context, message: _pesanError(e), variant: ToastVariant.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat survei')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          TextField(
            key: const Key('survei.judul'),
            controller: _judul,
            decoration: const InputDecoration(labelText: 'Judul survei'),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < _daftar.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      key: Key('survei.q$i.teks'),
                      initialValue: _daftar[i].teks,
                      onChanged: (v) => _daftar[i].teks = v,
                      decoration: InputDecoration(labelText: 'Pertanyaan ${i + 1}'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<String>(
                      key: Key('survei.q$i.tipe'),
                      segments: const [
                        ButtonSegment(value: 'rating', label: Text('Rating')),
                        ButtonSegment(value: 'pilihan', label: Text('Pilihan')),
                        ButtonSegment(value: 'teks', label: Text('Teks')),
                      ],
                      selected: {_daftar[i].tipe},
                      onSelectionChanged: (s) => setState(() => _daftar[i].tipe = s.first),
                    ),
                    if (_daftar[i].tipe == 'pilihan')
                      TextFormField(
                        key: Key('survei.q$i.opsi'),
                        initialValue: _daftar[i].opsi,
                        onChanged: (v) => _daftar[i].opsi = v,
                        decoration: const InputDecoration(labelText: 'Opsi (pisahkan dengan koma)'),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Wajib dijawab'),
                            value: _daftar[i].wajib,
                            onChanged: (v) => setState(() => _daftar[i].wajib = v == true),
                          ),
                        ),
                        if (_daftar.length > 1)
                          IconButton(
                            tooltip: 'Hapus pertanyaan',
                            onPressed: () => setState(() => _daftar.removeAt(i)),
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_daftar.length < 20)
            OutlinedButton.icon(
              key: const Key('survei.tambahPertanyaan'),
              onPressed: () => setState(() => _daftar.add(PertanyaanSurveiBaru())),
              icon: const Icon(Icons.add),
              label: const Text('Tambah pertanyaan'),
            ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const Key('survei.simpan'),
            onPressed: _menyimpan ? null : _simpan,
            child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan survei'),
          ),
        ],
      ),
    );
  }
}

class IsiSurveiPage extends ConsumerStatefulWidget {
  const IsiSurveiPage({super.key, required this.survei});

  final Map<String, dynamic> survei;

  @override
  ConsumerState<IsiSurveiPage> createState() => _IsiSurveiPageState();
}

class _IsiSurveiPageState extends ConsumerState<IsiSurveiPage> {
  final _angka = <String, int>{};
  final _teks = <String, String>{};
  bool _mengirim = false;

  List<Map<String, dynamic>> get _pertanyaan => [
        for (final q in widget.survei['pertanyaan'] as List) Map<String, dynamic>.from(q as Map),
      ];

  Future<void> _kirim() async {
    final jawaban = <Map<String, dynamic>>[];
    for (final q in _pertanyaan) {
      final id = q['id'] as String;
      if (q['tipe'] == 'rating') {
        if (_angka[id] != null) jawaban.add({'pertanyaan_id': id, 'nilai_angka': _angka[id]});
      } else if ((_teks[id] ?? '').trim().isNotEmpty) {
        jawaban.add({'pertanyaan_id': id, 'nilai_teks': _teks[id]!.trim()});
      }
      if (q['wajib'] == true && !jawaban.any((j) => j['pertanyaan_id'] == id)) {
        showAppToast(context, message: 'Pertanyaan wajib belum dijawab: ${q['teks']}', variant: ToastVariant.warning);
        return;
      }
    }
    if (jawaban.isEmpty) {
      showAppToast(context, message: 'Isi minimal satu jawaban', variant: ToastVariant.warning);
      return;
    }
    setState(() => _mengirim = true);
    try {
      await _panggil(
        ref,
        (t) => ref.read(backendApiProvider).postJson(
              accessToken: t,
              path: '/survei/${widget.survei['id']}/jawaban',
              body: {'jawaban': jawaban},
            ),
      );
      if (!mounted) return;
      showAppToast(context, message: 'Terima kasih, jawaban tersimpan', variant: ToastVariant.success);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _mengirim = false);
        showAppToast(context, message: _pesanError(e), variant: ToastVariant.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.survei['judul']}')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          for (final q in _pertanyaan)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${q['teks']}${q['wajib'] == true ? ' *' : ''}', style: AppTypography.cardTitle),
                  const SizedBox(height: AppSpacing.sm),
                  if (q['tipe'] == 'rating')
                    Row(
                      children: [
                        for (var n = 1; n <= 5; n++)
                          IconButton(
                            key: Key('survei.rating.${q['id']}.$n'),
                            onPressed: () => setState(() => _angka[q['id'] as String] = n),
                            icon: Icon(
                              (_angka[q['id']] ?? 0) >= n ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                            ),
                          ),
                      ],
                    )
                  else if (q['tipe'] == 'pilihan')
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        for (final o in (q['opsi'] as List).cast<String>())
                          ChoiceChip(
                            label: Text(o),
                            selected: _teks[q['id']] == o,
                            onSelected: (_) => setState(() => _teks[q['id'] as String] = o),
                          ),
                      ],
                    )
                  else
                    TextField(
                      key: Key('survei.teks.${q['id']}'),
                      onChanged: (v) => _teks[q['id'] as String] = v,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: 'Tulis jawaban'),
                    ),
                ],
              ),
            ),
          FilledButton(
            key: const Key('survei.kirim'),
            onPressed: _mengirim ? null : _kirim,
            child: Text(_mengirim ? 'Mengirim...' : 'Kirim jawaban'),
          ),
        ],
      ),
    );
  }
}

class HasilSurveiPage extends ConsumerStatefulWidget {
  const HasilSurveiPage({super.key, required this.surveiId, required this.judul});

  final String surveiId;
  final String judul;

  @override
  ConsumerState<HasilSurveiPage> createState() => _HasilSurveiPageState();
}

class _HasilSurveiPageState extends ConsumerState<HasilSurveiPage> {
  late final Future<Map<String, dynamic>> _hasil = _muat();

  Future<Map<String, dynamic>> _muat() async {
    final json = await _panggil(
      ref,
      (t) => ref.read(backendApiProvider).getJson(accessToken: t, path: '/survei/${widget.surveiId}/hasil'),
    );
    return Map<String, dynamic>.from(json as Map);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Hasil: ${widget.judul}')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _hasil,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return EmptyState(icon: Icons.cloud_off_outlined, message: _pesanError(snap.error!));
          final h = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              Text('${h['jumlah_responden']} responden', key: const Key('survei.responden'), style: AppTypography.cardTitle),
              const SizedBox(height: AppSpacing.md),
              for (final q in (h['pertanyaan'] as List).cast<Map>())
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${q['teks']}', style: AppTypography.cardTitle),
                        Text('${q['jumlah_jawaban']} jawaban', style: AppTypography.secondary),
                        const SizedBox(height: AppSpacing.sm),
                        if (q['tipe'] == 'rating' && q['rata_rata'] != null)
                          Text('Rata-rata ${q['rata_rata']} dari 5', key: const Key('survei.rataRata')),
                        if (q['tipe'] != 'teks')
                          for (final e in (q['sebaran'] as Map).entries) Text('${e.key}: ${e.value}'),
                        if (q['tipe'] == 'teks')
                          for (final k in (q['komentar'] as List)) Text('- $k'),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
