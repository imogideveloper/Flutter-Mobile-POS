import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/admin_data.dart';
import '../providers/admin_providers.dart';

final _formatTanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Dashboard Administrator: Ringkasan usaha, daftar Usaha, dan peta Fitur
/// (status pengembangan 87 fitur IMOGI), dengan filter jenis usaha F&B.
/// Hanya bisa dibuka setelah login administrator (lihat AdminLoginPage).
class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesi = ref.watch(adminSesiProvider);
    if (sesi == null) {
      // Tidak ada sesi admin (mis. dibuka langsung): arahkan ke login.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard Administrator'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(sesi.nama, style: AppTypography.secondary),
              ),
            ),
            IconButton(
              key: const Key('adminDashboard.keluar'),
              tooltip: 'Keluar',
              icon: const Icon(Icons.logout),
              onPressed: () {
                ref.read(adminSesiProvider.notifier).keluar();
                ref.read(adminJenisUsahaFilterProvider.notifier).pilih(null);
                context.go('/');
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Ringkasan'), Tab(text: 'Usaha'), Tab(text: 'Fitur')],
          ),
        ),
        body: Column(
          children: [
            const _FilterJenisUsaha(),
            const Expanded(
              child: TabBarView(children: [_TabRingkasan(), _TabUsaha(), _TabFitur()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterJenisUsaha extends ConsumerWidget {
  const _FilterJenisUsaha();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pilihan = ref.watch(adminJenisUsahaPilihanProvider).value ?? const <PilihanJenisUsaha>[];
    final aktif = ref.watch(adminJenisUsahaFilterProvider);
    return SizedBox(
      height: 52,
      child: ListView(
        key: const Key('adminDashboard.filter'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              key: const Key('adminDashboard.filter.semua'),
              label: const Text('Semua F&B'),
              selected: aktif == null,
              onSelected: (_) => ref.read(adminJenisUsahaFilterProvider.notifier).pilih(null),
            ),
          ),
          for (final p in pilihan)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                key: Key('adminDashboard.filter.${p.kode}'),
                label: Text(p.nama),
                selected: aktif == p.kode,
                onSelected: (_) => ref.read(adminJenisUsahaFilterProvider.notifier).pilih(p.kode),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _galat(Object error, VoidCallback ulangi) => Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Gagal memuat: $error', textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: ulangi, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );

class _KartuAngka extends StatelessWidget {
  const _KartuAngka({required this.label, required this.nilai, this.keyId});

  final String label;
  final String nilai;
  final String? keyId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: AppCard(
        key: keyId == null ? null : Key(keyId!),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.secondary),
            const SizedBox(height: AppSpacing.xs),
            Text(nilai, style: AppTypography.headerTitle),
          ],
        ),
      ),
    );
  }
}

class _TabRingkasan extends ConsumerWidget {
  const _TabRingkasan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminRingkasanProvider);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _galat(e, () => ref.invalidate(adminRingkasanProvider)),
      data: (r) {
        final trial = r.trial;
        return ListView(
          key: const Key('adminDashboard.ringkasan'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _KartuAngka(keyId: 'adminDashboard.totalUsaha', label: 'Usaha terdaftar', nilai: '${r.totalUsaha}'),
                _KartuAngka(label: 'Baru 30 hari', nilai: '${r.usahaBaru30Hari}'),
                _KartuAngka(keyId: 'adminDashboard.totalPengguna', label: 'Pengguna aktif', nilai: '${r.totalPengguna}'),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Paket yang dipakai', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Column(
                children: [
                  if (r.perPaket.isEmpty) Text('Belum ada usaha.', style: AppTypography.secondary),
                  for (final p in r.perPaket)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text(p.nama, style: AppTypography.body)),
                        Text('${p.jumlah} usaha', style: AppTypography.bodyEmphasis),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Jenis usaha', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Column(
                children: [
                  if (r.perJenisUsaha.isEmpty) Text('Belum ada usaha.', style: AppTypography.secondary),
                  for (final j in r.perJenisUsaha)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text(j.nama, style: AppTypography.body)),
                        Text('${j.jumlah}', style: AppTypography.bodyEmphasis),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Masa free trial', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              key: const Key('adminDashboard.trial'),
              child: !trial.diatur
                  ? Text('Masa trial belum diatur (usia akun 0 bulan).', style: AppTypography.secondary)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Batas trial ${trial.durasiBulan} bulan sejak usaha mendaftar', style: AppTypography.body),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                          AppBadge(label: 'Dalam trial: ${trial.dalamTrial}', variant: BadgeVariant.success),
                          AppBadge(
                            label: 'Hampir berakhir (≤${trial.batasNotifikasiHari} hari): ${trial.hampirBerakhir}',
                            variant: BadgeVariant.warning,
                          ),
                          AppBadge(label: 'Sudah berakhir: ${trial.berakhir}', variant: BadgeVariant.danger),
                        ]),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Kemajuan fitur', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.sm),
            _KartuKemajuanFitur(fitur: r.fitur),
          ],
        );
      },
    );
  }
}

class _KartuKemajuanFitur extends StatelessWidget {
  const _KartuKemajuanFitur({required this.fitur});

  final RingkasanFitur fitur;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const Key('adminDashboard.kemajuanFitur'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${fitur.sudah} dari ${fitur.relevan} fitur relevan sudah terpasang (${fitur.persenSelesai}%)',
              style: AppTypography.bodyEmphasis),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fitur.relevan == 0 ? 0 : fitur.sudah / fitur.relevan,
              minHeight: 10,
              color: AppColors.primary,
              backgroundColor: AppColors.borderDefault,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
            AppBadge(label: 'Sudah ${fitur.sudah}', variant: BadgeVariant.success),
            AppBadge(label: 'Sedang ${fitur.sedang}', variant: BadgeVariant.warning),
            AppBadge(label: 'Belum ${fitur.belum}', variant: BadgeVariant.danger),
            AppBadge(label: 'Tidak relevan ${fitur.tidakRelevan}'),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Lulus uji di HP: ${fitur.ujiHp} dari ${fitur.relevan}. "Sudah" berarti kode selesai dan lulus tes otomatis; '
            'belum ada yang dinyatakan Done sebelum diuji di HP.',
            style: AppTypography.secondary,
          ),
        ],
      ),
    );
  }
}

class _TabUsaha extends ConsumerWidget {
  const _TabUsaha();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminUsahaProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xs, AppSpacing.xl, AppSpacing.sm),
          child: TextField(
            key: const Key('adminDashboard.cariUsaha'),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari nama usaha, pemilik, atau email'),
            onSubmitted: (v) => ref.read(adminPencarianUsahaProvider.notifier).set(v),
          ),
        ),
        Expanded(
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _galat(e, () => ref.invalidate(adminUsahaProvider)),
            data: (daftar) {
              if (daftar.isEmpty) {
                return const EmptyState(icon: Icons.storefront_outlined, message: 'Tidak ada usaha untuk filter ini.');
              }
              return ListView.separated(
                key: const Key('adminDashboard.daftarUsaha'),
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
                itemCount: daftar.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) => _KartuUsaha(usaha: daftar[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _KartuUsaha extends StatelessWidget {
  const _KartuUsaha({required this.usaha});

  final UsahaAdmin usaha;

  @override
  Widget build(BuildContext context) {
    final trialLabel = usaha.trialAktif == null
        ? null
        : (usaha.trialAktif!
            ? 'Trial sampai ${_formatTanggal.format(usaha.trialBerakhir!)} (${usaha.trialHariTersisa} hari lagi)'
            : 'Trial berakhir ${_formatTanggal.format(usaha.trialBerakhir!)}');
    return AppCard(
      key: Key('adminDashboard.usaha.${usaha.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(usaha.nama, style: AppTypography.bodyEmphasis)),
            AppBadge(label: usaha.paket, variant: BadgeVariant.info),
          ]),
          Text(
            [if (usaha.jenisUsahaNama != null) usaha.jenisUsahaNama!, if (usaha.pemilikNama != null) usaha.pemilikNama!].join(' · '),
            style: AppTypography.secondary,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Terdaftar ${_formatTanggal.format(usaha.terdaftar)} (${usaha.usiaHari} hari) · '
            '${usaha.jumlahPengguna} pengguna · ${usaha.jumlahOutlet} outlet',
            style: AppTypography.body,
          ),
          Text('Langganan: ${usaha.paketLangganan} (${usaha.statusLangganan})', style: AppTypography.body),
          if (trialLabel != null) Text(trialLabel, style: AppTypography.body),
          if (usaha.email != null || usaha.noHp != null)
            Text([if (usaha.email != null) usaha.email!, if (usaha.noHp != null) usaha.noHp!].join(' · '),
                style: AppTypography.secondary),
          Text(
            usaha.terakhirSync == null ? 'Belum pernah sync' : 'Sync terakhir ${_formatTanggal.format(usaha.terakhirSync!)}',
            style: AppTypography.secondary,
          ),
        ],
      ),
    );
  }
}

class _TabFitur extends ConsumerStatefulWidget {
  const _TabFitur();

  @override
  ConsumerState<_TabFitur> createState() => _TabFiturState();
}

class _TabFiturState extends ConsumerState<_TabFitur> {
  StatusFitur? _status;

  BadgeVariant _varian(StatusFitur s) => switch (s) {
        StatusFitur.sudah => BadgeVariant.success,
        StatusFitur.sedang => BadgeVariant.warning,
        StatusFitur.belum => BadgeVariant.danger,
        StatusFitur.tidakRelevan => BadgeVariant.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(adminFiturProvider);
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _galat(e, () => ref.invalidate(adminFiturProvider)),
      data: (semua) {
        final moduls = kelompokkanPerModul(semua);
        return ListView(
          key: const Key('adminDashboard.fitur'),
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xs, AppSpacing.xl, AppSpacing.xl),
          children: [
            Wrap(spacing: AppSpacing.sm, children: [
              ChoiceChip(
                key: const Key('adminDashboard.statusSemua'),
                label: const Text('Semua status'),
                selected: _status == null,
                onSelected: (_) => setState(() => _status = null),
              ),
              for (final s in StatusFitur.values)
                ChoiceChip(
                  key: Key('adminDashboard.status.${s.kode}'),
                  label: Text(s.label),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
            ]),
            const SizedBox(height: AppSpacing.md),
            for (final m in moduls) _KartuModul(modul: m, saring: _status, varian: _varian),
          ],
        );
      },
    );
  }
}

class _KartuModul extends StatelessWidget {
  const _KartuModul({required this.modul, required this.saring, required this.varian});

  final RingkasanModul modul;
  final StatusFitur? saring;
  final BadgeVariant Function(StatusFitur) varian;

  @override
  Widget build(BuildContext context) {
    final tampil = modul.fitur.where((f) => saring == null || f.status == saring).toList();
    if (tampil.isEmpty) return const SizedBox.shrink();
    final relevan = modul.fitur.where((f) => f.status != StatusFitur.tidakRelevan).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: Key('adminDashboard.modul.${modul.modul}'),
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          // Key berubah menurut filter agar kartu dibangun ulang dan terbuka
          // otomatis saat pengguna menyaring status (initiallyExpanded hanya
          // dibaca saat tile dibuat).
          key: ValueKey('modul-${modul.modul}-${saring?.kode}'),
          initiallyExpanded: saring != null,
          shape: const Border(),
          title: Text(modul.modul, style: AppTypography.bodyEmphasis),
          subtitle: Text(
            modul.belumAda
                ? 'Belum ada fitur yang terpasang'
                : '${modul.hitung(StatusFitur.sudah)} sudah · ${modul.hitung(StatusFitur.sedang)} sedang · '
                    '${modul.hitung(StatusFitur.belum)} belum (dari $relevan relevan)',
            style: AppTypography.secondary.copyWith(color: modul.belumAda ? AppColors.dangerText : null),
          ),
          children: [
            for (final f in tampil)
              ListTile(
                key: Key('adminDashboard.fitur.${f.nomor}'),
                dense: true,
                title: Text('${f.nomor}. ${f.nama}', style: AppTypography.body),
                subtitle: f.catatan == null || f.catatan!.isEmpty
                    ? null
                    : Text(f.catatan!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppTypography.secondary),
                trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (f.kebutuhan != null && f.kebutuhan != 'na') AppBadge(label: f.kebutuhan!),
                  if (f.ujiHp) const Icon(Icons.phone_android, size: 16, color: AppColors.primary),
                  AppBadge(label: f.status.label, variant: varian(f.status)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
