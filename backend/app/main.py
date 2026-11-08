from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

import app.models  # noqa: F401 - registrasi semua tabel ke Base.metadata
from app.core.config import get_settings
from app.routers import (
    admin_langganan,
    admin_platform,
    audit,
    auth,
    fitur,
    langganan,
    laporan,
    order,
    outlet,
    payment_xendit,
    pelanggan,
    pembelian,
    pengguna,
    penjualan_setup,
    pesanan_tersimpan,
    produk,
    produk_lanjutan,
    shift,
    stok_opname,
    sync,
    toko,
    transaksi,
    transfer_stok,
)

settings = get_settings()

app = FastAPI(title=settings.app_name)

# Logo toko (tahap 4 bagian B.2) saat S3_BUCKET kosong (development) -
# disajikan dari folder lokal `storage/` (lihat storage_service.py).
# check_dir=False supaya startup tidak gagal kalau foldernya belum ada
# (baru dibuat saat upload pertama).
app.mount("/static", StaticFiles(directory="storage", check_dir=False), name="static")

app.include_router(auth.router)
app.include_router(toko.router)
app.include_router(outlet.router)
app.include_router(produk.router)
app.include_router(produk_lanjutan.router)
app.include_router(pelanggan.router)
app.include_router(pengguna.router)
app.include_router(penjualan_setup.router)
app.include_router(shift.router)
# WAJIB sebelum transaksi.router - route transaksi.py punya
# GET/DELETE /transaksi/{transaksi_id} yang kalau didaftar lebih dulu akan
# "menelan" /transaksi/pesanan-tersimpan sbg path param (urutan registrasi
# menentukan prioritas match di FastAPI/Starlette).
app.include_router(pesanan_tersimpan.router)
app.include_router(transaksi.router)
app.include_router(sync.router)
app.include_router(laporan.router)
app.include_router(fitur.router)
app.include_router(order.router)
app.include_router(pembelian.router)
app.include_router(stok_opname.router)
app.include_router(transfer_stok.router)
app.include_router(audit.router)
app.include_router(langganan.router)
app.include_router(admin_langganan.router)
app.include_router(admin_platform.router)
app.include_router(payment_xendit.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
