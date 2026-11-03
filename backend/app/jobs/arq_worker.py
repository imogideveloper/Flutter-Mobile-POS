"""Worker ARQ - job latar belakang via antrean Redis (tech stack #3.2:
rekap, notifikasi, cek langganan tanpa memperlambat API).

Logika sungguhan ada di app/services/jobs_service.py (testable tanpa
Redis) - file ini SENGAJA tipis, cuma pembungkus yang bikin sesi DB
sendiri per job lalu daftarkan ke ARQ cron. TIDAK dites lewat pytest di
sini (butuh Redis sungguhan, tidak ada di sandbox ini) - jalankan
`arq app.jobs.arq_worker.WorkerSettings` di mesin yang punya Redis utk
verifikasi manual sebelum produksi.

Jalankan: `arq app.jobs.arq_worker.WorkerSettings` (sudah disiapkan sbg
service `worker` di docker-compose.yml)."""

from arq import cron
from arq.connections import RedisSettings

from app.core.config import get_settings
from app.core.db import SessionLocal
from app.services.jobs_service import (
    cek_kasbon_jatuh_tempo_dan_notifikasi,
    cek_stok_menipis_dan_notifikasi,
    tandai_langganan_kedaluwarsa,
)


async def job_tandai_langganan_kedaluwarsa(ctx: dict) -> str:
    async with SessionLocal() as db:
        jumlah = await tandai_langganan_kedaluwarsa(db)
    return f"{jumlah} langganan ditandai kedaluwarsa"


async def job_cek_stok_menipis(ctx: dict) -> str:
    async with SessionLocal() as db:
        jumlah = await cek_stok_menipis_dan_notifikasi(db)
    return f"{jumlah} notifikasi stok menipis dibuat"


async def job_cek_kasbon_jatuh_tempo(ctx: dict) -> str:
    async with SessionLocal() as db:
        jumlah = await cek_kasbon_jatuh_tempo_dan_notifikasi(db)
    return f"{jumlah} notifikasi kasbon jatuh tempo dibuat"


class WorkerSettings:
    redis_settings = RedisSettings.from_dsn(get_settings().redis_url)
    cron_jobs = [
        # Tiap jam 01:00 - cukup sekali sehari, status langganan tidak
        # butuh dicek lebih sering dari itu.
        cron(job_tandai_langganan_kedaluwarsa, hour=1, minute=0),
        # Tiap jam, menit ke-0 - stok menipis perlu dicek lebih sering
        # drpd langganan krn bisa berubah kapan saja saat jam operasional.
        cron(job_cek_stok_menipis, minute=0),
        # Harian jam 07:00 (tahap 3b-1 aturan #7) - pagi, sebelum jam
        # operasional toko mulai, supaya owner lihat notifikasi besok
        # jatuh tempo/sudah lewat di awal hari.
        cron(job_cek_kasbon_jatuh_tempo, hour=7, minute=0),
    ]
