"""Penyimpanan file upload (logo toko, dkk) - tahap 4 bagian B.2. S3/R2
kalau `S3_BUCKET` diisi (produksi), kalau kosong (development) disimpan ke
folder lokal `storage/` yang disajikan FastAPI sbg static file (lihat
app/main.py). boto3 itu sinkron (blocking) - dipanggil lewat
`asyncio.to_thread` supaya tidak membekukan event loop, proyek ini belum
punya klien S3 async (aioboto3) sbg dependency."""

import asyncio
import uuid
from pathlib import Path

from fastapi import HTTPException, UploadFile, status

from app.core.config import get_settings

_MAKS_UKURAN_BYTES = 1 * 1024 * 1024  # 1 MB
_MAGIC_PNG = b"\x89PNG\r\n\x1a\n"
_MAGIC_JPEG = b"\xff\xd8\xff"

# Relatif ke working directory proses (lihat README backend - semua path
# lain di proyek ini juga relatif, mis. database_url sqlite). Boleh
# dioverride via STORAGE_DIR kalau perlu nanti - sengaja konstanta sederhana
# dulu, tidak semua hal perlu jadi Settings field.
LOCAL_STORAGE_DIR = Path("storage")


def _deteksi_ekstensi(konten: bytes) -> str:
    """Sniffing magic bytes, BUKAN percaya Content-Type header dari klien
    (bisa dipalsukan) - sama alasan kenapa validasi upload umumnya tidak
    boleh cuma bersandar pada header."""

    if konten.startswith(_MAGIC_PNG):
        return "png"
    if konten.startswith(_MAGIC_JPEG):
        return "jpg"
    raise HTTPException(status.HTTP_400_BAD_REQUEST, "File harus berupa PNG atau JPG")


async def simpan_logo_toko(toko_id: uuid.UUID, file: UploadFile) -> str:
    konten = await file.read()
    if len(konten) > _MAKS_UKURAN_BYTES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Ukuran file maksimal 1 MB")
    if not konten:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "File kosong")

    ekstensi = _deteksi_ekstensi(konten)
    nama_file = f"{toko_id}-{uuid.uuid4().hex[:8]}.{ekstensi}"

    settings = get_settings()
    if settings.s3_bucket:
        return await asyncio.to_thread(_simpan_ke_s3, nama_file, konten, ekstensi)
    return _simpan_lokal(nama_file, konten)


def _simpan_ke_s3(nama_file: str, konten: bytes, ekstensi: str) -> str:
    import boto3  # import lokal - supaya modul ini tetap bisa diimpor di test tanpa boto3 dipanggil sama sekali saat S3_BUCKET kosong

    settings = get_settings()
    content_type = "image/png" if ekstensi == "png" else "image/jpeg"
    client = boto3.client(
        "s3", region_name=settings.s3_region, endpoint_url=settings.s3_endpoint_url
    )
    key = f"logo/{nama_file}"
    client.put_object(
        Bucket=settings.s3_bucket, Key=key, Body=konten, ContentType=content_type, ACL="public-read"
    )
    if settings.s3_endpoint_url:
        return f"{settings.s3_endpoint_url.rstrip('/')}/{settings.s3_bucket}/{key}"
    return f"https://{settings.s3_bucket}.s3.{settings.s3_region}.amazonaws.com/{key}"


def _simpan_lokal(nama_file: str, konten: bytes) -> str:
    folder = LOCAL_STORAGE_DIR / "logo"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / nama_file).write_bytes(konten)
    return f"/static/logo/{nama_file}"
