import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/laba_rugi.dart' show isoDenganOffset;
import '../../domain/pengeluaran.dart';
import '../../domain/rekap_pajak.dart';

enum _Tab { pajak, pph }

/// Rekap pajak (IMOGI no. 73 PPN/PB1 dan no. 70 PPh Final UMKM). Dihitung server dari transaksi
/// selesai; hanya rekap/estimasi untuk pencatatan, BUKAN pelaporan SPT. Butuh internet.
class RekapPajakPage extends ConsumerStatefulWidget {
  const RekapPajakPage({super.key});

  @override
  ConsumerState<RekapPajakPage> createState() => _RekapPajakPageState();
}

class _RekapPajakPageState extends ConsumerState<RekapPajakPage> {
  _Tab _tab = _Tab.pajak;
  RentangPengeluaran _rentang = RentangPengeluaran.bulanIni;
  RekapPajak? _rekap;
  PphFinal? _pph;
  String? _error;
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final sesi = await ref.read(authSessionStoreProvider).muat();
      if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
      final (dari, sampai) = _rentang.tanggal(DateTime.now());
      final api = ref.read(backendApiProvider);
      final awal = isoDenganOffset(dari);
      // [sampai] eksklusif: awal hari berikutnya.
      final akhir = isoDenganOffset(DateTime(sampai.year, sampai.month, sampai.day + 1));
      if (_tab == _Tab.pajak) {
        _rekap = RekapPajak.dariJson(
            await api.laporanRekapPajak(accessToken: sesi.accessToken, dari: awal, sampai: akhir));
      } else {
        _pph = PphFinal.dariJson(await api.laporanPphFinal(accessToken: sesi.accessToken, dari: awal, sampai: akhir));
      }
    } on BackendException catch (e) {
      _error = e.tidakAdaKoneksi
          ? 'Butuh internet untuk melihat laporan.'
          : (e.statusCode == 403 ? 'Fitur ini belum tersedia di paket Anda atau peran Anda tidak berizin.' : e.message);
    } catch (e) {
      _error = 'Gagal memuat: $e';
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rekap pajak')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, 0),
            child: SegmentedButton<_Tab>(
              key: const Key('rekapPajak.tab'),
              segments: const [
                ButtonSegment(value: _Tab.pajak, label: Text('PPN / PB1')),
                ButtonSegment(value: _Tab.pph, label: Text('PPh Final')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) {
                setState(() => _tab = s.first);
                _muat();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final r in RentangPengeluaran.values)
                  ChoiceChip(
                    key: Key('rekapPajak.rentang.${r.name}'),
                    label: Text(r.label),
                    selected: _rentang == r,
                    onSelected: (_) {
                      setState(() => _rentang = r);
                      _muat();
                    },
                  ),
              ],
            ),
          ),
          Expanded(child: _isi()),
        ],
      ),
    );
  }

  Widget _isi() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, key: const Key('rekapPajak.error'), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: _muat, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    return _tab == _Tab.pajak ? _tampilPajak(_rekap) : _tampilPph(_pph);
  }

  String _rp(int n) => 'Rp ${formatRupiahDigits(n)}';

  Widget _tampilPajak(RekapPajak? r) {
    if (r == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pajak dipungut', style: AppTypography.secondary),
              Text(_rp(r.totalPajak),
                  key: const Key('rekapPajak.totalPajak'), style: AppTypography.headerTitle.copyWith(fontSize: 22)),
              const SizedBox(height: AppSpacing.xs),
              Text('Service dipungut: ${_rp(r.totalService)}', key: const Key('rekapPajak.totalService')),
              Text('${r.jumlahTransaksi} transaksi', style: AppTypography.secondary),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (r.baris.isEmpty)
          Text('Belum ada pajak atau service dipungut pada rentang ini.', style: AppTypography.secondary)
        else
          for (final b in r.baris)
            ListTile(
              key: Key('rekapPajak.baris.${b.nama}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${b.nama} ${b.persen % 1 == 0 ? b.persen.toInt() : b.persen}%'),
              subtitle: Text('${b.jumlahTransaksi} transaksi${b.service ? ' · service' : ''}'),
              trailing: Text(_rp(b.total), style: AppTypography.bodyEmphasis),
            ),
        const SizedBox(height: AppSpacing.md),
        Text('Hanya rekap untuk pencatatan, bukan pelaporan pajak resmi.', style: AppTypography.secondary),
      ],
    );
  }

  Widget _tampilPph(PphFinal? p) {
    if (p == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Estimasi PPh Final (${p.tarifPersen}%)', style: AppTypography.secondary),
              Text(_rp(p.pphTerutang),
                  key: const Key('rekapPajak.pph'), style: AppTypography.headerTitle.copyWith(fontSize: 22)),
              const SizedBox(height: AppSpacing.xs),
              Text('Peredaran bruto: ${_rp(p.omzet)}', key: const Key('rekapPajak.omzet')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final b in p.perBulan)
          ListTile(
            key: Key('rekapPajak.bulan.${b.bulan}'),
            contentPadding: EdgeInsets.zero,
            title: Text(b.bulan),
            subtitle: Text('Omzet ${_rp(b.omzet)}'),
            trailing: Text(_rp(b.pph), style: AppTypography.bodyEmphasis),
          ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Perkiraan sederhana: tarif x peredaran bruto (penjualan sebelum pajak). Ambang peredaran yang '
          'dibebaskan dan status wajib pajak belum dihitung. Konsultasikan dengan konsultan pajak.',
          key: const Key('rekapPajak.catatan'),
          style: AppTypography.secondary,
        ),
      ],
    );
  }
}
