import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/providers/izin_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../absensi/domain/absensi_data.dart' show offsetZonaMenit;
import '../../domain/jadwal_data.dart';

/// Jadwal shift mingguan dan pengajuan cuti/sakit/izin (IMOGI no. 63). Langsung ke server (butuh
/// internet). Pengelola (izin laporan.lihat) mengatur jadwal semua karyawan dan memutuskan pengajuan;
/// peran lain melihat jadwalnya sendiri dan mengajukan cuti.
class JadwalCutiPage extends ConsumerStatefulWidget {
  const JadwalCutiPage({super.key});

  @override
  ConsumerState<JadwalCutiPage> createState() => _JadwalCutiPageState();
}

class _JadwalCutiPageState extends ConsumerState<JadwalCutiPage> {
  List<JadwalKaryawan> _jadwal = const [];
  List<PengajuanCutiItem> _cuti = const [];
  JadwalHariIni? _hariIni;
  String? _penggunaIdSaya;
  String? _error;
  bool _memuat = true;
  bool _sibuk = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<SesiBackend> _sesi() async {
    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
    return sesi;
  }

  String _pesan(BackendException e) {
    if (e.tidakAdaKoneksi) return 'Butuh internet untuk jadwal dan cuti.';
    if (e.statusCode == 403) return 'Fitur ini belum tersedia di paket Anda atau peran Anda tidak berizin.';
    return e.message;
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final sesi = await _sesi();
      final api = ref.read(backendApiProvider);
      final jadwal = await api.daftarJadwal(accessToken: sesi.accessToken);
      final cuti = await api.daftarCuti(accessToken: sesi.accessToken);
      final saya = await api.jadwalSaya(accessToken: sesi.accessToken, tzMenit: offsetZonaMenit(DateTime.now()));
      _penggunaIdSaya = sesi.penggunaId;
      _jadwal = [for (final j in jadwal) JadwalKaryawan.dariJson(j as Map<String, dynamic>)];
      _cuti = [for (final c in cuti) PengajuanCutiItem.dariJson(c as Map<String, dynamic>)];
      _hariIni = JadwalHariIni.dariJson(saya['hari_ini'] as Map<String, dynamic>);
    } on BackendException catch (e) {
      _error = _pesan(e);
    } catch (e) {
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  void _toast(String pesan, {ToastVariant variant = ToastVariant.success}) {
    if (mounted) showAppToast(context, message: pesan, variant: variant);
  }

  Future<void> _jalankan(Future<void> Function(SesiBackend sesi) aksi, {String? sukses}) async {
    setState(() => _sibuk = true);
    try {
      await aksi(await _sesi());
      if (sukses != null) _toast(sukses);
      await _muat();
    } on BackendException catch (e) {
      _toast(_pesan(e), variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Future<void> _aturJadwal(JadwalKaryawan k) async {
    final pilihan = await showModalBottomSheet<Map<int, String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SheetJadwal(karyawan: k),
    );
    if (pilihan == null) return;
    await _jalankan(
      (sesi) => ref.read(backendApiProvider).aturJadwal(
            accessToken: sesi.accessToken,
            penggunaId: k.penggunaId,
            hari: badanJadwal(pilihan),
          ).then((_) {}),
      sukses: 'Jadwal ${k.nama} disimpan',
    );
  }

  Future<void> _ajukan() async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SheetCuti(),
    );
    if (body == null) return;
    await _jalankan(
      (sesi) => ref.read(backendApiProvider).ajukanCuti(accessToken: sesi.accessToken, body: body).then((_) {}),
      sukses: 'Pengajuan terkirim',
    );
  }

  @override
  Widget build(BuildContext context) {
    final kelola = ref.watch(izinSayaProvider).value?.contains('laporan.lihat') ?? false;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Jadwal & cuti'),
          bottom: const TabBar(tabs: [Tab(key: Key('jadwal.tabJadwal'), text: 'Jadwal'), Tab(key: Key('jadwal.tabCuti'), text: 'Cuti')]),
        ),
        body: _memuat && _hariIni == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, key: const Key('jadwal.error'), textAlign: TextAlign.center),
                          const SizedBox(height: AppSpacing.md),
                          OutlinedButton(onPressed: _muat, child: const Text('Coba lagi')),
                        ],
                      ),
                    ),
                  )
                : TabBarView(children: [_tabJadwal(kelola), _tabCuti(kelola)]),
      ),
    );
  }

  Widget _tabJadwal(bool kelola) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AppCard(
          child: Text(_hariIni?.teks ?? '', key: const Key('jadwal.hariIni'), style: AppTypography.cardTitle),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_jadwal.isEmpty) Text('Belum ada karyawan.', style: AppTypography.secondary),
        for (final k in _jadwal)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              key: Key('jadwal.karyawan.${k.penggunaId}'),
              child: InkWell(
                onTap: kelola && !_sibuk ? () => _aturJadwal(k) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(k.nama, style: AppTypography.bodyEmphasis)),
                        if (kelola) const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (var h = 1; h <= 7; h++)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${namaHariSingkat[h]} ${labelShift(k.shiftPada(h))}', style: const TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (kelola) Text('Ketuk karyawan untuk mengatur jadwalnya.', style: AppTypography.secondary),
      ],
    );
  }

  Widget _tabCuti(bool kelola) {
    final menunggu = _cuti.where((c) => c.menunggu).length;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        FilledButton.icon(
          key: const Key('jadwal.ajukan'),
          icon: const Icon(Icons.event_busy_outlined, size: 18),
          label: const Text('Ajukan cuti / sakit / izin'),
          onPressed: _sibuk ? null : _ajukan,
        ),
        const SizedBox(height: AppSpacing.md),
        if (kelola) Text('$menunggu pengajuan menunggu keputusan', key: const Key('jadwal.menunggu'), style: AppTypography.secondary),
        if (_cuti.isEmpty) Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: Text('Belum ada pengajuan.', style: AppTypography.secondary)),
        for (final c in _cuti) _kartuCuti(c, kelola),
      ],
    );
  }

  Widget _kartuCuti(PengajuanCutiItem c, bool kelola) {
    final milikSaya = c.penggunaId == _penggunaIdSaya;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: AppCard(
        key: Key('jadwal.cuti.${c.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('${c.penggunaNama} · ${labelJenisCuti(c.jenis)}', style: AppTypography.bodyEmphasis)),
                Text(labelStatusCuti(c.status),
                    key: Key('jadwal.status.${c.id}'),
                    style: AppTypography.secondary.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.status == 'disetujui'
                          ? AppColors.primaryDark
                          : (c.status == 'ditolak' ? AppColors.dangerText : AppColors.textSecondary),
                    )),
              ],
            ),
            Text('${c.rentangTeks} (${c.jumlahHari} hari)', style: AppTypography.secondary),
            if (c.alasan != null && c.alasan!.isNotEmpty) Text(c.alasan!, style: AppTypography.secondary),
            if (c.catatanKeputusan != null && c.catatanKeputusan!.isNotEmpty)
              Text('Catatan: ${c.catatanKeputusan}', style: AppTypography.secondary),
            if (c.menunggu && (milikSaya || (kelola && !milikSaya))) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  if (milikSaya)
                    OutlinedButton(
                      key: Key('jadwal.batalkan.${c.id}'),
                      onPressed: _sibuk
                          ? null
                          : () => _jalankan(
                                (sesi) => ref.read(backendApiProvider).batalkanCuti(accessToken: sesi.accessToken, cutiId: c.id).then((_) {}),
                                sukses: 'Pengajuan dibatalkan',
                              ),
                      child: const Text('Batalkan'),
                    )
                  else ...[
                    FilledButton(
                      key: Key('jadwal.setuju.${c.id}'),
                      onPressed: _sibuk ? null : () => _putuskan(c, true),
                      child: const Text('Setujui'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton(
                      key: Key('jadwal.tolak.${c.id}'),
                      onPressed: _sibuk ? null : () => _putuskan(c, false),
                      child: const Text('Tolak'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _putuskan(PengajuanCutiItem c, bool setuju) => _jalankan(
        (sesi) => ref
            .read(backendApiProvider)
            .putuskanCuti(accessToken: sesi.accessToken, cutiId: c.id, setuju: setuju)
            .then((_) {}),
        sukses: setuju ? 'Pengajuan disetujui' : 'Pengajuan ditolak',
      );
}

/// Atur shift tujuh hari satu karyawan. Jam memakai bawaan shift (pagi 07:00-15:00, siang 14:00-22:00).
class _SheetJadwal extends StatefulWidget {
  const _SheetJadwal({required this.karyawan});

  final JadwalKaryawan karyawan;

  @override
  State<_SheetJadwal> createState() => _SheetJadwalState();
}

class _SheetJadwalState extends State<_SheetJadwal> {
  late final Map<int, String> _pilihan = {
    for (var h = 1; h <= 7; h++) h: widget.karyawan.shiftPada(h) ?? 'libur',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Jadwal ${widget.karyawan.nama}', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.sm),
            for (var h = 1; h <= 7; h++)
              Row(
                children: [
                  Expanded(child: Text(namaHariLengkap[h]!)),
                  DropdownButton<String>(
                    key: Key('jadwalForm.hari.$h'),
                    value: _pilihan[h],
                    items: [for (final s in kodeShift) DropdownMenuItem(value: s, child: Text(labelShift(s)))],
                    onChanged: (v) => setState(() => _pilihan[h] = v ?? 'libur'),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.sm),
            Text('Pagi 07:00-15:00, Siang 14:00-22:00. Terlambat dihitung 10 menit setelah jam mulai.', style: AppTypography.secondary),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: const Key('jadwalForm.simpan'),
              onPressed: () => Navigator.pop(context, Map<int, String>.of(_pilihan)),
              child: const Text('Simpan jadwal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetCuti extends StatefulWidget {
  const _SheetCuti();

  @override
  State<_SheetCuti> createState() => _SheetCutiState();
}

class _SheetCutiState extends State<_SheetCuti> {
  String _jenis = 'cuti';
  DateTime _mulai = DateTime.now().add(const Duration(days: 1));
  DateTime _selesai = DateTime.now().add(const Duration(days: 1));
  final _alasan = TextEditingController();

  @override
  void dispose() {
    _alasan.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggal({required bool mulai}) async {
    final awal = mulai ? _mulai : _selesai;
    final pilih = await showDatePicker(
      context: context,
      initialDate: awal,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pilih == null) return;
    setState(() {
      if (mulai) {
        _mulai = pilih;
        if (_selesai.isBefore(_mulai)) _selesai = _mulai;
      } else {
        _selesai = pilih.isBefore(_mulai) ? _mulai : pilih;
      }
    });
  }

  String _iso(DateTime t) => DateFormat('yyyy-MM-dd').format(t);

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('d MMM yyyy', 'id_ID');
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ajukan cuti / sakit / izin', style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('cutiForm.jenis'),
            initialValue: _jenis,
            decoration: const InputDecoration(labelText: 'Jenis'),
            items: [for (final j in const ['cuti', 'sakit', 'izin']) DropdownMenuItem(value: j, child: Text(labelJenisCuti(j)))],
            onChanged: (v) => setState(() => _jenis = v ?? 'cuti'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: OutlinedButton(key: const Key('cutiForm.mulai'), onPressed: () => _pilihTanggal(mulai: true), child: Text('Mulai: ${f.format(_mulai)}'))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: OutlinedButton(key: const Key('cutiForm.selesai'), onPressed: () => _pilihTanggal(mulai: false), child: Text('Selesai: ${f.format(_selesai)}'))),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('cutiForm.alasan'),
            controller: _alasan,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Alasan (opsional)', counterText: ''),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const Key('cutiForm.kirim'),
            onPressed: () => Navigator.pop(context, {
              'jenis': _jenis,
              'tanggal_mulai': _iso(_mulai),
              'tanggal_selesai': _iso(_selesai),
              if (_alasan.text.trim().isNotEmpty) 'alasan': _alasan.text.trim(),
            }),
            child: const Text('Kirim pengajuan'),
          ),
        ],
      ),
    );
  }
}
