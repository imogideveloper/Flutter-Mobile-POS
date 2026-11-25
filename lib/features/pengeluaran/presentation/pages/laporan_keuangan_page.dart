import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import 'settlement_page.dart' show tanggalIso;

/// Laporan keuangan sederhana standar UMKM (IMOGI no. 81; arahan lead 2026-11-25: ikut susunan laporan keuangan
/// standar tetapi mudah dibaca pemilik UMKM). Susunan mengikuti SAK EMKM: Laporan Laba Rugi, Laporan Posisi Keuangan
/// (neraca), ditambah Arus Kas sederhana dan Catatan. Angka disusun server dari data yang tercatat; butuh internet.
/// Kode akun tidak ditampilkan; nama akun diganti bahasa sehari-hari bila perlu.
class BarisAkunLk {
  const BarisAkunLk({required this.kode, required this.nama, required this.jumlah});

  factory BarisAkunLk.fromJson(Map<String, dynamic> j) {
    final kode = j['kode_akun'] as String? ?? '';
    return BarisAkunLk(
      kode: kode,
      nama: namaMudahAkun[kode] ?? (j['nama'] ?? j['keterangan']) as String,
      jumlah: double.parse(j['jumlah'].toString()).round(),
    );
  }

  final String kode;
  final String nama;
  final int jumlah;
}

/// Nama akun dalam bahasa sehari-hari untuk pemilik UMKM (kode akun dari bagan akun standar server).
const namaMudahAkun = <String, String>{
  '4-1000': 'Penjualan',
  '4-2000': 'Potongan harga (diskon)',
  '4-9000': 'Pendapatan lain',
  '5-1000': 'Bahan baku yang terjual',
  '5-1100': 'Kemasan',
  '6-1000': 'Gaji karyawan',
  '6-1100': 'Sewa tempat',
  '6-1200': 'Listrik & air',
  '6-1300': 'Gas LPG',
  '6-1400': 'Promosi & pemasaran',
  '6-1500': 'Perawatan & perbaikan',
  '6-1600': 'Penyusutan peralatan',
  '6-1700': 'Biaya admin bank',
  '6-9000': 'Biaya lain-lain',
  '1-1100': 'Kas & saldo bank',
  '1-1200': 'Kas & saldo bank',
  '1-1300': 'Piutang pelanggan (kasbon)',
  '1-1400': 'Stok barang & bahan',
  '1-1500': 'Stok kemasan',
  '1-1600': 'Biaya dibayar di muka',
  '1-2100': 'Peralatan usaha',
  '1-2200': 'Dikurangi penyusutan',
  '2-1100': 'Utang ke pemasok',
  '2-1200': 'Utang pajak',
  '2-1300': 'Deposit pelanggan (titipan)',
  '2-1400': 'Gaji belum dibayar',
};

int _rp(Object? v) => double.parse(v.toString()).round();

List<BarisAkunLk> _daftar(Object? v) => [for (final b in v as List) BarisAkunLk.fromJson(b as Map<String, dynamic>)];

/// Baris arus kas: belanja bahan di sini adalah uang yang dibayarkan, bukan bahan yang terjual.
List<BarisAkunLk> _daftarArus(Object? v) => [
      for (final b in _daftar(v))
        b.kode == '5-1000' ? BarisAkunLk(kode: b.kode, nama: 'Belanja bahan baku', jumlah: b.jumlah) : b,
    ];

final _uang = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

/// Rupiah dengan tanda minus di depan (mis. -Rp5.000), lebih mudah dibaca daripada tanda kurung akuntansi.
String formatRupiahLk(int n) => n < 0 ? '-${_uang.format(-n)}' : _uang.format(n);

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
            data: (d) => _isi(d, DateFormat('MMMM yyyy', 'id_ID').format(_bulan)),
          ),
        ],
      ),
    );
  }

  List<Widget> _isi(Map<String, dynamic> d, String namaBulan) {
    final lr = d['laba_rugi'] as Map<String, dynamic>;
    final ak = d['arus_kas'] as Map<String, dynamic>;
    final pos = d['posisi'] as Map<String, dynamic>;

    final labaBersih = _rp(lr['laba_bersih']);
    final kenaikanKas = _rp(ak['kenaikan_kas']);
    final aset = _daftar(pos['aset']);
    final asetLancar = aset.where((b) => b.kode.startsWith('1-1')).toList();
    final asetTetap = aset.where((b) => b.kode.startsWith('1-2')).toList();
    final totalAset = _rp(pos['total_aset']);
    final totalKewajiban = _rp(pos['total_kewajiban']);
    final ekuitas = _rp(pos['ekuitas']);
    final tglPosisi = DateFormat('d MMMM yyyy', 'id_ID').format(DateTime.parse(pos['per_tanggal'] as String));

    return [
      // Ringkasan dalam kalimat biasa, sebelum tabel.
      AppCard(
        key: const Key('laporanKeuangan.ringkasan'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ringkasan $namaBulan', style: AppTypography.bodyEmphasis),
            const SizedBox(height: AppSpacing.sm),
            _Kalimat(
              labaBersih >= 0 ? 'Usaha untung' : 'Usaha rugi',
              labaBersih.abs(),
              positif: labaBersih >= 0,
            ),
            _Kalimat(
              kenaikanKas >= 0 ? 'Uang kas bertambah' : 'Uang kas berkurang',
              kenaikanKas.abs(),
              positif: kenaikanKas >= 0,
            ),
            _Kalimat('Nilai usaha (modal & laba) per $tglPosisi', ekuitas, positif: ekuitas >= 0),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      _Laporan(
        kunci: 'laporanKeuangan.labaRugi',
        judul: 'Laporan Laba Rugi',
        keterangan: 'Untung atau rugi selama $namaBulan: penjualan dikurangi modal bahan dan biaya.',
        isi: [
          const _Subjudul('Pendapatan'),
          ..._daftar(lr['pendapatan']).map(_BarisUang.biasa),
          _BarisUang.subtotal('Total pendapatan', _rp(lr['total_pendapatan'])),
          const _Subjudul('Harga pokok penjualan'),
          ..._daftar(lr['hpp']).map(_BarisUang.biasa),
          _BarisUang.subtotal('Laba kotor', _rp(lr['laba_kotor'])),
          const _Subjudul('Biaya usaha'),
          ..._daftar(lr['beban']).map(_BarisUang.biasa),
          _BarisUang.subtotal('Total biaya usaha', _rp(lr['total_beban'])),
          _BarisUang.akhir(labaBersih >= 0 ? 'Laba bersih' : 'Rugi bersih', labaBersih),
        ],
      ),
      _Laporan(
        kunci: 'laporanKeuangan.posisi',
        judul: 'Laporan Posisi Keuangan (Neraca)',
        keterangan: 'Apa yang dimiliki usaha dan apa yang masih harus dibayar, per $tglPosisi.',
        isi: [
          const _Subjudul('Aset lancar'),
          ...asetLancar.map(_BarisUang.biasa),
          if (asetTetap.isNotEmpty) ...[
            const _Subjudul('Aset tetap'),
            ...asetTetap.map(_BarisUang.biasa),
          ],
          _BarisUang.subtotal('Total aset', totalAset),
          const _Subjudul('Kewajiban'),
          ..._daftar(pos['kewajiban']).map(_BarisUang.biasa),
          _BarisUang.subtotal('Total kewajiban', totalKewajiban),
          const _Subjudul('Modal'),
          _BarisUang.biasa(BarisAkunLk(kode: '3-1000', nama: 'Modal pemilik & laba usaha', jumlah: ekuitas)),
          _BarisUang.akhir('Total kewajiban + modal', totalKewajiban + ekuitas),
        ],
      ),
      _Laporan(
        kunci: 'laporanKeuangan.arusKas',
        judul: 'Laporan Arus Kas',
        keterangan: 'Uang yang benar-benar masuk dan keluar selama $namaBulan (termasuk kasbon yang baru dilunasi).',
        isi: [
          const _Subjudul('Uang masuk'),
          ..._daftarArus(ak['masuk']).map(_BarisUang.biasa),
          _BarisUang.subtotal('Total uang masuk', _rp(ak['total_masuk'])),
          const _Subjudul('Uang keluar'),
          ..._daftarArus(ak['keluar']).map(_BarisUang.biasa),
          _BarisUang.subtotal('Total uang keluar', _rp(ak['total_keluar'])),
          _BarisUang.akhir(kenaikanKas >= 0 ? 'Kas bertambah' : 'Kas berkurang', kenaikanKas),
        ],
      ),
      Text('Catatan', style: AppTypography.bodyEmphasis),
      const SizedBox(height: AppSpacing.xs),
      Text(
        '1. Laporan disusun otomatis dari penjualan, pengeluaran, stok, aset, dan deposit yang dicatat di aplikasi.\n'
        '2. Kas & saldo bank dihitung dari uang masuk dan keluar sejak mulai memakai aplikasi; saldo sebelumnya, '
        'setoran modal, dan uang yang diambil pemilik belum tercatat.\n'
        '3. Belanja bahan tidak dihitung lagi sebagai biaya karena nilainya sudah masuk "Bahan baku yang terjual".\n'
        '4. Utang pajak belum dihitung karena setoran pajak belum dicatat.',
        key: const Key('laporanKeuangan.catatan'),
        style: AppTypography.secondary,
      ),
    ];
  }
}

class _Kalimat extends StatelessWidget {
  const _Kalimat(this.label, this.jumlah, {required this.positif});

  final String label;
  final int jumlah;
  final bool positif;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.body)),
          Text(
            formatRupiahLk(jumlah),
            style: AppTypography.bodyEmphasis.copyWith(color: positif ? AppColors.primary : AppColors.dangerText),
          ),
        ],
      ),
    );
  }
}

class _Laporan extends StatelessWidget {
  const _Laporan({required this.kunci, required this.judul, required this.keterangan, required this.isi});

  final String kunci;
  final String judul;
  final String keterangan;
  final List<Widget> isi;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(judul, style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(keterangan, style: AppTypography.secondary),
          const SizedBox(height: AppSpacing.sm),
          AppCard(key: Key(kunci), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: isi)),
        ],
      ),
    );
  }
}

class _Subjudul extends StatelessWidget {
  const _Subjudul(this.teks);

  final String teks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
      child: Text(teks.toUpperCase(), style: AppTypography.labelUppercase),
    );
  }
}

enum _Gaya { biasa, subtotal, akhir }

class _BarisUang extends StatelessWidget {
  _BarisUang.biasa(BarisAkunLk b)
      : label = b.nama,
        jumlah = b.jumlah,
        gaya = _Gaya.biasa;

  const _BarisUang.subtotal(this.label, this.jumlah) : gaya = _Gaya.subtotal;

  const _BarisUang.akhir(this.label, this.jumlah) : gaya = _Gaya.akhir;

  final String label;
  final int jumlah;
  final _Gaya gaya;

  @override
  Widget build(BuildContext context) {
    final teks = gaya == _Gaya.biasa ? AppTypography.body : AppTypography.bodyEmphasis;
    final warnaAngka = jumlah < 0 ? AppColors.dangerText : null;
    final baris = Padding(
      padding: EdgeInsets.only(
        left: gaya == _Gaya.biasa ? AppSpacing.md : 0,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: teks)),
          const SizedBox(width: AppSpacing.md),
          Text(formatRupiahLk(jumlah), style: teks.copyWith(color: warnaAngka)),
        ],
      ),
    );
    if (gaya == _Gaya.biasa) return baris;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: BoxDecoration(
        color: gaya == _Gaya.akhir ? AppColors.primaryTint : null,
        border: const Border(top: BorderSide(color: AppColors.borderDefault)),
      ),
      padding: gaya == _Gaya.akhir ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm) : EdgeInsets.zero,
      child: baris,
    );
  }
}
