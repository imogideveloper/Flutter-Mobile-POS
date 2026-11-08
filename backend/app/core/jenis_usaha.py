"""Jenis usaha yang didukung: modul Makanan & Minuman dari dokumen IMOGI
(IMOGI POS Menu & Fitur, 5 Nov 2026). Kode 3 huruf = kode jenis usaha di
dokumen itu, dipakai sebagai kontrak dengan dashboard. Disimpan di
`toko.jenis_usaha`."""

JENIS_USAHA_FNB: dict[str, str] = {
    "CAF": "Kafe & Kedai Kopi",
    "RES": "Restoran",
    "CAT": "Katering",
    "BRD": "Roti, Kue & Camilan",
    "FRZ": "Bahan Segar & Makanan Beku",
    "BEV": "Minuman",
    "STL": "Kios & Food Court",
}

# Dipakai bila pendaftar tidak mengisi jenis usaha (klien lama).
JENIS_USAHA_DEFAULT = "CAF"


def normalisasi_jenis_usaha(nilai: str | None) -> str:
    """Kode valid (huruf besar/kecil diabaikan) atau default. Nilai lama dari
    aplikasi versi sebelumnya ('fnb') dianggap Kafe & Kedai Kopi. Nilai tidak
    dikenal ditolak oleh validator skema, bukan di sini."""
    if nilai is None or nilai.strip() == "":
        return JENIS_USAHA_DEFAULT
    kode = nilai.strip().upper()
    if kode == "FNB":
        return JENIS_USAHA_DEFAULT
    return kode
