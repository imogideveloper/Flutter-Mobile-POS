import uuid
from datetime import date, datetime
from decimal import Decimal

from typing import Literal

from pydantic import BaseModel, Field


class ModifierPilihIn(BaseModel):
    modifier_id: uuid.UUID | None = None
    nama: str
    harga: Decimal = Decimal("0")


class ItemTransaksiIn(BaseModel):
    produk_id: uuid.UUID
    varian_id: uuid.UUID | None = None
    nama_produk: str
    qty: Decimal
    # harga_satuan/diskon: HANYA dipakai apa adanya utk push OFFLINE
    # (body.id terisi - C.2, ini uang yang benar2 diterima kasir saat
    # transaksi dibuat). Checkout ONLINE SELALU mengabaikan kedua field
    # ini (D.1) - harga/grosir/markup/modifier/promo dihitung ulang
    # server dari database, supaya body tidak bisa memalsukan harga.
    harga_satuan: Decimal
    hpp_satuan: Decimal = Decimal("0")
    # Kalau > 0: diminta sbg DISKON MANUAL (bukan promo) - lihat
    # `CheckoutIn.diskon_manual_disetujui_oleh`. Online ditolak 403 tanpa
    # approval yang sah; push offline tetap disimpan tapi ditandai ke
    # audit_log (D.2-D.3).
    diskon: Decimal = Decimal("0")
    lacak_stok: bool = True
    modifiers: list[ModifierPilihIn] = []


class RincianPajakKlienIn(BaseModel):
    """Temuan#1 (rapikan F3) - satu baris pajak/service yang SUDAH dihitung
    HP lewat lib/core/harga/kalkulator.dart, dikirim HANYA utk push offline
    (body.id terisi). `pajak_id` None/tidak dikenal/bukan milik toko ini ->
    disimpan id NULL + audit_log (lihat checkout_service.py), bukan ditolak -
    uang sudah diterima di HP. Tipe pajak/service TIDAK dikirim di sini -
    disimpulkan dari join ke Pajak.tipe kalau pajak_id valid (sama pola dgn
    checkout_service._ke_checkout_out utk ONLINE)."""

    pajak_id: uuid.UUID | None = None
    nama: str
    persen: Decimal = Decimal("0")
    jumlah: Decimal


class RincianPromoKlienIn(BaseModel):
    """promo_id None dipakai utk diskon member (konvensi sama dgn
    TransaksiPromo.promo_id di jalur ONLINE, lihat checkout_service.py)."""

    promo_id: uuid.UUID | None = None
    nama: str
    jumlah_diskon: Decimal


class SplitPembayaranLineIn(BaseModel):
    """Satu baris pembayaran dlm split payment (tahap fitur F3.A - Kartu/
    Transfer manual). `nomor_referensi`/`empat_digit_akhir_kartu` opsional,
    DILARANG berisi nomor kartu lengkap - disimpan apa adanya di
    Pembayaran.ref_gateway/payload_gateway, tidak divalidasi formatnya."""

    metode_bayar_id: uuid.UUID
    jumlah: Decimal
    nomor_referensi: str | None = None
    empat_digit_akhir_kartu: str | None = None
    # Temuan A.1 (tahap 5) - penanda generik (mis. QRIS statis/manual yang
    # dikonfirmasi kasir sendiri lihat layar HP, BUKAN webhook payment
    # gateway sungguhan: `{"metode": "qris_statis_manual", ...}`). Kalau
    # diisi, MENIMPA payload gabungan dari empat_digit_akhir_kartu di
    # checkout_service.py (bukan gabungan keduanya - satu transaksi/baris
    # cuma satu jenis penanda).
    payload_gateway: dict | None = None


class CheckoutIn(BaseModel):
    # id opsional - kalau diisi (UUID yang sudah dibuat di HP saat offline),
    # dipakai utk idempotency: push ulang transaksi yang sama tidak boleh
    # membuat baris dobel (aturan dokumen #4.3).
    id: uuid.UUID | None = None
    outlet_id: uuid.UUID
    shift_id: uuid.UUID | None = None
    pelanggan_id: uuid.UUID | None = None
    tipe_order_id: uuid.UUID | None = None
    meja_id: uuid.UUID | None = None
    nomor_struk: str
    # Nomor antrian yang dibuat HP sendiri saat offline (format "A-001",
    # lihat lib/features/dapur/data/antrean_repository.dart). Disimpan apa
    # adanya; None = antrian dimatikan / fitur nomor_antrean tidak aktif.
    nomor_antrean: str | None = Field(default=None, max_length=10)
    # Status awal pesanan (None = fitur status pesanan mati di HP).
    status_pesanan: "StatusPesananKode | None" = None
    tanggal: datetime
    items: list[ItemTransaksiIn]
    promo_id: uuid.UUID | None = None
    metode_bayar_id: uuid.UUID
    total_bayar: Decimal
    # Split payment (F3.A) - OPSIONAL. Kosong/None = perilaku lama (satu
    # baris Pembayaran pakai metode_bayar_id+total_bayar di atas). Diisi =
    # beberapa metode sekaligus dlm SATU transaksi (mis. separo tunai,
    # separo kartu) - jumlah SEMUA baris WAJIB persis == total_bayar,
    # masing2 jadi baris Pembayaran terpisah. metode_bayar_id di atas tetap
    # dipakai sbg representatif (mis. utk cek apakah qris dkk - lihat
    # checkout_service) kalau split_pembayaran kosong.
    split_pembayaran: list[SplitPembayaranLineIn] | None = None
    # Temuan A.1 (tahap 5) - penanda generik yang sama dgn
    # SplitPembayaranLineIn.payload_gateway di atas, tapi utk jalur
    # SATU baris Pembayaran (split_pembayaran kosong/None) - lihat
    # checkout_service.py bagian `elif body.total_bayar > 0`.
    payload_gateway: dict | None = None
    # Temuan A.2 (tahap 5) - JSON lengkap StrukData+PengaturanStrukData yang
    # dipakai HP mencetak struk ASLI transaksi ini (lihat
    # lib/core/struk/struk_snapshot.dart) - disimpan APA ADANYA, dipakai
    # utk cetak ulang identik nanti (termasuk dari HP lain lewat
    # GET /transaksi/{id}). None = client lama yang belum kirim snapshot -
    # cetak ulang utk transaksi semacam itu turun ke rekonstruksi dari data
    # saat ini (keterbatasan lama, lihat docs/aturan_harga.md).
    snapshot_struk: dict | None = None
    catatan: str | None = None
    # Tahap 5b - identitas karyawan yang SEBENARNYA login di HP saat
    # transaksi ini dibuat (lihat identitas_service.validasi_dan_tandai).
    # HANYA dipakai jalur PUSH offline (body.id terisi) - checkout ONLINE
    # tetap pakai identitas token (Depends(get_pengguna_id)) apa pun isi
    # field ini, krn utk jalur itu token SUDAH identitas sungguhan.
    pengguna_id: uuid.UUID | None = None
    # pengguna_id yang PIN-nya sudah diverifikasi LOKAL di HP (lihat
    # core/auth/pin_approval.dart di Flutter) dan diklaim punya izin
    # 'transaksi.diskon' - server tetap mengecek ULANG izin user ini
    # sendiri (tidak pernah percaya klaim HP). WAJIB diisi+valid kalau
    # ada item dgn `diskon` > 0, kalau tidak checkout ONLINE ditolak 403
    # (D.2); push offline tidak pernah ditolak tapi ditandai ke
    # audit_log+notifikasi kalau approval-nya tidak sah (D.3).
    diskon_manual_disetujui_oleh: uuid.UUID | None = None
    # Breakdown yang SUDAH dihitung HP sendiri lewat
    # lib/core/harga/kalkulator.dart (mesin yang SAMA dgn server) - HANYA
    # dipakai utk transaksi offline yang di-push (body.id terisi):
    # disimpan APA ADANYA ke kolom transaksi (C.2 - itu uang yang benar2
    # diterima kasir, harus cocok dgn rekonsiliasi kas shift). Server
    # TETAP menghitung ulang dari database, tapi hasilnya CUMA dipakai
    # utk pembanding audit_log (lihat _catat_selisih_harga), tidak pernah
    # menimpa yang tersimpan. Diabaikan sepenuhnya utk checkout ONLINE -
    # server selalu memakai & mengembalikan hasil hitungnya sendiri (C.1).
    # Granularitas GABUNGAN (bukan dipecah diskon_member/diskon_promo
    # atau service/pajak) - sengaja disamakan dgn kolom `transaksi` lokal
    # di Flutter (subtotal/total_diskon/total_pajak/pembulatan/total),
    # yang juga sudah gabungan, bukan dipecah per komponen.
    subtotal_klien: Decimal | None = None
    total_diskon_klien: Decimal | None = None
    total_pajak_klien: Decimal | None = None
    pembulatan_klien: Decimal | None = None
    total_klien: Decimal | None = None
    # Temuan#1 (rapikan F3) - rincian per-baris pajak/service & promo/member
    # yang SUDAH dihitung HP, HANYA dipakai/disimpan utk push offline (sama
    # aturan toleransi dgn field *_klien lain di atas). None/kosong = client
    # lama yang belum kirim rincian - tetap didukung, turun ke satu baris
    # gabungan seperti sebelumnya (lihat checkout_service.py). Diabaikan
    # sepenuhnya utk checkout ONLINE (server selalu pakai hasil hitungnya
    # sendiri, persis field *_klien lain).
    rincian_pajak_klien: list[RincianPajakKlienIn] | None = None
    rincian_promo_klien: list[RincianPromoKlienIn] | None = None
    # Kasbon (tahap 3b-1) - cuma relevan kalau total_bayar < total. Default
    # 7 hari (aturan #4), kasir boleh ubah. Diabaikan kalau transaksi ini
    # dibayar lunas/lebih di awal (tidak ada utang, tidak ada jatuh tempo).
    jatuh_tempo_hari: int | None = None
    # Tukar poin (modul 10) - poin pelanggan ditukar jadi diskon FLAT
    # (poin_ditukar x aturan_poin.nilai_tukar_poin), DIPOTONG DARI TOTAL
    # SETELAH pajak/service (bukan ikut masuk basis hitung pajak lewat
    # kalkulator.py/kalkulator.dart) - diperlakukan spt kredit/voucher yang
    # dicairkan, bukan promo penjualan, supaya tidak perlu mengubah mesin
    # hitung yang dipakai bersama (lihat docs/aturan_harga.md). Wajib
    # pelanggan_id terisi. 0/None = tidak menukar poin sama sekali.
    poin_ditukar: int = 0
    # Nilai Rupiah dari poin_ditukar yang SUDAH dihitung+dipotong HP sendiri
    # (lib/core/harga/kalkulator.dart) - pola *_klien yang sama dgn
    # subtotal_klien dkk: HANYA dipakai/dipercaya utk push offline (C.2,
    # sudah "kejadian" di HP), diabaikan sepenuhnya utk checkout ONLINE
    # (server hitung ulang sendiri dari aturan_poin+pelanggan.poin di DB).
    diskon_poin_klien: Decimal | None = None


class RincianPajakOut(BaseModel):
    nama: str
    persen: Decimal
    jumlah: Decimal


class RincianServiceOut(BaseModel):
    nama: str
    persen: Decimal
    jumlah: Decimal


class CheckoutOut(BaseModel):
    id: uuid.UUID
    nomor_struk: str
    subtotal: Decimal
    diskon_member: Decimal = Decimal("0")
    diskon_promo: Decimal = Decimal("0")
    diskon_poin: Decimal = Decimal("0")
    total_diskon: Decimal
    service: Decimal = Decimal("0")
    rincian_service: list[RincianServiceOut] = []
    total_pajak: Decimal
    rincian_pajak: list[RincianPajakOut]
    pembulatan: Decimal = Decimal("0")
    total: Decimal
    total_bayar: Decimal
    kembalian: Decimal
    status: str
    # Kasbon (tahap 3b-1).
    status_bayar: str = "lunas"
    sisa_tagihan: Decimal = Decimal("0")
    jatuh_tempo: date | None = None


# Tahap status pesanan (alur IMOGI: Baru, Diproses, Siap, (Diantar), Selesai). 'diambil' dipertahankan
# untuk data lama dan dianggap setara 'selesai'.
StatusPesananKode = Literal["baru", "diproses", "siap", "diantar", "selesai", "diambil", "dibatalkan"]


class VoidIn(BaseModel):
    alasan: str


class TransaksiOut(BaseModel):
    id: uuid.UUID
    outlet_id: uuid.UUID
    pelanggan_id: uuid.UUID | None = None
    nomor_struk: str
    nomor_antrean: str | None = None
    tanggal: datetime
    status: str
    subtotal: Decimal
    total_diskon: Decimal
    total_pajak: Decimal
    total: Decimal
    total_bayar: Decimal
    kembalian: Decimal
    alasan_void: str | None
    status_bayar: str = "lunas"
    sisa_tagihan: Decimal = Decimal("0")
    jatuh_tempo: date | None = None
    # Temuan A.2 (tahap 5) - lihat CheckoutIn.snapshot_struk. Dipakai HP
    # LAIN (bukan yang membuat transaksi ini) utk cetak ulang identik,
    # krn transaksi tidak pernah di-pull ke drift lokal device lain.
    snapshot_struk: dict | None = None

    model_config = {"from_attributes": True}


class TransaksiListOut(BaseModel):
    """F3.B - GET /transaksi dgn filter rentang+pagination (limit+1 trick,
    sama pola dgn /sync/pull) - dipakai RiwayatListPage saat perlu data
    lebih lama drpd yang tersimpan lokal."""

    items: list[TransaksiOut]
    has_more: bool
