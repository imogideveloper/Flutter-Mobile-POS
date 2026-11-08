import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/avatar_initial.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/qty_dialog.dart';
import '../../../../core/widgets/qty_stepper.dart';
import '../../domain/item_keranjang.dart';
import '../../../order/domain/tipe_order.dart';
import '../../../order/presentation/providers/tipe_order_providers.dart';
import '../../../pelanggan/domain/pelanggan.dart';
import '../../../pelanggan/presentation/providers/pelanggan_providers.dart';
import '../../../pelanggan/presentation/widgets/pelanggan_picker_sheet.dart';
import '../../../promo/data/local/tables/promo_table.dart' show PromoTipe;
import '../../../promo/domain/promo.dart';
import '../../../promo/presentation/providers/promo_providers.dart';
import '../../../stok/presentation/providers/stok_providers.dart';
import '../providers/harga_keranjang_provider.dart';
import '../providers/keranjang_provider.dart';
import '../providers/transaksi_providers.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

String _labelPromo(Promo promo) {
  final nilai = promo.tipe == PromoTipe.persen
      ? '${promo.nilai.toStringAsFixed(promo.nilai.truncateToDouble() == promo.nilai ? 0 : 1)}%'
      : _formatRupiah.format(promo.nilai.round());
  return '${promo.nama} · $nilai';
}

class KeranjangPage extends ConsumerWidget {
  const KeranjangPage({super.key});

  // F3.E - "Simpan pesanan" tidak digate paket (selalu tersedia di semua
  // tier, beda dari pemilihan meja yang tetap digate fitur 'tipe_order' -
  // lihat FiturTerkunci di sekitar dropdown tipe order pada build() ini).
  Future<void> _simpanPesanan(BuildContext context, WidgetRef ref) async {
    final items = ref.read(keranjangProvider);
    if (items.isEmpty) return;
    final hasil = ref.read(hasilHargaKeranjangProvider);
    final draftSebelumnya = ref.read(draftPesananDibukaProvider);

    await ref.read(transaksiRepositoryProvider).simpanPesanan(
          tokoId: ref.read(currentTokoIdProvider),
          outletId: ref.read(currentOutletIdProvider),
          penggunaId: ref.read(currentPenggunaIdProvider) ?? '',
          items: items,
          hasil: hasil,
          draftIdSebelumnya: draftSebelumnya,
          pelangganId: ref.read(keranjangPelangganIdProvider),
          tipeOrderId: ref.read(keranjangTipeOrderIdProvider),
          catatan: ref.read(keranjangCatatanProvider),
        );
    ref.read(keranjangProvider.notifier).kosongkan();
    if (context.mounted) {
      showAppToast(context, message: 'Pesanan tersimpan', variant: ToastVariant.success);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keranjang = ref.watch(keranjangProvider);
    // SATU mesin hitung yang sama dgn checkout_service.py server (lihat
    // docs/aturan_harga.md) - subtotal/diskon member/diskon promo/
    // service/tiap pajak/pembulatan/total semua dari sini.
    final hasil = ref.watch(hasilHargaKeranjangProvider);
    final promo = ref.watch(keranjangPromoProvider);
    final pelangganId = ref.watch(keranjangPelangganIdProvider);
    final catatan = ref.watch(keranjangCatatanProvider);
    final tipeOrderId = ref.watch(keranjangTipeOrderIdProvider);
    final pelangganAktif = ref.watch(pelangganAktifProvider);
    final tipeOrderAktif = ref.watch(tipeOrderAktifProvider);

    final pelanggan = pelangganAktif.maybeWhen(
      data: (items) => items.where((p) => p.id == pelangganId).firstOrNull,
      orElse: () => null,
    );
    final tipeOrder = tipeOrderAktif.maybeWhen(
      data: (items) => items.where((t) => t.id == tipeOrderId).firstOrNull,
      orElse: () => null,
    );

    final poinDitukar = ref.watch(keranjangPoinDitukarProvider);
    final diskonPoin = ref.watch(diskonPoinKeranjangProvider);
    final total = ref.watch(totalSetelahPoinProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keranjang'),
        actions: [
          if (keranjang.isNotEmpty)
            TextButton(
              key: const Key('keranjangForm.simpanPesanan'),
              onPressed: () => _simpanPesanan(context, ref),
              child: const Text('Simpan pesanan'),
            ),
        ],
      ),
      body: keranjang.isEmpty
          ? const Center(child: Text('Keranjang kosong'))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                AppCard(
                  onTap: () => _pilihPelanggan(context, ref),
                  child: Row(
                    children: [
                      AvatarInitial.fromName(pelanggan?.nama ?? '?'),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pelanggan?.nama ?? 'Tanpa pelanggan',
                              style: AppTypography.bodyEmphasis,
                            ),
                            if (pelanggan != null)
                              Text('Member · ${pelanggan.poin} poin', style: AppTypography.secondary),
                          ],
                        ),
                      ),
                      Text(
                        pelanggan == null ? 'Pilih' : 'Ganti',
                        style: AppTypography.bodyEmphasis.copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < keranjang.length; i++)
                        _ItemRow(item: keranjang[i], showDivider: i < keranjang.length - 1),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _ChipButton(
                        label: promo == null ? 'Promo' : _labelPromo(promo),
                        selected: promo != null,
                        icon: Icons.local_offer_outlined,
                        onTap: () => _pilihPromo(context, ref),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _ChipButton(
                        label: catatan == null || catatan.isEmpty ? 'Catatan pesanan' : catatan,
                        selected: catatan != null && catatan.isNotEmpty,
                        icon: Icons.edit_note,
                        onTap: () => _editCatatan(context, ref, catatan),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                FiturTerkunci(
                  kode: 'tipe_order',
                  child: _ChipButton(
                    label: tipeOrder == null ? 'Tipe pesanan' : tipeOrder.nama,
                    selected: tipeOrder != null,
                    icon: Icons.storefront_outlined,
                    onTap: () => _pilihTipeOrder(context, ref),
                  ),
                ),
                // Tukar poin (modul 10) - cuma masuk akal kalau ada
                // pelanggan terpilih (poin melekat ke pelanggan).
                if (pelanggan != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  FiturTerkunci(
                    kode: 'poin_loyalitas',
                    child: _ChipButton(
                      label: poinDitukar > 0 ? 'Tukar $poinDitukar poin' : 'Tukar poin',
                      selected: poinDitukar > 0,
                      icon: Icons.redeem_outlined,
                      onTap: () => _pilihPoinDitukar(context, ref, pelanggan),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    children: [
                      _RincianRow(label: 'Subtotal (${keranjang.length} item)', value: hasil.subtotal),
                      if (hasil.diskonMember > 0)
                        _RincianRow(label: 'Diskon member', value: -hasil.diskonMember, color: AppColors.primaryDark),
                      if (hasil.diskonPromo > 0)
                        _RincianRow(
                          label: 'Promo ${promo?.nama ?? ''}',
                          value: -hasil.diskonPromo,
                          color: AppColors.primaryDark,
                        ),
                      for (final r in hasil.rincianService)
                        _RincianRow(label: '${r.nama} ${r.persen}%', value: r.jumlah),
                      for (final r in hasil.rincianPajak)
                        if (!r.termasukHarga) _RincianRow(label: '${r.nama} ${r.persen}%', value: r.jumlah),
                      if (hasil.pembulatan != 0)
                        _RincianRow(label: 'Pembulatan', value: hasil.pembulatan),
                      if (diskonPoin > 0)
                        _RincianRow(
                          label: 'Tukar $poinDitukar poin',
                          value: -diskonPoin,
                          color: AppColors.primaryDark,
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(_formatRupiah.format(total), style: AppTypography.totalPrice),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: keranjang.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
                child: SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: () => context.push('/kasir/bayar'),
                    child: Text('Bayar ${_formatRupiah.format(total)}'),
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _pilihPelanggan(BuildContext context, WidgetRef ref) async {
    final pelangganAktif = await ref.read(pelangganAktifProvider.future);
    if (!context.mounted) return;

    final dipilih = await showModalBottomSheet<Pelanggan?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PelangganPickerSheet(daftar: pelangganAktif),
    );
    ref.read(keranjangPelangganIdProvider.notifier).state = dipilih?.id;
    // Ganti/batal pelanggan - penukaran poin lama (kalau ada) sudah tidak
    // valid lagi (beda pelanggan = beda saldo poin), reset supaya tidak
    // ada diskon "nyangkut" dari pelanggan sebelumnya.
    ref.read(keranjangPoinDitukarProvider.notifier).state = 0;
  }

  Future<void> _pilihPromo(BuildContext context, WidgetRef ref) async {
    final promoAktif = await ref.read(promoAktifProvider.future);
    if (!context.mounted) return;

    final dipilih = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PromoPickerSheet(
        daftar: promoAktif,
        promoIdTerpilih: ref.read(keranjangPromoIdProvider),
      ),
    );
    ref.read(keranjangPromoIdProvider.notifier).state = dipilih;
  }

  Future<void> _pilihTipeOrder(BuildContext context, WidgetRef ref) async {
    final tipeOrderAktif = await ref.read(tipeOrderAktifProvider.future);
    if (!context.mounted) return;

    final dipilih = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TipeOrderPickerSheet(
        daftar: tipeOrderAktif,
        tipeOrderIdTerpilih: ref.read(keranjangTipeOrderIdProvider),
      ),
    );
    ref.read(keranjangTipeOrderIdProvider.notifier).state = dipilih;
  }

  Future<void> _pilihPoinDitukar(BuildContext context, WidgetRef ref, Pelanggan pelanggan) async {
    final aturan = await ref.read(aturanPoinProvider.future);
    if (!context.mounted) return;
    if (aturan == null || !aturan.aktif || aturan.nilaiTukarPoin <= 0) {
      showAppToast(
        context,
        message: 'Penukaran poin belum diaktifkan utk toko ini',
        variant: ToastVariant.warning,
      );
      return;
    }
    if (pelanggan.poin <= 0 || (aturan.minTukarPoin > 0 && pelanggan.poin < aturan.minTukarPoin)) {
      showAppToast(
        context,
        message: aturan.minTukarPoin > 0
            ? 'Poin pelanggan tidak cukup (min ${aturan.minTukarPoin} poin)'
            : 'Pelanggan ini belum punya poin',
        variant: ToastVariant.warning,
      );
      return;
    }

    final controller = TextEditingController(
      text: ref.read(keranjangPoinDitukarProvider) > 0
          ? ref.read(keranjangPoinDitukarProvider).toString()
          : '',
    );
    final poinDipilih = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tukar poin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo poin ${pelanggan.nama}: ${pelanggan.poin}'),
            Text('1 poin = ${_formatRupiah.format(aturan.nilaiTukarPoin)}'),
            if (aturan.minTukarPoin > 0) Text('Minimal tukar: ${aturan.minTukarPoin} poin'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('keranjangForm.poinDitukar'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jumlah poin ditukar'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(0),
            child: const Text('Batal tukar'),
          ),
          FilledButton(
            key: const Key('keranjangForm.terapkanPoin'),
            onPressed: () => Navigator.of(dialogContext).pop(int.tryParse(controller.text) ?? 0),
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
    if (poinDipilih == null) return;
    if (poinDipilih > pelanggan.poin) {
      if (context.mounted) {
        showAppToast(context, message: 'Poin tidak cukup (saldo ${pelanggan.poin})', variant: ToastVariant.warning);
      }
      return;
    }
    if (poinDipilih > 0 && aturan.minTukarPoin > 0 && poinDipilih < aturan.minTukarPoin) {
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Minimal tukar ${aturan.minTukarPoin} poin',
          variant: ToastVariant.warning,
        );
      }
      return;
    }
    ref.read(keranjangPoinDitukarProvider.notifier).state = poinDipilih;
  }

  Future<void> _editCatatan(BuildContext context, WidgetRef ref, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final hasil = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Catatan pesanan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Contoh: tanpa es, bungkus terpisah'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (hasil != null) {
      ref.read(keranjangCatatanProvider.notifier).state = hasil.isEmpty ? null : hasil;
    }
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.showDivider});

  final ItemKeranjang item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: showDivider
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.borderDefault)))
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.namaProduk, style: AppTypography.bodyEmphasis),
                if (item.modifiers.isNotEmpty)
                  Text(
                    item.modifiers.map((m) => m.harga > 0 ? '${m.nama} (+${_formatRupiah.format(m.harga)})' : m.nama).join(', '),
                    key: Key('keranjang.tambahan.${item.kunciBaris}'),
                    style: AppTypography.secondary,
                  ),
                Text(_formatRupiah.format(item.subtotal), style: AppTypography.bodyEmphasis),
              ],
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              // Bug nyata (stok tersisa 4, tetap bisa ditambah sampai 32)
              // - sama pola cek dgn kasir_page.dart::_tambahKeKeranjang,
              // satu sumber kebenaran "izinkan_stok_minus" per outlet.
              final outletId = ref.watch(currentOutletIdProvider);
              final izinkanStokMinus = ref
                  .watch(pengaturanOutletProvider(outletId))
                  .maybeWhen(data: (v) => v?.izinkanStokMinus ?? true, orElse: () => true);
              final stok = ref
                  .watch(stokOutletProvider(outletId))
                  .maybeWhen(data: (v) => v, orElse: () => const [])
                  .firstWhereOrNull((s) => s.produkId == item.produkId);

              return QtyStepper(
                qty: item.qty,
                onIncrement: () {
                  if (item.lacakStok && !izinkanStokMinus) {
                    final tersedia = stok?.jumlah ?? 0;
                    if (item.qty + 1 > tersedia) {
                      showAppToast(
                        context,
                        message: tersedia <= 0
                            ? 'Stok "${item.namaProduk}" habis'
                            : 'Stok "${item.namaProduk}" tidak cukup - sisa ${tersedia.toStringAsFixed(0)}',
                        variant: ToastVariant.warning,
                      );
                      return;
                    }
                  }
                  ref.read(keranjangProvider.notifier).ubahQty(item.kunciBaris, item.qty + 1);
                },
                onDecrement: () =>
                    ref.read(keranjangProvider.notifier).ubahQty(item.kunciBaris, item.qty - 1),
                onQtyTap: () async {
                  final hasil = await tampilkanIsiJumlah(context, judul: item.namaProduk, awal: item.qty);
                  if (hasil == null || !context.mounted) return;
                  if (hasil > 0 && item.lacakStok && !izinkanStokMinus) {
                    final tersedia = stok?.jumlah ?? 0;
                    if (hasil > tersedia) {
                      showAppToast(
                        context,
                        message: tersedia <= 0
                            ? 'Stok "${item.namaProduk}" habis'
                            : 'Stok "${item.namaProduk}" tidak cukup - sisa ${tersedia.toStringAsFixed(0)}',
                        variant: ToastVariant.warning,
                      );
                      return;
                    }
                  }
                  ref.read(keranjangProvider.notifier).ubahQty(item.kunciBaris, hasil);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryTint : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.primaryTintBorder : AppColors.borderDefault),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? AppColors.primaryDark : AppColors.textPrimary),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.secondary.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.primaryDark : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RincianRow extends StatelessWidget {
  const _RincianRow({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.secondary.copyWith(color: color ?? AppColors.textSecondary)),
          Text(
            '${value < 0 ? '-' : ''}${_formatRupiah.format(value.abs())}',
            style: AppTypography.secondary.copyWith(
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoPickerSheet extends StatelessWidget {
  const _PromoPickerSheet({required this.daftar, required this.promoIdTerpilih});

  final List<Promo> daftar;
  final String? promoIdTerpilih;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pilih promo', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.not_interested),
              title: const Text('Tanpa promo'),
              onTap: () => Navigator.of(context).pop(),
            ),
            if (daftar.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('Belum ada promo aktif', style: AppTypography.secondary),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: daftar.length,
                  itemBuilder: (context, index) {
                    final p = daftar[index];
                    final terpilih = p.id == promoIdTerpilih;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        terpilih ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: terpilih ? AppColors.primary : AppColors.textTertiary,
                      ),
                      title: Text(_labelPromo(p)),
                      onTap: () => Navigator.of(context).pop(p.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TipeOrderPickerSheet extends StatelessWidget {
  const _TipeOrderPickerSheet({required this.daftar, required this.tipeOrderIdTerpilih});

  final List<TipeOrder> daftar;
  final String? tipeOrderIdTerpilih;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pilih tipe pesanan', style: AppTypography.cardTitle),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.not_interested),
              title: const Text('Tanpa tipe pesanan'),
              onTap: () => Navigator.of(context).pop(),
            ),
            if (daftar.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('Belum ada tipe pesanan aktif', style: AppTypography.secondary),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: daftar.length,
                  itemBuilder: (context, index) {
                    final t = daftar[index];
                    final terpilih = t.id == tipeOrderIdTerpilih;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        terpilih ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: terpilih ? AppColors.primary : AppColors.textTertiary,
                      ),
                      title: Text(t.nama),
                      subtitle: t.markupPersen > 0 ? Text('Markup ${t.markupPersen}%') : null,
                      onTap: () => Navigator.of(context).pop(t.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
