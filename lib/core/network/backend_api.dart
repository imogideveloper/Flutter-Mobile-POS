/// Abstraksi panggilan ke backend FastAPI - sengaja dipisah dari
/// implementasi Dio (lihat dio_backend_api.dart) supaya SyncRepository dan
/// alur pairing OTP bisa ditest dengan FakeBackendApi tanpa jaringan
/// sungguhan (tidak ada device/emulator+server hidup di sandbox ini).
abstract class BackendApi {
  Future<OtpRequestResult> otpRequest({required String noHp});

  Future<AuthResult> otpVerify({
    required String noHp,
    required String kode,
    required String deviceUid,
    required String namaPerangkat,
    String? platform,
    String? namaToko,
    String? jenisUsaha,
    String? namaPemilik,
    String? pin,
  });

  Future<String> refreshAccessToken({required String refreshToken});

  /// Tahap 5b (desain #6) - login PIN ONLINE, menghasilkan token ATAS
  /// NAMA karyawan ybs (bukan token device/Owner) - dipakai utk panggilan
  /// online langsung (refund, layar kelola) supaya izin dicek berdasarkan
  /// identitas karyawan sungguhan. Device WAJIB sudah pernah pairing
  /// (perangkatId dari AuthSessionStore) - endpoint ini tidak mendaftarkan
  /// device baru. Lempar BackendException kalau PIN salah/tidak aktif/
  /// tidak punya akses outlet - pemanggil (login_page.dart) menelan error
  /// ini diam-diam (login LOKAL offline sudah cukup utk masuk, upgrade ke
  /// token online ini best-effort saja).
  Future<PinLoginResult> pinLoginOnline({
    required String perangkatId,
    required String penggunaId,
    required String pin,
  });

  Future<SyncPushResult> syncPush({
    required String accessToken,
    required String perangkatId,
    required List<Map<String, dynamic>> transaksi,
    // Cicilan/pelunasan kasbon (tahap 3b-1) yang dicatat offline - lihat
    // PembayaranPushIn di backend/app/schemas/sync.py. Beda dari
    // pembayaran yang lahir BERSAMA checkout (itu ikut payload `transaksi`
    // di atas, backend membuat baris pembayarannya sendiri).
    List<Map<String, dynamic>> pembayaran = const [],
    // Temuan#2 (rapikan F3.E) - pembatalan pesanan tersimpan yang terjadi
    // SAAT OFFLINE, dikirim belakangan lewat kategori ini - lihat
    // PesananBatalPushIn di backend/app/schemas/sync.py.
    List<Map<String, dynamic>> pesananBatal = const [],
  });

  /// `since` = ISO8601, berlaku SAMA utk semua tabel sekaligus (bukan per
  /// tabel - lihat SyncPullOut.has_more di backend/app/schemas/sync.py).
  /// Pemanggil (SyncRepository) yang bertanggung jawab mengulang panggilan
  /// ini dgn `since` yang dimajukan selama ada tabel yang `has_more`.
  Future<SyncPullResult> syncPull({
    required String accessToken,
    required String perangkatId,
    required String since,
    String? outletId,
    int limit = 500,
  });

  /// Pengaturan struk outlet (tahap 4 bagian B) - server WAJIB jadi sumber
  /// kebenaran (beda dari data offline-first lain yang boleh ditulis lokal
  /// lalu disync) krn kolom ini (header/footer/lebar kertas/dkk) tidak ada
  /// artinya diedit tanpa koneksi, dan harus konsisten lintas-device di
  /// outlet yang sama. Kembalikan Map mentah (field snake_case dari JSON
  /// response, sama konvensi dgn SyncPullOut) drpd kelas khusus - dipakai
  /// langsung oleh halaman pengaturan, tidak perlu dipetakan ke tipe Dart.
  Future<Map<String, dynamic>> ambilPengaturanOutlet({
    required String accessToken,
    required String outletId,
  });

  Future<Map<String, dynamic>> ubahPengaturanOutlet({
    required String accessToken,
    required String outletId,
    required Map<String, dynamic> body,
  });

  /// Upload logo toko (tahap 4 bagian B.2) - [namaFile] dipakai server utk
  /// sniffing ekstensi dari isi file (magic bytes), bukan dari nama file
  /// ini (nama ini cuma label utk Content-Disposition multipart).
  Future<String> uploadLogoToko({
    required String accessToken,
    required List<int> bytes,
    required String namaFile,
  });

  Future<Map<String, dynamic>> ubahMetodeBayar({
    required String accessToken,
    required String metodeBayarId,
    required Map<String, dynamic> body,
  });

  /// F3.B - daftar transaksi dgn filter rentang tanggal server-side,
  /// dipakai RiwayatListPage SAJA saat rentang yang dipilih kasir lebih
  /// jauh drpd data yang tersimpan lokal (data normal tetap dari drift
  /// lokal, offline-first). Map mentah (field snake_case), sama konvensi
  /// dgn ambilPengaturanOutlet - dipetakan ke RingkasanTransaksi di
  /// pemanggil, bukan di layer network ini.
  Future<Map<String, dynamic>> ambilTransaksi({
    required String accessToken,
    required String outletId,
    required String dariTanggal,
    required String sampaiTanggal,
    int limit = 200,
    int offset = 0,
  });

  /// Temuan A.2 (tahap 5) - detail SATU transaksi dari server (termasuk
  /// `snapshot_struk`), dipakai cetak ulang transaksi dari HP LAIN (tidak
  /// pernah ada di drift lokal device ini - lihat TransaksiDetailPage).
  Future<Map<String, dynamic>> ambilDetailTransaksi({
    required String accessToken,
    required String transaksiId,
  });

  /// F3.D - daftar item transaksi yg masih bisa direfund (qty asli -
  /// sudah direfund, dihitung SERVER). Refund (beda dari sebagian besar
  /// fitur lain di app ini) SELALU online - tidak offline-first, lihat
  /// docs/aturan_harga.md bagian Refund utk alasannya (perlu id
  /// item_transaksi SUNGGUHAN dari server, bukan id lokal HP).
  Future<List<Map<String, dynamic>>> ambilItemRefundable({
    required String accessToken,
    required String transaksiId,
  });

  Future<Map<String, dynamic>> buatRefund({
    required String accessToken,
    required String transaksiId,
    required Map<String, dynamic> body,
  });

  /// F3.F - halaman "Paket langganan". Semua SELALU online (data
  /// kuota/perbandingan fitur harus akurat real-time, tidak ada artinya
  /// di-cache offline) - sama prinsip dgn ambilPengaturanOutlet dkk.
  Future<List<Map<String, dynamic>>> ambilDaftarPaket({required String accessToken});

  Future<Map<String, dynamic>> ambilLanggananSaya({required String accessToken});

  Future<Map<String, dynamic>> ajukanUpgrade({
    required String accessToken,
    required Map<String, dynamic> body,
  });

  /// Upgrade paket SUNGGUHAN lewat pembayaran Xendit (dibalik dari
  /// keputusan awal "tanpa pembayaran di app", lihat
  /// backend/app/services/xendit_service.py) - beda dari [ajukanUpgrade]
  /// (jalur manual lama, masih dipertahankan backend utk kasus di luar
  /// Xendit). Balas `invoice_url` utk dibuka di browser.
  Future<Map<String, dynamic>> checkoutUpgrade({
    required String accessToken,
    required Map<String, dynamic> body,
  });

  /// Dipanggil app SETELAH user kembali dari halaman bayar Xendit -
  /// backend yang nanya status KE Xendit (bukan nunggu webhook), lihat
  /// catatan lengkap di xendit_service.py kenapa jalur ini perlu ada
  /// sendiri. Balas {"status": "baru"|"selesai"|"batal"}.
  Future<Map<String, dynamic>> statusCheckoutUpgrade({
    required String accessToken,
    required String permintaanId,
  });

  /// Temuan#2 (rapikan F3.E) - jalur ONLINE pembatalan pesanan tersimpan
  /// (`POST /transaksi/pesanan-tersimpan/{id}/batalkan`). Jalur OFFLINE
  /// lewat kategori `pesanan_batal` di syncPush, BUKAN method ini - lihat
  /// TransaksiRepository.batalkanPesanan & SyncRepository.
  Future<void> batalkanPesananTersimpan({
    required String accessToken,
    required String pesananId,
    required Map<String, dynamic> body,
  });

  /// Tahap 5 bagian C - layar kelola data master (pajak, promo, pelanggan,
  /// karyawan, level member, aturan poin, tipe order, meja, produk
  /// lanjutan dkk) SELALU online (Prinsip 1). Daripada menulis satu method
  /// bernama per endpoint (puluhan kombinasi CRUD yang pola HTTP-nya
  /// identik), dipakai 4 method generik Map-passthrough ini - konsisten
  /// dgn konvensi `ambilPengaturanOutlet`/`ubahPengaturanOutlet` di atas
  /// (balas Map/List mentah, dipetakan oleh pemanggil, bukan di layer
  /// network). [path] diawali '/', TANPA query string (pakai [query]).
  Future<dynamic> getJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? query,
  });

  Future<dynamic> postJson({
    required String accessToken,
    required String path,
    Map<String, dynamic>? body,
  });

  Future<dynamic> patchJson({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  });

  /// PUT generik dgn body Map bebas (BEDA dari [putJsonIds] di bawah yang
  /// khusus body `{"ids": [...]}`) - dipakai endpoint upsert singleton spt
  /// `PUT /aturan-poin`.
  Future<dynamic> putJsonBody({
    required String accessToken,
    required String path,
    required Map<String, dynamic> body,
  });

  Future<void> deleteJson({required String accessToken, required String path});

  /// Endpoint replace-all "set" (`PUT .../produk`, `.../outlet` dkk - lihat
  /// IdsIn di backend) - SELALU berbentuk `{"ids": [...]}`, jadi dibuatkan
  /// method sendiri drpd `Map<String,dynamic> body` generik spy pemanggil
  /// tidak perlu menulis ulang `{'ids': ids}` di tiap tempat.
  Future<void> putJsonIds({
    required String accessToken,
    required String path,
    required List<String> ids,
  });
}

class PinLoginResult {
  const PinLoginResult({required this.accessToken, required this.refreshToken, required this.penggunaId});

  final String accessToken;
  final String refreshToken;
  final String penggunaId;
}

class OtpRequestResult {
  const OtpRequestResult({required this.expiresIn});

  final int expiresIn;
}

class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.tokoId,
    required this.tokoNama,
    required this.outletId,
    required this.outletNama,
    required this.outletKode,
    required this.penggunaId,
    required this.penggunaNama,
    required this.perangkatId,
  });

  final String accessToken;
  final String refreshToken;
  final String tokoId;
  final String tokoNama;
  final String outletId;
  final String outletNama;
  final String outletKode;
  final String penggunaId;
  final String penggunaNama;
  final String perangkatId;
}

/// status: "diterima" | "sudah_ada" | "ditolak" - lihat HasilItemPush di
/// backend/app/schemas/sync.py.
class HasilPushItem {
  const HasilPushItem({required this.id, required this.status, this.pesan});

  final String id;
  final String status;
  final String? pesan;
}

class SyncPushResult {
  const SyncPushResult({
    required this.transaksi,
    this.pembayaran = const [],
    this.pesananBatal = const [],
  });

  final List<HasilPushItem> transaksi;
  final List<HasilPushItem> pembayaran;
  // Temuan#2 (rapikan F3.E) - hasil kategori `pesanan_batal` (pembatalan
  // pesanan tersimpan yang terjadi saat offline, dikirim belakangan).
  final List<HasilPushItem> pesananBatal;
}

class SyncPullResult {
  const SyncPullResult({
    required this.waktuPull,
    required this.produk,
    required this.kategori,
    required this.satuan,
    required this.pajak,
    required this.promo,
    required this.metodeBayar,
    required this.stok,
    required this.hargaOutlet,
    required this.hargaGrosir,
    required this.tipeOrderPajak,
    required this.pengaturanOutlet,
    required this.hasMore,
    required this.paket,
    this.logoUrl,
    required this.kodeFitur,
    required this.batasFitur,
    this.pengguna = const [],
    this.role = const [],
    this.roleIzin = const [],
    this.pelanggan = const [],
  });

  final String waktuPull;
  final List<Map<String, dynamic>> produk;
  final List<Map<String, dynamic>> kategori;
  final List<Map<String, dynamic>> satuan;
  final List<Map<String, dynamic>> pajak;
  final List<Map<String, dynamic>> promo;
  final List<Map<String, dynamic>> metodeBayar;
  final List<Map<String, dynamic>> stok;
  // Tahap 5b (desain #2) - "karyawan = baris pengguna server", dikirim
  // lewat /sync/pull supaya device bisa login PIN offline. `pengguna`
  // sudah termasuk `pin_hash` mentah dari server (HARUS argon2id/bcrypt,
  // tidak pernah PIN polos - lihat backend/app/services/sync_service.py).
  // `roleIzin` relasi murni (role_id+izin_kode), dipakai hasIzin() lokal.
  final List<Map<String, dynamic>> pengguna;
  final List<Map<String, dynamic>> role;
  final List<Map<String, dynamic>> roleIzin;
  // Modul 10 - pelanggan.poin/totalBelanja berubah di SERVER saja (saat
  // backend memproses transaksi yg di-push, lihat checkout_service.py) -
  // TANPA pull ini, nilai lokal jadi basi selamanya begitu ada transaksi
  // pertama yg melibatkan pelanggan ybs (lihat SyncRepository._terapkanPull).
  final List<Map<String, dynamic>> pelanggan;
  // Tahap 3a Part B - data pendukung lib/core/harga/kalkulator.dart.
  final List<Map<String, dynamic>> hargaOutlet;
  final List<Map<String, dynamic>> hargaGrosir;
  final List<Map<String, dynamic>> tipeOrderPajak;
  final List<Map<String, dynamic>> pengaturanOutlet;
  final Map<String, bool> hasMore;
  // Status gating paket (lihat SyncPullOut.paket/kode_fitur/batas_fitur di
  // backend) - paket=null kalau toko tidak punya langganan aktif sama
  // sekali (dianggap semua fitur tertutup di sisi Flutter).
  final String? paket;
  // Tahap 4 bagian B.4 - lihat LogoCache utk cara dicache lokal supaya
  // tetap bisa dicetak saat offline.
  final String? logoUrl;
  final List<String> kodeFitur;
  final Map<String, int> batasFitur;
}
