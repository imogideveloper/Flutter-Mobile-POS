import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel


class PaketOut(BaseModel):
    """F3.F.1 - dipakai tabel perbandingan fitur Gratis/Pro/Bisnis di
    halaman Paket langganan - dari tabel paket+paket_fitur SUNGGUHAN,
    bukan hardcode di Flutter."""

    id: uuid.UUID
    nama: str
    urutan: int
    harga_bulanan: Decimal
    harga_tahunan: Decimal | None
    maks_outlet: int | None
    maks_pengguna: int | None
    maks_produk: int | None
    kode_fitur: list[str]


class PemakaianOut(BaseModel):
    outlet: int
    pengguna: int
    produk: int


class LanggananSayaOut(BaseModel):
    paket_id: uuid.UUID
    paket_nama: str
    status: str
    periode: str
    jumlah_outlet: int
    mulai: datetime
    berakhir: datetime | None
    pemakaian: PemakaianOut
    # Masa trial berdasarkan usia akun (arahan lead 2026-11-08). Selama
    # trial_aktif, `paket_efektif_nama` (paket yang BENAR-BENAR berlaku)
    # lebih tinggi dari `paket_nama` (paket langganan tercatat).
    paket_efektif_nama: str | None = None
    trial_aktif: bool = False
    trial_mulai: datetime | None = None
    trial_berakhir: datetime | None = None
    trial_durasi_bulan: int | None = None
    trial_hari_tersisa: int | None = None
    trial_notifikasi_hari: int = 7


class PermintaanUpgradeIn(BaseModel):
    paket_tujuan_id: uuid.UUID
    jumlah_outlet: int = 1
    periode: str = "bulanan"
    catatan: str | None = None


class PermintaanUpgradeOut(BaseModel):
    id: uuid.UUID
    paket_tujuan_id: uuid.UUID
    jumlah_outlet: int
    periode: str
    status: str

    model_config = {"from_attributes": True}


class CheckoutUpgradeOut(BaseModel):
    """Dibalas begitu invoice Xendit berhasil dibuat - app buka
    `invoice_url` (browser/webview), lalu poll
    GET /langganan/checkout-upgrade/{id}/status setelah user kembali."""

    id: uuid.UUID
    invoice_url: str | None
    jumlah_bayar: Decimal | None
    status: str


class StatusCheckoutOut(BaseModel):
    status: str


class VaCheckoutIn(PermintaanUpgradeIn):
    bank_code: str  # key pendek: "bca"|"bni"|"bri"|"mandiri"|"permata" (lihat BANK_VA_DIDUKUNG)


class QrisCheckoutOut(BaseModel):
    """QR dirender LANGSUNG di app (package qr_flutter), tidak pernah
    keluar ke browser - lihat catatan sandbox di xendit_service.py.buat_qris."""

    id: uuid.UUID
    qr_string: str
    jumlah_bayar: Decimal
    status: str


class VaCheckoutOut(BaseModel):
    id: uuid.UUID
    bank_code: str
    nomor_va: str
    jumlah_bayar: Decimal
    status: str


class AdminAktivasiLangganan(BaseModel):
    """F3.F.3 - endpoint admin (API key, bukan JWT toko)."""

    toko_id: uuid.UUID
    paket_id: uuid.UUID
    jumlah_outlet: int = 1
    periode: str = "bulanan"
    # None = tidak kedaluwarsa (langganan tahunan/manual tanpa batas
    # eksplisit) - admin yang menentukan, bukan dihitung otomatis dari
    # periode di sini (aktivasi manual, bukan billing otomatis).
    berakhir: datetime | None = None
