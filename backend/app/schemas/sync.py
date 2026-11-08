import uuid
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel

from app.schemas.transaksi import CheckoutIn, StatusPesananKode


class PelangganPushIn(BaseModel):
    id: uuid.UUID
    nama: str
    no_hp: str | None = None
    email: str | None = None
    catatan: str | None = None


class ShiftPushIn(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID
    dibuka_pada: datetime
    ditutup_pada: datetime | None = None
    modal_awal: Decimal = Decimal("0")
    kas_seharusnya: Decimal | None = None
    kas_aktual: Decimal | None = None
    selisih: Decimal | None = None
    catatan: str | None = None
    status: str = "buka"
    # Tahap 5b - karyawan yang SEBENARNYA buka/tutup shift ini di HP (lihat
    # CheckoutIn.pengguna_id utk alasan lengkap). None = fallback ke
    # identitas token (perilaku lama).
    pengguna_id: uuid.UUID | None = None


class KasShiftPushIn(BaseModel):
    id: uuid.UUID
    shift_id: uuid.UUID
    jenis: str
    jumlah: Decimal
    keterangan: str
    pengguna_id: uuid.UUID | None = None


class PembayaranPushIn(BaseModel):
    # Cicilan/pelunasan kasbon yang dicatat offline di HP (tahap 3b-1
    # aturan #3) - `id` WAJIB (bukan opsional spt PembayaranIn umum) krn
    # jalur push selalu berarti "ini sudah terjadi di HP", sama pola dgn
    # ShiftPushIn/KasShiftPushIn. `transaksi_id` wajib di body (beda dari
    # endpoint langsung yang ambil dari path).
    id: uuid.UUID
    transaksi_id: uuid.UUID
    shift_id: uuid.UUID
    metode_bayar_id: uuid.UUID
    jumlah: Decimal
    dibayar_pada: datetime | None = None
    # Temuan A.1 (tahap 5) - lihat PembayaranIn.payload_gateway.
    payload_gateway: dict | None = None
    # Tahap 5b - karyawan yang mencatat cicilan/pelunasan ini di HP.
    pengguna_id: uuid.UUID | None = None


class PesananBatalPushIn(BaseModel):
    """Temuan#2 (rapikan F3.E) - pembatalan pesanan tersimpan yang terjadi
    SAAT OFFLINE, dikirim belakangan lewat /sync/push. `id` = id pesanan
    (transaksi status='tersimpan') yang dibatalkan - WAJIB, sama pola dgn
    push lain (ShiftPushIn dkk)."""

    id: uuid.UUID
    alasan: str
    disetujui_oleh: uuid.UUID | None = None
    # Tahap 5b - karyawan yang MEMINTA pembatalan (beda dari
    # disetujui_oleh = approver kalau butuh approval). None = fallback ke
    # identitas token.
    pengguna_id: uuid.UUID | None = None


class StatusPesananPushIn(BaseModel):
    """Perubahan status pesanan yang terjadi di HP SETELAH transaksinya tersync
    (jadi tidak ikut payload checkout). `id` = id transaksi."""

    id: uuid.UUID
    status: StatusPesananKode


class SyncPushIn(BaseModel):
    perangkat_id: uuid.UUID
    transaksi: list[CheckoutIn] = []
    shift: list[ShiftPushIn] = []
    kas_shift: list[KasShiftPushIn] = []
    pelanggan: list[PelangganPushIn] = []
    pembayaran: list[PembayaranPushIn] = []
    pesanan_batal: list[PesananBatalPushIn] = []
    status_pesanan: list[StatusPesananPushIn] = []


class HasilItemPush(BaseModel):
    id: uuid.UUID
    status: str  # "diterima" | "sudah_ada" | "ditolak"
    pesan: str | None = None


class SyncPushOut(BaseModel):
    transaksi: list[HasilItemPush]
    shift: list[HasilItemPush]
    kas_shift: list[HasilItemPush]
    pelanggan: list[HasilItemPush]
    pembayaran: list[HasilItemPush]
    pesanan_batal: list[HasilItemPush]
    status_pesanan: list[HasilItemPush] = []


class SyncPullOut(BaseModel):
    waktu_pull: datetime
    produk: list[dict]
    kategori: list[dict]
    satuan: list[dict]
    pajak: list[dict]
    promo: list[dict]
    metode_bayar: list[dict]
    pelanggan: list[dict]
    pengguna: list[dict]
    role: list[dict]
    # Tahap 5b (desain #2) - karyawan=baris pengguna server; `pin_hash` di
    # sini WAJIB hash kuat (bcrypt, lihat core/security.py), TIDAK PERNAH
    # PIN mentah. `role_izin` relasi murni (tanpa updated_at, sama pola
    # dgn tipe_order_pajak) - snapshot PENUH tiap pull, dipakai device
    # menghitung izin efektif per pengguna.role_id TANPA perlu tabel
    # master `izin` terpisah (kode izin sudah diresolve di sini).
    role_izin: list[dict]
    # Katalog varian/tambahan produk (dokumen IMOGI no. 42). grup_modifier dan
    # modifier = delta by updated_at; produk_grup_modifier = relasi murni, snapshot
    # PENUH tiap pull (device mengganti seluruh isinya). Default [] supaya client
    # lama tidak terpengaruh.
    grup_modifier: list[dict] = []
    modifier: list[dict] = []
    produk_grup_modifier: list[dict] = []
    stok: list[dict]
    # Tahap 3a Part B - data yang dibutuhkan lib/core/harga/kalkulator.dart
    # di HP supaya keranjang bisa hitung grosir/harga per-outlet/service
    # per tipe pesanan/pembulatan SENDIRI (bukan harga datar), sama
    # persis dgn mesin yang dipakai server (docs/aturan_harga.md).
    harga_outlet: list[dict]
    harga_grosir: list[dict]
    # tipe_order_pajak & pengaturan_outlet TIDAK punya kolom updated_at
    # (tabel relasi murni / baris tunggal kecil) - selalu snapshot PENUH
    # tiap pull (bukan delta `since`), bukan bug.
    tipe_order_pajak: list[dict]
    pengaturan_outlet: list[dict]
    # Kode fitur yang terbuka utk paket toko ini saat ini (aturan dokumen
    # #4.2) - app simpan ini lokal & cek lewat featureGate.has(kode).
    # Dikirim tiap pull (bukan cuma ikut updated_at) krn baris paket_fitur
    # tidak punya kolom per-toko yang bisa dibandingkan `since`.
    paket: str | None
    # URL logo toko saat ini (tahap 4 bagian B.4) - sama alasan dgn paket:
    # baris `toko` tidak punya watermark per-field yang bisa dibandingkan
    # `since`, jadi dikirim snapshot tiap pull, bukan delta.
    logo_url: str | None
    kode_fitur: list[str]
    # Batas (mis. hari utk laporan_dasar) per kode fitur YANG PUNYA batas
    # di paket toko ini saat ini - fitur tanpa batas (termasuk yang tidak
    # terbuka sama sekali) TIDAK muncul di sini. App lokal pakai ini utk
    # tahu "fitur X terbuka tapi dibatasi N" (lihat FeatureGate.batas() di
    # sisi Flutter), bukan cuma terbuka/tertutup.
    batas_fitur: dict[str, int]
    # Per tabel (bukan gabungan) - True kalau masih ada sisa data yang
    # belum terkirim krn kena `limit`. Client pull ulang dgn `since` =
    # updated_at baris TERAKHIR yang diterima utk tabel yang masih True.
    has_more: dict[str, bool]
