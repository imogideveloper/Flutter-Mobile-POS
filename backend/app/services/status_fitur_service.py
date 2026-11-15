"""Status pengembangan fitur untuk dashboard Administrator.

Sumber kebenaran: `app/data/status_fitur.json` (kunci = nomor_imogi). Berkas
itu diperbarui di repo setiap fitur selesai dibangun (bersama
docs/gap_imogi.md), lalu `sinkron_status_fitur` menyalinnya ke tabel `fitur`
saat server menyala - jadi dashboard otomatis mengikuti kode yang dirilis,
tanpa edit manual di database. `uji_hp` hanya boleh true bila ada bukti uji
di perangkat (lihat docs/alur_kerja.md): tes otomatis BUKAN bukti."""

import json
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fitur import Fitur

BERKAS_STATUS = Path(__file__).resolve().parent.parent / "data" / "status_fitur.json"
STATUS_VALID = {"belum", "sedang", "sudah", "tidak_relevan"}


def baca_berkas_status(path: Path = BERKAS_STATUS) -> dict[int, dict]:
    mentah = json.loads(path.read_text(encoding="utf-8"))
    hasil: dict[int, dict] = {}
    for nomor, isi in mentah.items():
        if isi.get("status") not in STATUS_VALID:
            raise ValueError(f"Status fitur {nomor} tidak valid: {isi.get('status')!r}")
        hasil[int(nomor)] = isi
    return hasil


async def sinkron_status_fitur(db: AsyncSession, path: Path = BERKAS_STATUS) -> int:
    """Salin status dari berkas ke tabel fitur (berdasarkan nomor_imogi).
    Mengembalikan jumlah fitur yang diperbarui."""
    data = baca_berkas_status(path)
    rows = (await db.execute(select(Fitur).where(Fitur.nomor_imogi.is_not(None)))).scalars().all()
    diperbarui = 0
    for fitur in rows:
        isi = data.get(fitur.nomor_imogi)
        if isi is None:
            continue
        status_baru = isi["status"]
        catatan = isi.get("catatan")
        uji = bool(isi.get("uji_hp", False))
        if (fitur.status_dev, fitur.catatan_dev, fitur.uji_hp) != (status_baru, catatan, uji):
            fitur.status_dev = status_baru
            fitur.catatan_dev = catatan
            fitur.uji_hp = uji
            diperbarui += 1
    await db.commit()
    return diperbarui
