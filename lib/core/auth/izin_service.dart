import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/seed.dart';
import 'pin_hash.dart';

/// Resolusi izin role untuk PIN-approval (aturan #7 PROMPT_Senior_Mobile_Dev_POS:
/// aksi sensitif wajib cek izin role, butuh PIN owner bila kasir yang
/// melakukan). Belum ada modul login - currentPenggunaIdProvider masih
/// placeholder, lihat seed.dart.
class IzinService {
  IzinService(this._db);

  final AppDatabase _db;
  Future<void>? _seedFuture;

  Future<void> _pastikanSeed() => _seedFuture ??= seedRoleDanOwner(_db);

  Future<bool> hasIzin(String penggunaId, String kodeIzin) async {
    await _pastikanSeed();

    final pengguna =
        await (_db.select(_db.pengguna)..where((t) => t.id.equals(penggunaId))).getSingleOrNull();
    if (pengguna == null) return false;

    // Tahap 5b (desain #2) - role_izin dari SERVER (/sync/pull) diperiksa
    // LEBIH DULU, krn itulah sumber kebenaran utk karyawan yang sudah
    // disatukan identitasnya. Kalau role ini SAMA SEKALI tidak dikenal di
    // tabel sync (belum pernah sync, mis. Owner sebelum pairing pertama),
    // fallback ke role_izin/izin hasil seed lokal lama.
    final adaDiSync = await (_db.select(_db.roleIzinSync)
          ..where((t) => t.roleId.equals(pengguna.roleId)))
        .get();
    if (adaDiSync.isNotEmpty) {
      return adaDiSync.any((r) => r.izinKode == kodeIzin);
    }

    final query = _db.select(_db.roleIzin).join([
      innerJoin(_db.izin, _db.izin.id.equalsExp(_db.roleIzin.izinId)),
    ])
      ..where(_db.roleIzin.roleId.equals(pengguna.roleId) & _db.izin.kode.equals(kodeIzin));

    return await query.getSingleOrNull() != null;
  }

  /// Cari pengguna di toko ini yang PIN-nya cocok DAN punya izin yang
  /// diminta - dipakai saat kasir (tanpa izin) minta approval ke siapapun
  /// yang berwenang (biasanya owner/manajer), bukan mengecek satu akun
  /// tertentu secara hardcoded.
  Future<PenggunaRow?> cariPenggunaUntukApproval({
    required String tokoId,
    required String pin,
    required String kodeIzin,
  }) async {
    await _pastikanSeed();

    // bcrypt menghasilkan salt acak tiap hashPin() dipanggil - TIDAK bisa
    // dibandingkan via WHERE pinHash.equals(...) spt sha256 polos dulu,
    // wajib diverifikasi satu-satu lewat verifyPin() di Dart.
    final kandidat = await (_db.select(_db.pengguna)
          ..where((t) => t.tokoId.equals(tokoId) & t.aktif.equals(true)))
        .get();

    for (final pengguna in kandidat) {
      if (verifyPin(pin, pengguna.pinHash) && await hasIzin(pengguna.id, kodeIzin)) {
        return pengguna;
      }
    }
    return null;
  }
}
