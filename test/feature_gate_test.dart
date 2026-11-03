import 'package:apps_pos/core/database/app_database.dart';
import 'package:apps_pos/core/providers/database_provider.dart';
import 'package:apps_pos/core/providers/session_provider.dart';
import 'package:apps_pos/features/fitur/presentation/providers/feature_gate_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// FeatureGate murni baca cache lokal (diisi SyncRepository tiap pull,
/// lihat FiturDao.simpanStatusFitur) - tes ini simulasikan isi cache utk
/// ketiga tingkat paket langsung lewat DAO, tanpa jaringan/backend
/// sungguhan (sama polanya dgn sync_repository_test.dart).
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [appDatabaseProvider.overrideWith((ref) => db)]);
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  test('FeatureGate.has benar utk paket Gratis - hanya fitur tingkat 0', () async {
    final tokoId = container.read(currentTokoIdProvider);
    await db.fiturDao.simpanStatusFitur(
      tokoId: tokoId,
      paket: 'Gratis',
      kodeFiturAktif: const ['pos', 'cetak_struk', 'scan_barcode', 'kelola_stok', 'kelola_pelanggan', 'laporan_dasar'],
      batasPerKode: const {'laporan_dasar': 30},
      updatedAt: 0,
    );

    final gate = await container.read(featureGateProvider.future);
    expect(gate.paket, 'Gratis');
    expect(gate.has('pos'), isTrue);
    expect(gate.has('laporan_dasar'), isTrue);
    expect(gate.batasUntuk('laporan_dasar'), 30);
    expect(gate.has('diskon'), isFalse);
    expect(gate.has('tiket_dapur'), isFalse);
  });

  test('FeatureGate.has benar utk paket Pro - tingkat 0 dan 1, bukan tingkat 2', () async {
    final tokoId = container.read(currentTokoIdProvider);
    await db.fiturDao.simpanStatusFitur(
      tokoId: tokoId,
      paket: 'Pro',
      kodeFiturAktif: const ['pos', 'diskon', 'resep', 'tipe_order'],
      batasPerKode: const {'laporan_dasar': 365},
      updatedAt: 0,
    );

    final gate = await container.read(featureGateProvider.future);
    expect(gate.paket, 'Pro');
    expect(gate.has('pos'), isTrue);
    expect(gate.has('diskon'), isTrue);
    expect(gate.has('resep'), isTrue);
    expect(gate.has('tiket_dapur'), isFalse);
    expect(gate.has('harga_grosir'), isFalse);
  });

  test('FeatureGate.has benar utk paket Bisnis - semua tingkat', () async {
    final tokoId = container.read(currentTokoIdProvider);
    await db.fiturDao.simpanStatusFitur(
      tokoId: tokoId,
      paket: 'Bisnis',
      kodeFiturAktif: const ['pos', 'diskon', 'resep', 'tiket_dapur', 'harga_grosir', 'bundling'],
      batasPerKode: const {},
      updatedAt: 0,
    );

    final gate = await container.read(featureGateProvider.future);
    expect(gate.paket, 'Bisnis');
    expect(gate.has('tiket_dapur'), isTrue);
    expect(gate.has('harga_grosir'), isTrue);
    expect(gate.has('bundling'), isTrue);
    expect(gate.batasUntuk('laporan_dasar'), isNull); // Bisnis = tanpa batas
  });

  test('FeatureGate kosong (belum pernah sync) - semua fitur dianggap tertutup', () async {
    final gate = await container.read(featureGateProvider.future);
    expect(gate.paket, isNull);
    expect(gate.has('pos'), isFalse);
  });
}
