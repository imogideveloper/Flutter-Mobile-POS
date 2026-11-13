import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart' show ProdukCompanion;
import '../../../../core/network/auth_session_store.dart';
import '../../../../core/network/backend_exception.dart';
import '../../../../core/network/dio_backend_api.dart';
import '../../../../core/network/sync_mapping.dart';
import '../../../../core/providers/session_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/utils/rupiah_input_formatter.dart';
import '../../../../core/widgets/barcode_scan_page.dart';
import '../../../../core/widgets/fitur_terkunci.dart';
import '../../../../core/widgets/offline_notice_banner.dart';
import '../../../stok/presentation/providers/stok_providers.dart';
import '../../../stok/data/local/tables/mutasi_stok_table.dart'
    show MutasiJenis;
import '../../data/local/tables/produk_table.dart' show ProdukTipe, produkTipePostgresValue;
import '../../domain/produk.dart';
import '../../domain/margin_produk.dart';
import '../../../transaksi/presentation/providers/harga_keranjang_provider.dart' show pengaturanOutletProvider;
import '../providers/kategori_providers.dart';
import '../providers/produk_providers.dart';
import '../widgets/produk_lanjutan_sections.dart';

final _formatRupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
);

const _labelTipeProduk = {
  ProdukTipe.barang: 'Barang',
  ProdukTipe.jasa: 'Jasa',
  ProdukTipe.bahanBaku: 'Bahan baku',
  ProdukTipe.bundling: 'Bundling',
};

/// Form tambah/edit produk. Kirim [produk] untuk mode edit - kalau null,
/// ini mode tambah baru.
///
/// Kategori, varian, dan modifier SENGAJA belum ada di form ini - belum
/// ada CRUD kategori/grup-modifier terpisah untuk mengisinya, jadi
/// menambah field itu di sini hanya akan jadi input tanpa tujuan. Susulkan
/// begitu modul kategori & modifier dibangun.
///
/// Tahap 5 C.8 - 4 seksi lanjutan (resep/bundling/harga grosir/harga per
/// outlet, lihat ProdukLanjutanSections) HANYA tampil di mode edit -
/// semuanya endpoint `/produk/{id}/...` yang butuh id produk SUNGGUHAN,
/// jadi produk baru wajib disimpan dulu sebelum bisa diisi.
class ProdukFormPage extends ConsumerStatefulWidget {
  const ProdukFormPage({super.key, this.produk});

  final Produk? produk;

  @override
  ConsumerState<ProdukFormPage> createState() => _ProdukFormPageState();
}

class _ProdukFormPageState extends ConsumerState<ProdukFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _namaController = TextEditingController(
    text: widget.produk?.nama ?? '',
  );
  late final _hargaJualController = TextEditingController(
    text: widget.produk == null ? '' : formatRupiahDigits(widget.produk!.hargaJual),
  );
  late final _hppController = TextEditingController(
    text: formatRupiahDigits(widget.produk?.hpp ?? 0),
  );
  late final _skuController = TextEditingController(
    text: widget.produk?.sku ?? '',
  );
  late final _barcodeController = TextEditingController(
    text: widget.produk?.barcode ?? '',
  );
  final _stokAwalController = TextEditingController(text: '0');
  final _batasMinController = TextEditingController(text: '0');

  late ProdukTipe _tipe = widget.produk?.tipe ?? ProdukTipe.barang;
  late String? _kategoriId = widget.produk?.kategoriId;
  late bool _lacakStok = widget.produk?.lacakStok ?? true;
  late bool _pakaiResep = widget.produk?.pakaiResep ?? false;
  late bool _aktif = widget.produk?.aktif ?? true;
  late String? _fotoPath = widget.produk?.gambarUrl;
  bool _menyimpan = false;

  bool get _modeEdit => widget.produk != null;

  @override
  void initState() {
    super.initState();
    // Mode edit tidak punya "stok awal" lagi (lihat _simpan) tapi TETAP
    // perlu tahu batas minimum YANG SUDAH TERSIMPAN supaya field "Ingatkan
    // jika sisa" di bawah tidak kelihatan kosong/ke-reset ke 0 tiap buka
    // Edit - sebelum ini field itu malah disembunyikan total di mode edit,
    // jadi produk lama tidak pernah bisa diatur ulang batas minimumnya.
    if (_modeEdit) _muatBatasMinimum();
  }

  Future<void> _muatBatasMinimum() async {
    final outletId = ref.read(currentOutletIdProvider);
    final batas = await ref.read(stokRepositoryProvider).batasMinimumUntuk(
          outletId: outletId,
          produkId: widget.produk!.id,
        );
    if (mounted && batas > 0) {
      setState(() => _batasMinController.text = batas.toStringAsFixed(batas.truncateToDouble() == batas ? 0 : 2));
    }
  }

  @override
  void dispose() {
    _namaController.dispose();
    _hargaJualController.dispose();
    _hppController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _stokAwalController.dispose();
    _batasMinController.dispose();
    super.dispose();
  }

  int get _hargaJual => parseRupiahInput(_hargaJualController.text) ?? 0;
  int get _hpp => parseRupiahInput(_hppController.text) ?? 0;

  Future<void> _pilihFoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file != null && mounted) setState(() => _fotoPath = file.path);
  }

  Future<void> _scanBarcode() async {
    final hasil = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const BarcodeScanPage()),
    );
    if (hasil != null && mounted) {
      setState(() => _barcodeController.text = hasil);
    }
  }

  // Bug nyata (laporan pengguna: produk yang dibuat di HP bisa hilang
  // permanen kalau HP di-uninstall/reset - ditemukan sambil investigasi
  // karena /sync/push TERNYATA TIDAK PUNYA field `produk` sama sekali,
  // jadi produk lokal tidak pernah benar2 "menunggu disinkron" - memang
  // tidak ada jalan ke server). Form ini sekarang ONLINE-DIRECT (sama
  // pola dgn Karyawan/Promo/Pajak di Tahap 5/5b) - simpan ke server DULU,
  // baru tulis-tembus (write-through) ke cache lokal supaya UI & layar
  // offline lain tetap langsung lihat hasilnya tanpa nunggu sync pull
  // berikutnya.
  //
  // `pakaiResep`/`gambarUrl` SENGAJA TETAP LOKAL MURNI (belum ada
  // field-nya di ProdukIn/ProdukOut backend) - diakui sbg keterbatasan
  // yang belum dibereskan di sesi ini, bukan diam-diam dihapus.
  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    final sesi = await ref.read(authSessionStoreProvider).muat();
    if (!mounted) return;
    if (sesi == null) {
      showAppToast(context, message: 'Device belum pairing ke backend.', variant: ToastVariant.warning);
      return;
    }

    setState(() => _menyimpan = true);
    try {
      final outletId = ref.read(currentOutletIdProvider);
      final dijual = _tipe != ProdukTipe.bahanBaku;

      final api = ref.read(backendApiProvider);
      final body = {
        'nama': _namaController.text.trim(),
        'tipe': produkTipePostgresValue[_tipe],
        'kategori_id': _kategoriId,
        'sku': _skuController.text.trim().isEmpty ? null : _skuController.text.trim(),
        'barcode': _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
        'harga_jual': _hargaJual.toString(),
        'hpp': _hpp.toString(),
        'lacak_stok': _lacakStok,
        'aktif': _aktif,
      };
      Map<String, dynamic> hasil;
      // "Produk hantu" (temuan nyata: laporan "Gagal memuat resep/pajak:
      // Produk tidak ditemukan" di Edit Produk) - baris lokal dari era
      // sebelum Produk jadi online-direct (dibuat offline murni, toko_id-nya
      // ikut termigrasi PairingDao.migrasikanTokoId saat pairing, tapi
      // baris-nya TIDAK PERNAH ada di server). PATCH ke id semacam itu
      // selalu 404 - sembuhkan transparan dgn bikin baru di server (POST),
      // bukan gagal diam2 menyuruh user hapus-lalu-buat-ulang manual.
      var idBerubah = false;
      if (_modeEdit) {
        try {
          hasil = await api.patchJson(
                accessToken: sesi.accessToken,
                path: '/produk/${widget.produk!.id}',
                body: body,
              ) as Map<String, dynamic>;
        } on BackendException catch (e) {
          if (e.statusCode != 404) rethrow;
          hasil = await api.postJson(
                accessToken: sesi.accessToken,
                path: '/produk',
                body: body,
              ) as Map<String, dynamic>;
          idBerubah = true;
        }
      } else {
        hasil = await api.postJson(
              accessToken: sesi.accessToken,
              path: '/produk',
              body: body,
            ) as Map<String, dynamic>;
      }

      final produkId = hasil['id'] as String;
      final now = DateTime.now().millisecondsSinceEpoch;
      final tipeServer = ProdukTipe.values.byName(produkTipeDariBackend(hasil['tipe'] as String));
      if (idBerubah) {
        // id server BEDA dari id lokal lama (baris hantu barusan "lahir
        // ulang" sbg produk baru) - baris lokal lama wajib dibuang, bukan
        // ditinggal jadi duplikat kedua di sebelah yang baru.
        await ref.read(produkDaoProvider).hapusPermanen(widget.produk!.id);
      }
      if (_modeEdit && !idBerubah) {
        await ref.read(produkDaoProvider).updateProduk(
              produkId,
              ProdukCompanion(
                tokoId: Value(hasil['toko_id'] as String),
                kategoriId: Value(hasil['kategori_id'] as String?),
                satuanId: Value(hasil['satuan_id'] as String?),
                sku: Value(hasil['sku'] as String?),
                barcode: Value(hasil['barcode'] as String?),
                nama: Value(hasil['nama'] as String),
                tipe: Value(tipeServer),
                lacakStok: Value(hasil['lacak_stok'] as bool),
                pakaiResep: Value(_pakaiResep),
                gambarUrl: Value(_fotoPath),
                dijual: Value(dijual),
                hpp: Value(uangDariBackend(hasil['hpp'].toString())),
                hargaJual: Value(uangDariBackend(hasil['harga_jual'].toString())),
                aktif: Value(hasil['aktif'] as bool),
                updatedAt: Value(now),
              ),
            );
      } else {
        await ref.read(produkDaoProvider).upsertProduk(
              ProdukCompanion.insert(
                id: produkId,
                tokoId: hasil['toko_id'] as String,
                kategoriId: Value(hasil['kategori_id'] as String?),
                satuanId: Value(hasil['satuan_id'] as String?),
                sku: Value(hasil['sku'] as String?),
                barcode: Value(hasil['barcode'] as String?),
                nama: hasil['nama'] as String,
                tipe: tipeServer,
                lacakStok: Value(hasil['lacak_stok'] as bool),
                pakaiResep: Value(_pakaiResep),
                gambarUrl: Value(_fotoPath),
                dijual: Value(dijual),
                hpp: Value(uangDariBackend(hasil['hpp'].toString())),
                hargaJual: Value(uangDariBackend(hasil['harga_jual'].toString())),
                aktif: Value(hasil['aktif'] as bool),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      if (_lacakStok) {
        // Bug nyata (laporan pengguna): "Ingatkan jika sisa" dulu TIDAK
        // PERNAH dibaca di sini sama sekali - controller-nya ada & tampil
        // di form, tapi nilainya kebuang begitu Simpan ditekan, jadi tab
        // "Stok menipis" tidak pernah menandai produk manapun.
        //
        // Keterbatasan diakui (bukan ditutupi) - kasus `idBerubah` (produk
        // hantu) pakai cabang `aturBatasMinimum` di bawah persis spt edit
        // biasa, TAPI baris stok lokal lama masih tertaut ke id produk
        // LAMA (belum ikut dimigrasikan ke produkId baru) - saldo stok
        // produk yg baru "lahir ulang" ini perlu diperiksa manual lewat
        // halaman Stok, belum ditangani otomatis di sini.
        final batasMinimum = double.tryParse(_batasMinController.text) ?? 0;
        if (!_modeEdit) {
          // Stok awal hanya dicatat sekali saat produk baru dibuat - kalau
          // mode edit, perubahan SALDO wajib lewat halaman Stok (tercatat
          // di mutasi_stok dengan jenis yang sesuai), bukan ditimpa
          // diam-diam dari sini. Trigger baris stok juga kalau batas
          // minimum diisi walau stok awal 0 (kasus wajar: produk baru
          // belum ada stok, tapi kasir sudah mau diingatkan begitu nanti
          // direstok).
          final stokAwal = double.tryParse(_stokAwalController.text) ?? 0;
          if (stokAwal > 0 || batasMinimum > 0) {
            await ref
                .read(stokRepositoryProvider)
                .catatMutasi(
                  tokoId: hasil['toko_id'] as String,
                  outletId: outletId,
                  produkId: produkId,
                  jenis: MutasiJenis.stokAwal,
                  qty: stokAwal,
                  batasMinimum: batasMinimum,
                );
          }
        } else {
          // Mode edit - HANYA ubah ambang pengingat, TIDAK menyentuh saldo
          // stok (lihat StokDao.aturBatasMinimum, baru ditambah supaya
          // produk lama yang kadung terlanjur tidak terisi juga bisa
          // diperbaiki lewat Edit, bukan harus hapus+buat ulang).
          await ref.read(stokRepositoryProvider).aturBatasMinimum(
                outletId: outletId,
                produkId: produkId,
                batasMinimum: batasMinimum,
              );
        }
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showAppToast(context, message: 'Gagal menyimpan: $e', variant: ToastVariant.danger);
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = isOnlineSaat(ref);
    final margin = _hargaJual - _hpp;
    final persenMargin = marginPersen(hargaJual: _hargaJual, hpp: _hpp) ?? 0;
    // Batas margin diatur per outlet (Pengaturan struk), bawaan 50% untuk makanan dan minuman.
    final batasMargin = ref.watch(pengaturanOutletProvider(ref.watch(currentOutletIdProvider))).value?.batasMargin ?? batasMarginBawaan;
    final statusMargin_ = statusMargin(hargaJual: _hargaJual, hpp: _hpp, batasPersen: batasMargin);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(_modeEdit ? 'Edit produk' : 'Tambah produk'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          key: const Key('produkForm.scrollView'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OfflineNoticeBanner(),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FotoPicker(path: _fotoPath, onTap: _pilihFoto),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: _LabeledField(
                            label: 'Nama produk',
                            child: TextFormField(
                              key: const Key('produkForm.nama'),
                              controller: _namaController,
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Nama wajib diisi'
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _LabeledField(
                      label: 'Tipe produk',
                      child: DropdownButtonFormField<ProdukTipe>(
                        initialValue: _tipe,
                        items: ProdukTipe.values
                            .map(
                              (tipe) => DropdownMenuItem(
                                value: tipe,
                                child: Text(_labelTipeProduk[tipe]!),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _tipe = value ?? _tipe),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _LabeledField(
                      label: 'Kategori',
                      child: Consumer(
                        builder: (context, ref, _) {
                          final tokoId = ref.watch(currentTokoIdProvider);
                          final kategoriAsync = ref.watch(kategoriAktifProvider(tokoId));
                          return kategoriAsync.when(
                            data: (daftar) {
                              // kategoriId lama bisa saja sudah dihapus - tetap
                              // tampilkan dropdown-nya tanpa crash, cuma gugur
                              // ke null (tanpa kategori) kalau tidak ketemu.
                              final adaDiDaftar = daftar.any((k) => k.id == _kategoriId);
                              return DropdownButtonFormField<String?>(
                                key: const Key('produkForm.kategori'),
                                initialValue: adaDiDaftar ? _kategoriId : null,
                                decoration: const InputDecoration(hintText: 'Tanpa kategori'),
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Tanpa kategori')),
                                  for (final k in daftar) DropdownMenuItem(value: k.id, child: Text(k.nama)),
                                ],
                                onChanged: (value) => setState(() => _kategoriId = value),
                              );
                            },
                            loading: () => const LinearProgressIndicator(),
                            error: (error, stackTrace) => Text('Gagal memuat kategori: $error'),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: _LabeledField(
                            label: 'Harga jual',
                            child: TextFormField(
                              key: const Key('produkForm.hargaJual'),
                              controller: _hargaJualController,
                              decoration: const InputDecoration(prefixText: 'Rp '),
                              keyboardType: TextInputType.number,
                              inputFormatters: [RupiahInputFormatter()],
                              onChanged: (_) => setState(() {}),
                              validator: (value) {
                                if (parseRupiahInput(value ?? '') == null) return 'Wajib diisi';
                                return null;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _LabeledField(
                            label: 'Harga modal (HPP)',
                            child: TextFormField(
                              controller: _hppController,
                              decoration: const InputDecoration(prefixText: 'Rp '),
                              keyboardType: TextInputType.number,
                              inputFormatters: [RupiahInputFormatter()],
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_hargaJual > 0) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Margin ${_formatRupiah.format(margin)} · $persenMargin%',
                        key: const Key('produkForm.margin'),
                        style: AppTypography.secondary.copyWith(
                          color: statusMargin_ == StatusMargin.rendah ? AppColors.warningTextStrong : AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (statusMargin_ == StatusMargin.rendah)
                        Text(
                          'Di bawah batas margin $batasMargin%. Periksa harga jual atau HPP.',
                          key: const Key('produkForm.margin.peringatan'),
                          style: AppTypography.secondary.copyWith(color: AppColors.warningTextStrong),
                        )
                      else if (statusMargin_ == StatusMargin.hppKosong)
                        Text(
                          'HPP belum diisi, margin belum akurat.',
                          key: const Key('produkForm.margin.hppKosong'),
                          style: AppTypography.secondary,
                        ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    _LabeledField(
                      label: 'SKU / barcode',
                      child: TextFormField(
                        controller: _barcodeController,
                        decoration: InputDecoration(
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.qr_code_scanner,
                              color: AppColors.primary,
                            ),
                            onPressed: _scanBarcode,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ToggleRow(
                      title: 'Lacak stok',
                      subtitle: 'Stok berkurang otomatis saat terjual',
                      value: _lacakStok,
                      onChanged: (value) => setState(() => _lacakStok = value),
                    ),
                    if (_lacakStok) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          if (!_modeEdit) ...[
                            Expanded(
                              child: _LabeledField(
                                label: 'Stok awal',
                                child: TextFormField(
                                  key: const Key('produkForm.stokAwal'),
                                  controller: _stokAwalController,
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                          ],
                          Expanded(
                            child: _LabeledField(
                              label: 'Ingatkan jika sisa',
                              child: TextFormField(
                                key: const Key('produkForm.batasMinimum'),
                                controller: _batasMinController,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  children: [
                    FiturTerkunci(
                      kode: 'resep',
                      child: _ToggleRow(
                        title: 'Pakai resep bahan baku',
                        subtitle: 'Potong stok bahan baku tiap terjual',
                        value: _pakaiResep,
                        onChanged: (value) => setState(() => _pakaiResep = value),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _ToggleRow(
                      title: 'Tampil di kasir',
                      subtitle: 'Matikan untuk menyembunyikan sementara',
                      value: _aktif,
                      onChanged: (value) => setState(() => _aktif = value),
                    ),
                  ],
                ),
              ),
              if (_modeEdit) ...[
                const SizedBox(height: AppSpacing.lg),
                ProdukLanjutanSections(produkId: widget.produk!.id),
              ],
              const SizedBox(height: AppSpacing.xxxl),
              AppPrimaryButton(
                label: _menyimpan ? 'Menyimpan...' : 'Simpan produk',
                onPressed: _menyimpan || !online ? null : _simpan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FotoPicker extends StatelessWidget {
  const _FotoPicker({required this.path, required this.onTap});

  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final file = path;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.textTertiary,
            style: file == null ? BorderStyle.solid : BorderStyle.none,
          ),
          image: file == null
              ? null
              : DecorationImage(
                  image: FileImage(File(file)),
                  fit: BoxFit.cover,
                ),
        ),
        alignment: Alignment.center,
        child: file != null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_a_photo_outlined,
                    size: 22,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Foto',
                    style: AppTypography.secondary.copyWith(fontSize: 11),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.secondary.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyEmphasis),
              Text(subtitle, style: AppTypography.secondary),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.primary,
        ),
      ],
    );
  }
}
