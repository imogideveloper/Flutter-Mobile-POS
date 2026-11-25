"""Bagan akun (Chart of Accounts) standar untuk usaha F&B skala UMKM (IMOGI no. 80, tahap 1).

Keputusan lead (MoM 2026-11-25): pencatatan beban (sewa, listrik, dll.) cukup lewat layar Pengeluaran yang sudah
ada; yang disiapkan adalah CoA standarnya. Jadi tahap ini HANYA daftar akun tetap (sama untuk semua toko, tidak bisa
diubah dari aplikasi) dan pemetaan kategori pengeluaran serta baris ekspor ke akun tersebut. Jurnal umum, buku besar,
dan neraca (no. 80 bagian jurnal, no. 81) belum dibangun.

Penomoran mengikuti pola umum (1 aset, 2 kewajiban, 3 ekuitas, 4 pendapatan, 5 HPP, 6 beban usaha, 7 beban lain).
Daftar ini usulan awal; perlu ditinjau akuntan sebelum dipakai untuk laporan resmi."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Akun:
    kode: str
    nama: str
    kelompok: str  # aset|kewajiban|ekuitas|pendapatan|hpp|beban|beban_lain
    saldo_normal: str  # debit|kredit


AKUN_STANDAR: tuple[Akun, ...] = (
    Akun("1-1100", "Kas", "aset", "debit"),
    Akun("1-1200", "Bank & dompet digital", "aset", "debit"),
    Akun("1-1300", "Piutang usaha (kasbon pelanggan)", "aset", "debit"),
    Akun("1-1400", "Persediaan bahan baku", "aset", "debit"),
    Akun("1-1500", "Persediaan kemasan", "aset", "debit"),
    Akun("1-1600", "Biaya dibayar di muka", "aset", "debit"),
    Akun("1-2100", "Peralatan & perlengkapan usaha", "aset", "debit"),
    Akun("1-2200", "Akumulasi penyusutan peralatan", "aset", "kredit"),
    Akun("2-1100", "Utang usaha (pemasok)", "kewajiban", "kredit"),
    Akun("2-1200", "Utang pajak (PB1/PPN dan service dipungut)", "kewajiban", "kredit"),
    Akun("2-1300", "Pendapatan diterima di muka (deposit pelanggan)", "kewajiban", "kredit"),
    Akun("2-1400", "Utang gaji", "kewajiban", "kredit"),
    Akun("3-1000", "Modal pemilik", "ekuitas", "kredit"),
    Akun("3-2000", "Prive", "ekuitas", "debit"),
    Akun("3-3000", "Laba ditahan", "ekuitas", "kredit"),
    Akun("4-1000", "Penjualan makanan & minuman", "pendapatan", "kredit"),
    Akun("4-2000", "Diskon penjualan", "pendapatan", "debit"),
    Akun("4-9000", "Pendapatan lain-lain", "pendapatan", "kredit"),
    Akun("5-1000", "HPP bahan baku", "hpp", "debit"),
    Akun("5-1100", "HPP kemasan", "hpp", "debit"),
    Akun("6-1000", "Beban gaji & upah", "beban", "debit"),
    Akun("6-1100", "Beban sewa", "beban", "debit"),
    Akun("6-1200", "Beban listrik & air", "beban", "debit"),
    Akun("6-1300", "Beban gas LPG", "beban", "debit"),
    Akun("6-1400", "Beban pemasaran", "beban", "debit"),
    Akun("6-1500", "Beban perawatan & perbaikan", "beban", "debit"),
    Akun("6-1600", "Beban penyusutan", "beban", "debit"),
    Akun("6-1700", "Beban administrasi bank & MDR", "beban", "debit"),
    Akun("6-9000", "Beban lain-lain", "beban", "debit"),
    Akun("7-1000", "Beban pajak penghasilan (PPh Final)", "beban_lain", "debit"),
)

AKUN_PER_KODE: dict[str, Akun] = {a.kode: a for a in AKUN_STANDAR}

# Kategori pengeluaran (models/pengeluaran.py KATEGORI_PENGELUARAN) ke akun beban/HPP.
AKUN_KATEGORI_PENGELUARAN: dict[str, str] = {
    "belanja_bahan": "5-1000",
    "kemasan": "5-1100",
    "gas_lpg": "6-1300",
    "gaji": "6-1000",
    "sewa": "6-1100",
    "listrik_air": "6-1200",
    "pemasaran": "6-1400",
    "perawatan": "6-1500",
    "lainnya": "6-9000",
}

# Jenis baris ekspor akuntansi (routers/ekspor_akuntansi.py) yang akunnya tetap.
AKUN_JENIS_EKSPOR: dict[str, str] = {
    "penjualan_bersih": "4-1000",
    "pajak_dipungut": "2-1200",
    "hpp": "5-1000",
}


def akun_untuk_baris_ekspor(jenis: str, rincian: str) -> Akun | None:
    """Akun usulan untuk satu baris ekspor. Penerimaan tunai ke Kas, metode lain ke Bank & dompet digital."""
    if jenis in AKUN_JENIS_EKSPOR:
        return AKUN_PER_KODE[AKUN_JENIS_EKSPOR[jenis]]
    if jenis == "biaya":
        kode = AKUN_KATEGORI_PENGELUARAN.get(rincian)
        return AKUN_PER_KODE[kode] if kode else None
    if jenis == "penerimaan":
        return AKUN_PER_KODE["1-1100" if "tunai" in rincian.lower() else "1-1200"]
    return None
