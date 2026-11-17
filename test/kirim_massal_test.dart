import 'package:apps_pos/core/providers/toko_profile_provider.dart';
import 'package:apps_pos/features/pelanggan/domain/kirim_massal.dart';
import 'package:apps_pos/features/pelanggan/domain/pelanggan.dart';
import 'package:apps_pos/features/pelanggan/presentation/pages/kirim_massal_page.dart';
import 'package:apps_pos/features/pelanggan/presentation/providers/pelanggan_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Pelanggan _p(String id, String nama, String? hp, {String? level}) => Pelanggan(
      id: id,
      tokoId: 't1',
      nama: nama,
      noHp: hp,
      levelMemberId: level,
      poin: 0,
      totalBelanja: 0,
    );

void main() {
  group('nomorWhatsApp', () {
    test('menormalkan ke format 62 dan menolak nomor yang tidak masuk akal', () {
      expect(nomorWhatsApp('0812-3456-7890'), '6281234567890');
      expect(nomorWhatsApp('+62 812 3456 7890'), '6281234567890');
      expect(nomorWhatsApp('6281234567890'), '6281234567890');
      expect(nomorWhatsApp('12'), isNull);
      expect(nomorWhatsApp(''), isNull);
      expect(nomorWhatsApp(null), isNull);
      expect(nomorWhatsApp('0123456789012345678'), isNull);
    });
  });

  group('kandidatPenerima', () {
    final semua = [
      _p('1', 'Budi', '081234567890', level: 'gold'),
      _p('2', 'Sari', '081298765432', level: 'silver'),
      _p('3', 'Tanpa HP', null),
      _p('4', 'Budi Dobel', '+6281234567890', level: 'gold'),
      _p('5', 'Nomor Rusak', '12'),
    ];

    test('hanya yang punya nomor sah; nomor yang sama muncul sekali', () {
      expect(kandidatPenerima(semua).map((p) => p.id), ['1', '2']);
    });

    test('saring per level dan kata cari (nama atau nomor)', () {
      expect(kandidatPenerima(semua, levelMemberId: 'silver').map((p) => p.id), ['2']);
      expect(kandidatPenerima(semua, kataCari: 'sar').map((p) => p.id), ['2']);
      expect(kandidatPenerima(semua, kataCari: '1234567').map((p) => p.id), ['1']);
    });
  });

  group('isiPesanMassal', () {
    test('mengganti {nama} dan {toko}; nama kosong menjadi Kak', () {
      expect(isiPesanMassal('Halo {nama}, promo di {toko}!', namaPelanggan: 'Budi', namaToko: 'Kopi Kita'),
          'Halo Budi, promo di Kopi Kita!');
      expect(isiPesanMassal('Halo {nama}', namaPelanggan: '  '), 'Halo Kak');
      expect(isiPesanMassal('Di {toko} ya', namaPelanggan: 'A'), 'Di  ya');
    });
  });

  testWidgets('halaman: pilih penerima, pratinjau per orang, lewati sampai selesai', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pelangganAktifProvider.overrideWith(
          (ref) => Stream.value([_p('1', 'Budi', '081234567890'), _p('2', 'Sari', '081298765432'), _p('3', 'Tanpa HP', null)]),
        ),
        levelMemberProvider.overrideWith((ref) => Stream.value(const <LevelMember>[])),
        tokoProfileProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: KirimMassalPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kirimMassal.baris.3')), findsNothing, reason: 'tanpa nomor tidak ditawarkan');
    expect(tester.widget<FilledButton>(find.byKey(const Key('kirimMassal.mulai'))).onPressed, isNull,
        reason: 'belum ada penerima dipilih');

    await tester.tap(find.byKey(const Key('kirimMassal.pilihSemua')));
    await tester.pump();
    expect(find.text('Mulai kirim (2)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kirimMassal.mulai')));
    await tester.pumpAndSettle();
    expect(find.text('Pesan 1 dari 2'), findsOneWidget);
    expect(find.text('Budi'), findsOneWidget);
    expect(find.byKey(const Key('kirimMassal.pratinjau')), findsOneWidget);
    expect((tester.widget<Text>(find.byKey(const Key('kirimMassal.pratinjau')))).data, 'Halo Budi,');

    await tester.tap(find.byKey(const Key('kirimMassal.lewati')));
    await tester.pumpAndSettle();
    expect(find.text('Pesan 2 dari 2'), findsOneWidget);
    expect(find.text('Sari'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kirimMassal.lewati')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kirimMassal.selesai')), findsOneWidget);

    await tester.tap(find.byKey(const Key('kirimMassal.selesai')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kirimMassal.mulai')), findsOneWidget, reason: 'kembali ke persiapan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
