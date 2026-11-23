import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/toko_profile_provider.dart';
import '../../../../core/struk/kirim_whatsapp_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/kirim_massal.dart';
import '../../domain/pelanggan.dart';
import '../providers/pelanggan_providers.dart';

/// Kirim WA ke banyak pelanggan (IMOGI no. 57). Kasir menulis satu pesan ({nama} dan {toko} diisi otomatis),
/// memilih penerima, lalu pesan dibuka di WhatsApp satu per satu dan dikirim kasir sendiri (tidak ada kirim
/// otomatis).
class KirimMassalPage extends ConsumerStatefulWidget {
  const KirimMassalPage({super.key});

  @override
  ConsumerState<KirimMassalPage> createState() => _KirimMassalPageState();
}

class _KirimMassalPageState extends ConsumerState<KirimMassalPage> {
  final _pesan = TextEditingController(text: 'Halo {nama}, ');
  final _cari = TextEditingController();
  final Set<String> _dipilih = {};
  String? _levelId;
  List<Pelanggan>? _antrian;
  int _indeks = 0;

  @override
  void dispose() {
    _pesan.dispose();
    _cari.dispose();
    super.dispose();
  }

  Future<void> _bukaSaatIni(String? namaToko) async {
    final antrian = _antrian!;
    final p = antrian[_indeks];
    await kirimStrukWhatsApp(
      noHpPelanggan: p.noHp,
      teks: isiPesanMassal(_pesan.text, namaPelanggan: p.nama, namaToko: namaToko),
    );
    if (mounted) setState(() => _indeks++);
  }

  @override
  Widget build(BuildContext context) {
    final semua = ref.watch(pelangganAktifProvider).value ?? const <Pelanggan>[];
    final levels = ref.watch(levelMemberProvider).value ?? const <LevelMember>[];
    final namaToko = ref.watch(tokoProfileProvider).value?.namaToko;
    final antrian = _antrian;

    return Scaffold(
      appBar: AppBar(title: const Text('Kirim WA ke pelanggan')),
      body: antrian != null ? _berjalan(antrian, namaToko) : _persiapan(semua, levels),
    );
  }

  Widget _berjalan(List<Pelanggan> antrian, String? namaToko) {
    if (_indeks >= antrian.length) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        message: 'Selesai: ${antrian.length} pesan sudah dibuka di WhatsApp.',
        action: FilledButton(
          key: const Key('kirimMassal.selesai'),
          onPressed: () => setState(() {
            _antrian = null;
            _indeks = 0;
          }),
          child: const Text('Kembali'),
        ),
      );
    }
    final p = antrian[_indeks];
    final teks = isiPesanMassal(_pesan.text, namaPelanggan: p.nama, namaToko: namaToko);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pesan ${_indeks + 1} dari ${antrian.length}', style: AppTypography.secondary),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nama, key: const Key('kirimMassal.penerima'), style: AppTypography.cardTitle),
                Text(p.noHp ?? '', style: AppTypography.secondary),
                const Divider(),
                Text(teks, key: const Key('kirimMassal.pratinjau')),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('kirimMassal.buka'),
              onPressed: () => unawaited(_bukaSaatIni(namaToko)),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Buka WhatsApp'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('kirimMassal.lewati'),
              onPressed: () => setState(() => _indeks++),
              child: const Text('Lewati'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Kirim pesannya di WhatsApp, lalu kembali ke sini untuk pelanggan berikutnya.',
            style: AppTypography.secondary,
          ),
        ],
      ),
    );
  }

  Widget _persiapan(List<Pelanggan> semua, List<LevelMember> levels) {
    final kandidat = kandidatPenerima(semua, levelMemberId: _levelId, kataCari: _cari.text);
    final dipilihAda = [for (final p in kandidat) if (_dipilih.contains(p.id)) p];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('kirimMassal.pesan'),
                controller: _pesan,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Pesan',
                  helperText: '{nama} diganti nama pelanggan, {toko} diganti nama usaha',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('kirimMassal.cari'),
                controller: _cari,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Cari pelanggan'),
              ),
              if (levels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      ChoiceChip(
                        key: const Key('kirimMassal.level.semua'),
                        label: const Text('Semua level'),
                        selected: _levelId == null,
                        onSelected: (_) => setState(() => _levelId = null),
                      ),
                      for (final l in levels)
                        ChoiceChip(
                          key: Key('kirimMassal.level.${l.id}'),
                          label: Text(l.nama),
                          selected: _levelId == l.id,
                          onSelected: (_) => setState(() => _levelId = l.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${kandidat.length} pelanggan punya nomor WhatsApp',
                  style: AppTypography.secondary,
                ),
              ),
              TextButton(
                key: const Key('kirimMassal.pilihSemua'),
                onPressed: () => setState(() {
                  final semuaTerpilih = dipilihAda.length == kandidat.length;
                  for (final p in kandidat) {
                    semuaTerpilih ? _dipilih.remove(p.id) : _dipilih.add(p.id);
                  }
                }),
                child: Text(dipilihAda.length == kandidat.length && kandidat.isNotEmpty ? 'Kosongkan' : 'Pilih semua'),
              ),
            ],
          ),
        ),
        Expanded(
          child: kandidat.isEmpty
              ? const EmptyState(
                  icon: Icons.people_outline,
                  message: 'Belum ada pelanggan dengan nomor WhatsApp',
                )
              : ListView(
                  children: [
                    for (final p in kandidat)
                      CheckboxListTile(
                        key: Key('kirimMassal.baris.${p.id}'),
                        value: _dipilih.contains(p.id),
                        title: Text(p.nama),
                        subtitle: Text(p.noHp ?? ''),
                        onChanged: (v) => setState(() => v == true ? _dipilih.add(p.id) : _dipilih.remove(p.id)),
                      ),
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('kirimMassal.mulai'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: dipilihAda.isEmpty || _pesan.text.trim().isEmpty
                    ? null
                    : () => setState(() {
                          _antrian = dipilihAda;
                          _indeks = 0;
                        }),
                child: Text('Mulai kirim (${dipilihAda.length})'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
