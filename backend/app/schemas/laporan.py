import uuid
from datetime import date
from decimal import Decimal

from pydantic import BaseModel


class JamRamaiOut(BaseModel):
    jam: int
    total: Decimal


class MetodeBayarPersenOut(BaseModel):
    metode_bayar_id: uuid.UUID
    nama: str
    total: Decimal
    persen: Decimal


class RingkasanPenjualanOut(BaseModel):
    penjualan_bersih: Decimal
    # Kas diterima (tahap 3b-1) - uang yang BENAR2 masuk selama periode ini
    # (Pembayaran.dibayar_pada di rentang [dari, sampai)), BEDA dari
    # penjualan_bersih yang menghitung NILAI TRANSAKSI yang terjadi di
    # periode ini (termasuk kasbon yang belum/baru sebagian dibayar).
    # Keduanya sengaja bisa berbeda - itu intinya laporan ini.
    kas_diterima: Decimal
    laba_kotor: Decimal
    jumlah_transaksi: int
    rata_rata: Decimal
    jam_ramai: list[JamRamaiOut]
    metode_bayar: list[MetodeBayarPersenOut]


class ProdukTerlarisOut(BaseModel):
    produk_id: uuid.UUID
    nama_produk: str
    qty: Decimal
    total: Decimal


class PiutangPelangganOut(BaseModel):
    pelanggan_id: uuid.UUID
    nama_pelanggan: str
    total_utang: Decimal
    jumlah_transaksi: int
    jatuh_tempo_terdekat: date | None
    lewat_jatuh_tempo: bool
    # Umur piutang (hari sejak jatuh_tempo TERDEKAT, 0 kalau belum lewat) -
    # dikelompokkan sesuai aturan #6: 0-30 / 31-60 / >60 hari.
    umur_hari: int


class LaporanPiutangOut(BaseModel):
    total_piutang: Decimal
    jumlah_pelanggan: int
    jumlah_lewat_jatuh_tempo: int
    pelanggan: list[PiutangPelangganOut]


class LaporanShiftOut(BaseModel):
    shift_id: uuid.UUID
    status: str
    modal_awal: Decimal
    kas_seharusnya: Decimal | None
    kas_aktual: Decimal | None
    selisih: Decimal | None
    jumlah_transaksi: int
    penjualan_bersih: Decimal
    metode_bayar: list[MetodeBayarPersenOut]


class BiayaKategoriOut(BaseModel):
    kategori: str
    total: Decimal


class LabaRugiOut(BaseModel):
    """Laporan laba rugi sederhana (IMOGI no. 69). Pajak/service yang dipungut bukan pendapatan,
    jadi tidak masuk hitungan. `belanja_bahan` ditampilkan terpisah dan TIDAK dikurangkan lagi,
    karena nilai bahan yang terjual sudah ada di HPP (hindari hitung dua kali)."""

    penjualan_kotor: Decimal
    diskon: Decimal
    penjualan_bersih: Decimal
    hpp: Decimal
    laba_kotor: Decimal
    biaya_operasional: list[BiayaKategoriOut]
    total_biaya_operasional: Decimal
    laba_bersih: Decimal
    belanja_bahan: Decimal
    pajak_dipungut: Decimal
    jumlah_transaksi: int
