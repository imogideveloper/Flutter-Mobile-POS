"""Baca/tulis pengaturan tingkat platform (tabel pengaturan_platform)."""

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.platform import PengaturanPlatform

# Lama masa trial berdasarkan usia akun toko, dalam bulan. 0 atau kunci
# tidak ada = masa trial mati (perilaku lama: paket berlaku sejak hari
# pertama). Migrasi 0009 mengisi 4 di database produksi/dev.
KUNCI_USIA_AKUN_BULAN = "usia_akun_bulan"
# Berapa hari sebelum trial berakhir notifikasi dikirim.
KUNCI_TRIAL_NOTIFIKASI_HARI = "trial_notifikasi_hari"
DEFAULT_TRIAL_NOTIFIKASI_HARI = 7


async def ambil_int(db: AsyncSession, kunci: str, default: int) -> int:
    baris = await db.get(PengaturanPlatform, kunci)
    if baris is None:
        return default
    try:
        return int(baris.nilai)
    except ValueError:
        return default


async def simpan_int(db: AsyncSession, kunci: str, nilai: int) -> None:
    baris = await db.get(PengaturanPlatform, kunci)
    if baris is None:
        db.add(PengaturanPlatform(kunci=kunci, nilai=str(nilai)))
    else:
        baris.nilai = str(nilai)
    await db.commit()
