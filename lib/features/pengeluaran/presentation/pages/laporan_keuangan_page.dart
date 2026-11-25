import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import 'settlement_page.dart' show tanggalIso;

/// Laporan keuangan sederhana standar UMKM (IMOGI no. 81; arahan lead 2026-11-25): laba rugi per akun, arus kas,
/// dan posisi keuangan (neraca) ringkas per hari ini. Disusun server dari data yang tercatat; butuh internet.
class BarisAkunLk {
  const BarisAkunLk({required this.kode, required this.nama, required this.jumlah});

  factory BarisAkunLk.fromJson(Map<String, dynamic> j) => BarisAkunLk(
        kode: j['kode_akun'] as String? ?? '',
        nama: (j['nama'] ?? j['keterangan']) as String,
        jumlah: double.parse(j['jumlah'].toString()).round(),
      );

  final String kode;
  final String nama;
  final int jumlah;
}

int _rp(Object? v) => double.parse(v.toString()).round();

List<BarisAkunLk> _daftar(Object? v) => [for (final b in v as List) BarisAkunLk.fromJson(b as Map<String, dynamic>)];

final _uang = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

final laporanKeuanganProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, DateTime>((ref, bulan) async {
  final sesi = await ref.read(authSessionStoreProvider).muat();
  if (sesi == null) throw const BackendException(message: 'Perangkat belum terhubung ke server');
  final akhirBulan = DateTime(bulan.year, bulan.month + 1, 0);
  final hariIni = DateTime.now();
  final sampai = akhirBulan.isAfter(hariIni) ? hariIni : akhirBulan;
  final json = await ref.read(backendApiProvider).getJson(
    accessToken: sesi.accessToken,
    path: '/laporan-keuangan',
    query: {'dari': tanggalIso(bulan), 'sampai': tanggalIso(sampai)},
  );
  return json as Map<String, dynamic>;
});

class LaporanKeuanganPage extends ConsumerStatefulWidget {
  const LaporanKeuanganPage({super.key});

  @override
  ConsumerState<LaporanKeuanganPage> createState() => _LaporanKeuanganPageState();
}

class _LaporanKeuanganPageState extends ConsumerState<LaporanKeuanganPage> {
  DateTime _bulan = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(laporanKeuanganProvider(_bulan));
    final bulanIni = DateTime(DateTime.now().year, DateTime.now().month);
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan keuangan')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('laporanKeuangan.bulanSebelumnya'),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _bulan = DateTime(_bulan.year, _bulan.month - 1)),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy', 'id_ID').format(_bulan),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyEmphasis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _bulan == bulanIni ? null : () => setState(() => _bulan = DateTime(_bulan.year, _bulan.month + 1)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...data.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [
              Text(
                e is BackendException && e.tidakAdaKoneksi ? 'Butuh internet untuk memuat laporan keuangan.' : 'Gagal memuat: $e',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: () => ref.invalidate(laporanKeuanganProvider(_bulan)), child: const Text('Coba lagi')),
            ],
            data: _isi,
          ),
        ],
      ),
    );
  }

  List<Widget> _isi(Map<String, dynamic> d) {
    final lr = d['laba_rugi'] as Map<String, dynamic>;
    final ak = d['arus_kas'] as Map<String, dynamic>;
    final pos = d['posisi'] as Map<String, dynamic>;
    return [
      _Bagian(
        judul: 'Laba rugi',
        kunci: 'laporanKeuangan.labaRugi',
        isi: [
          ..._daftar(lr['pendapatan']).map(_BarisUang.new),
          _BarisUang.total('Total pendapatan', _rp(lr['total_pendapatan'])),
          ..._daftar(lr['hpp']).map(_BarisUang.new),
          _BarisUang.total('Laba kotor', _rp(lr['laba_kotor'])),
          ..._daftar(lr['beban']).map(_BarisUang.new),
          _BarisUang.total('Total beban', _rp(lr['total_beban'])),
          _BarisUang.total('Laba bersih', _rp(lr['laba_bersih'])),
        ],
      ),
      _Bagian(
        judul: 'Arus kas',
        kunci: 'laporanKeuangan.arusKas',
        isi: [
          ..._daftar(ak['masuk']).map(_BarisUang.new),
          _BarisUang.total('Total kas masuk', _rp(ak['total_masuk'])),
          ..._daftar(ak['keluar']).map(_BarisUang.new),
          _BarisUang.total('Total kas keluar', _rp(ak['total_keluar'])),
          _BarisUang.total('Kenaikan (penurunan) kas', _rp(ak['kenaikan_kas'])),
        ],
      ),
      _Bagian(
        judul: 'Posisi keuangan per hari ini',
        kunci: 'laporanKeuangan.posisi',
        isi: [
          ..._daftar(pos['aset']).map(_BarisUang.new),
          _BarisUang.total('Total aset', _rp(pos['total_aset'])),
          ..._daftar(pos['kewajiban']).map(_BarisUang.new),
          _BarisUang.total('Total kewajiban', _rp(pos['total_kewajiban'])),
          _BarisUang.total('Modal & laba (aset - kewajiban)', _rp(pos['ekuitas'])),
        ],
      ),
      Text(
        'Disusun dari data yang dicatat di aplikasi. Kas di neraca adalah akumulasi uang masuk dan keluar yang '
        'tercatat sejak mulai memakai aplikasi; saldo awal, setoran modal, dan prive pemilik belum tercatat. '
        'Utang pajak belum dihitung karena setoran pajak belum dicatat.',
        style: AppTypography.secondary,
      ),
    ];
  }
}

class _Bagian extends StatelessWidget {
  const _Bagian({required this.judul, required this.kunci, required this.isi});

  final String judul;
  final String kunci;
  final List<Widget> isi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(judul, style: AppTypography.bodyEmphasis),
          const SizedBox(height: AppSpacing.sm),
          AppCard(key: Key(kunci), child: Column(children: isi)),
        ],
      ),
    );
  }
}

class _BarisUang extends StatelessWidget {
  _BarisUang(BarisAkunLk b)
      : label = b.kode.isEmpty ? b.nama : '${b.kode} ${b.nama}',
        jumlah = b.jumlah,
        tebal = false;

  const _BarisUang.total(this.label, this.jumlah) : tebal = true;

  final String label;
  final int jumlah;
  final bool tebal;

  @override
  Widget build(BuildContext context) {
    final gaya = tebal ? AppTypography.bodyEmphasis : AppTypography.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: gaya)),
          const SizedBox(width: AppSpacing.md),
          Text(_uang.format(jumlah), style: gaya),
        ],
      ),
    );
  }
}
