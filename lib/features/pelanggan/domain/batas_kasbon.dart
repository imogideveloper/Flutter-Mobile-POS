/// Aturan limit bon (IMOGI no. 16): total utang pelanggan setelah bon baru
/// tidak boleh melebihi `batas_kasbon` (kosong/null = tanpa batas).
/// Murni, dipakai kasir di HP sebelum menyimpan bon. Server tetap menerima
/// push offline yang melampaui batas (lihat checkout_service).
class HasilBatasKasbon {
  const HasilBatasKasbon({required this.boleh, required this.sisaKuota});

  final bool boleh;

  /// Sisa kuota bon sebelum bon baru; null bila tanpa batas.
  final int? sisaKuota;
}

HasilBatasKasbon cekBatasKasbon({
  required int? batas,
  required int utangSekarang,
  required int sisaTagihanBaru,
}) {
  if (batas == null) return const HasilBatasKasbon(boleh: true, sisaKuota: null);
  final kuota = batas - utangSekarang;
  return HasilBatasKasbon(
    boleh: utangSekarang + sisaTagihanBaru <= batas,
    sisaKuota: kuota < 0 ? 0 : kuota,
  );
}
