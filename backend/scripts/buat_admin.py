"""Buat (atau ganti kata sandi) akun Administrator Imogi.

Kata sandi DIKETIK sendiri oleh operator (tidak ditaruh di repo, argumen
perintah, atau riwayat shell). Jalankan di dalam kontainer api:

    docker exec -it backend-api-1 python scripts/buat_admin.py email@contoh.com "Nama Admin"

Bila email sudah terdaftar, kata sandinya diganti dan akun diaktifkan lagi.
"""

import asyncio
import getpass
import sys

from sqlalchemy import func, select

from app.core.db import SessionLocal
from app.core.security import hash_password
from app.models.platform import AkunAdmin


async def main(email: str, nama: str, password: str) -> None:
    email = email.strip().lower()
    async with SessionLocal() as db:
        akun = (await db.execute(select(AkunAdmin).where(func.lower(AkunAdmin.email) == email))).scalar_one_or_none()
        if akun is None:
            db.add(AkunAdmin(email=email, nama=nama.strip(), password_hash=hash_password(password)))
            aksi = "dibuat"
        else:
            akun.password_hash = hash_password(password)
            akun.aktif = True
            aksi = "diperbarui (kata sandi diganti)"
        await db.commit()
    print(f"Akun administrator {email} {aksi}.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit('Pakai: python scripts/buat_admin.py email@contoh.com "Nama Admin"')
    sandi = getpass.getpass("Kata sandi (minimal 10 karakter): ")
    if len(sandi) < 10:
        sys.exit("Kata sandi terlalu pendek (minimal 10 karakter).")
    ulang = getpass.getpass("Ulangi kata sandi: ")
    if sandi != ulang:
        sys.exit("Kata sandi tidak sama.")
    asyncio.run(main(sys.argv[1], sys.argv[2], sandi))
