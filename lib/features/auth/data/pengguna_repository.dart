import 'package:drift/drift.dart';

import '../../../core/auth/pin_hash.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/pengguna_dao.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/pengguna.dart';
import '../domain/pengguna_mapper.dart';

/// Tahap 5b (desain #3) - login PIN OFFLINE wajib bisa membedakan "PIN
/// salah" dari "terkunci" dari "nonaktif" (pesan beda per kasus di UI),
/// jadi `verifikasiPin` tidak lagi cuma bool.
enum HasilVerifikasiPin { berhasil, pinSalah, terkunci, nonaktif, tidakDitemukan }

const kMaksPercobaanPinGagal = 5;
const kDurasiKuncPin = Duration(minutes: 5);

class PenggunaRepository {
  PenggunaRepository(this._dao);

  final PenggunaDao _dao;

  Stream<List<Pengguna>> watchPenggunaAktif(String tokoId) =>
      _dao.watchPenggunaAktif(tokoId).map((rows) => rows.map((row) => row.toDomain()).toList());

  Stream<List<RoleRow>> watchRoleBawaan() => _dao.watchRoleBawaan();

  /// Verifikasi PIN pengguna yang dipilih di layar login - lihat
  /// HasilVerifikasiPin utk makna tiap hasil. PIN diverifikasi via
  /// verifyPin (bcrypt, bukan exact-match string - lihat pin_hash.dart).
  Future<HasilVerifikasiPin> verifikasiPin(String penggunaId, String pin) async {
    final pengguna = await _dao.cariById(penggunaId);
    if (pengguna == null) return HasilVerifikasiPin.tidakDitemukan;
    if (!pengguna.aktif || pengguna.deletedAt != null) return HasilVerifikasiPin.nonaktif;

    final sekarang = nowEpochMs();
    final terkunciSampai = pengguna.terkunciSampai;
    if (terkunciSampai != null && terkunciSampai > sekarang) {
      return HasilVerifikasiPin.terkunci;
    }

    if (verifyPin(pin, pengguna.pinHash)) {
      if (pengguna.percobaanGagal != 0 || terkunciSampai != null) {
        await _dao.resetPercobaanGagal(penggunaId);
      }
      return HasilVerifikasiPin.berhasil;
    }

    final percobaanBaru = pengguna.percobaanGagal + 1;
    if (percobaanBaru >= kMaksPercobaanPinGagal) {
      await _dao.kunciSementara(
        penggunaId,
        sampaiEpochMs: sekarang + kDurasiKuncPin.inMilliseconds,
      );
      return HasilVerifikasiPin.terkunci;
    }
    await _dao.catatPercobaanGagal(penggunaId, percobaanBaru);
    return HasilVerifikasiPin.pinSalah;
  }

  /// Tahap 5b (desain #6) - id SERVER karyawan ini, kalau sudah dikenal
  /// (disinkron dari /sync/pull ATAU sudah dimigrasi - lihat kolom
  /// Pengguna.serverPenggunaId). null = device belum tahu id server
  /// karyawan ini (belum pernah sync/migrasi) - pemanggil tidak boleh
  /// mencoba login online dgn id lokal, server tidak akan mengenalnya.
  Future<String?> serverIdUntuk(String penggunaIdLokal) async {
    final pengguna = await _dao.cariById(penggunaIdLokal);
    return pengguna?.serverPenggunaId;
  }

  /// Dipanggil dari layar Daftar (RegisterPage) - mengisi identitas Owner
  /// hasil seed (lihat seed.dart, seedRoleDanOwner) dengan data pemilik
  /// sungguhan. UPDATE (bukan INSERT baru) karena arsitektur saat ini
  /// masih single-tenant per instalasi (toko_id placeholder) - lihat
  /// catatan di session_provider.dart. Kalau karena suatu hal Owner hasil
  /// seed belum ada, baru fallback insert baris baru.
  Future<void> daftarkanPemilik({
    required String tokoId,
    required String nama,
    required String pin,
    String? noHp,
    String? email,
  }) async {
    final now = nowEpochMs();
    final ownerUtama = await _dao.cariOwnerUtama(tokoId);

    if (ownerUtama != null) {
      await _dao.updatePengguna(
        ownerUtama.id,
        PenggunaCompanion(
          nama: Value(nama),
          pinHash: Value(hashPin(pin)),
          noHp: Value(noHp),
          email: Value(email),
          updatedAt: Value(now),
        ),
      );
      return;
    }

    final roleOwner = await _dao.cariRoleOwner();
    if (roleOwner == null) {
      throw StateError('Role Owner belum ada - seed role/izin belum jalan');
    }
    await _dao.tambahPengguna(PenggunaCompanion.insert(
      id: generateId(),
      tokoId: tokoId,
      roleId: roleOwner.id,
      nama: nama,
      pinHash: Value(hashPin(pin)),
      noHp: Value(noHp),
      email: Value(email),
      createdAt: now,
      updatedAt: now,
    ));
  }

  /// Dipanggil sekali setelah OTP pairing ke backend sukses (baik mode
  /// Daftar maupun Masuk - lihat otp_login_page.dart) - mengganti id+tokoId
  /// baris Owner lokal hasil seed/daftarkanPemilik dengan id ASLI dari
  /// backend, supaya payload /sync/push selanjutnya memakai id yang backend
  /// kenal (bukan id yang dibuat sendiri di HP saat offline).
  ///
  /// roleId SENGAJA TIDAK diganti ke id role dari backend - sistem
  /// role/izin/PIN-approval tetap 100% lokal (lihat pin_approval.dart),
  /// backend punya UUID role sendiri yang tidak match baris Role lokal.
  /// Kalau pin diisi (mode Daftar), PIN lokal ikut diperbarui; mode Masuk
  /// (pairing device baru ke toko yang sudah ada) TIDAK mengubah PIN lokal
  /// - server tidak pernah mengirim balik PIN asli (hash tidak reversible,
  /// lagipula skema hash lokal beda dgn bcrypt di server), jadi PIN di
  /// device ini wajib diset/reset manual lewat halaman Pengguna setelah
  /// pairing - dicatat sbg batasan, bukan diabaikan.
  Future<void> terapkanIdentitasBackend({
    required String tokoIdLama,
    required String tokoIdBaru,
    required String penggunaIdBaru,
    required String namaDariBackend,
    String? pin,
  }) async {
    // Fallback ke cariOwnerManaSaja kalau baris Owner lokal sudah pernah
    // dimigrasikan ke tokoId lain oleh percobaan pairing sebelumnya yang
    // gagal di tengah jalan (lihat catatan di cariOwnerManaSaja) - jangan
    // langsung anggap "seed belum jalan" cuma krn tokoIdLama tidak match.
    final ownerUtama =
        await _dao.cariOwnerUtama(tokoIdLama) ?? await _dao.cariOwnerManaSaja();
    if (ownerUtama == null) {
      throw StateError('Baris Owner lokal tidak ditemukan - seed belum jalan?');
    }
    final now = nowEpochMs();
    await _dao.updatePengguna(
      ownerUtama.id,
      PenggunaCompanion(
        id: Value(penggunaIdBaru),
        tokoId: Value(tokoIdBaru),
        nama: Value(namaDariBackend),
        pinHash: pin == null ? const Value.absent() : Value(hashPin(pin)),
        // Tahap 5b (desain #6) - Owner JUGA butuh serverPenggunaId terisi
        // supaya login_page.dart bisa upgrade ke token online atas nama
        // Owner sendiri (id lokal Owner SELALU == id server sejak baris
        // di atas, sama persis spt karyawan yang disinkron dari server).
        serverPenggunaId: Value(penggunaIdBaru),
        updatedAt: Value(now),
      ),
    );
  }
}
