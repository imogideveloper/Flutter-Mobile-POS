import 'package:apps_pos/core/providers/device_pairing_provider.dart';
import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Penyimpanan aman palsu di memori: cukup read/write/delete yang dipakai profil usaha.
class _PenyimpananMemori implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final nama = invocation.memberName;
    final key = invocation.namedArguments[#key] as String?;
    if (nama == #write) {
      data[key!] = invocation.namedArguments[#value] as String;
      return Future<void>.value();
    }
    if (nama == #read) return Future<String?>.value(data[key]);
    if (nama == #delete) {
      data.remove(key);
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Bug: nama usaha lama menempel setelah masuk atau mendaftar usaha lain di HP yang sama. Profil harus
/// ditimpa saat usaha berikutnya masuk dan dihapus saat keluar dari usaha.
void main() {
  testWidgets('profil usaha ditimpa usaha berikutnya dan terhapus saat keluar dari usaha', (tester) async {
    final penyimpanan = _PenyimpananMemori();
    late WidgetRef refUji;
    await tester.pumpWidget(ProviderScope(
      overrides: [secureStorageProvider.overrideWithValue(penyimpanan)],
      child: Consumer(builder: (context, ref, _) {
        refUji = ref;
        return const SizedBox();
      }),
    ));

    await simpanTokoProfile(refUji, namaToko: 'Aaaa', jenisUsaha: JenisUsaha.kafe, namaPemilik: 'Nurul');
    expect((await refUji.read(tokoProfileProvider.future))?.namaToko, 'Aaaa');

    // Usaha lain masuk di HP yang sama: nama harus berganti, jenis usaha ikut.
    await simpanTokoProfile(refUji, namaToko: 'Roti Sari', jenisUsaha: JenisUsaha.roti, namaPemilik: 'Budi');
    final baru = await refUji.read(tokoProfileProvider.future);
    expect(baru?.namaToko, 'Roti Sari');
    expect(baru?.jenisUsaha, JenisUsaha.roti);
    expect(baru?.namaPemilik, 'Budi');

    await hapusTokoProfile(refUji);
    expect(await refUji.read(tokoProfileProvider.future), isNull);
    expect(penyimpanan.data, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
