"""Sync push (HP -> server) & pull (server -> HP), sesuai aturan dokumen
#4.3:
  - Push: transaksi, shift, kas_shift, pelanggan baru - per batch,
    idempotent berdasarkan UUID (baris yang id-nya sudah ada tidak
    diproses ulang, bukan error).
  - Pull: data master yang updated_at > waktu sync terakhir, TERMASUK
    baris berstatus deleted_at (supaya HP tahu harus menghapus lokal).
  - Konflik: transaksi selalu diterima (barang sudah keluar - lewat
    checkout_service yang sudah idempotent & boleh stok minus). Untuk
    data master (pull), server yang menang - HP tidak pernah push
    update ke produk/pajak/dkk, hanya pull.
"""

import uuid
from datetime import UTC, datetime
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.akun import AksesOutlet, Izin, Pengguna, Role, RoleIzin
from app.models.audit import SyncLog
from app.models.order import TipeOrder, TipeOrderPajak
from app.models.outlet import PengaturanOutlet, Perangkat, Toko
from app.models.pelanggan import Pelanggan
from app.models.produk import HargaGrosir, HargaOutlet, Kategori, Produk, Satuan
from app.models.promo import Pajak, Promo
from app.models.stok import Stok
from app.models.transaksi import KasShift, MetodeBayar, Pembayaran, Shift, Transaksi
from app.schemas.pembayaran import PembayaranIn
from app.schemas.sync import (
    HasilItemPush,
    KasShiftPushIn,
    PelangganPushIn,
    PembayaranPushIn,
    ShiftPushIn,
    SyncPullOut,
    SyncPushIn,
    SyncPushOut,
)
from app.core.deps import require_outlet_access
from app.services.checkout_service import checkout as checkout_service
from app.services.fitur_service import kode_fitur_toko, paket_efektif, semua_batas_fitur_toko
from app.services.identitas_service import validasi_dan_tandai
from app.services.kepemilikan import get_outlet_milik_toko
from app.services.pembayaran_service import catat_pembayaran
from app.services.pesanan_tersimpan_service import batalkan_pesanan_tersimpan
from app.services.shift_service import hitung_kas_seharusnya


async def _ambil_perangkat_milik_toko(db: AsyncSession, perangkat_id: uuid.UUID, toko_id: uuid.UUID) -> Perangkat:
    perangkat = await db.get(Perangkat, perangkat_id)
    if perangkat is None or perangkat.toko_id != toko_id:
        raise HTTPException(404, "Perangkat tidak ditemukan/tidak terdaftar ke toko ini")
    return perangkat


async def _tolak_item(db: AsyncSession, item_id: uuid.UUID | None, pesan: str) -> HasilItemPush:
    """Dipanggil setelah sebuah item push gagal (HTTPException ATAU
    IntegrityError, mis. dua device push id yang sama hampir bersamaan) -
    rollback WAJIB sebelum lanjut ke item berikutnya dalam session yang
    sama, supaya satu item bentrok tidak membuat seluruh batch gagal 500
    atau mewarisi transaction yang sudah rusak ke item setelahnya."""

    await db.rollback()
    return HasilItemPush(id=item_id or uuid.uuid4(), status="ditolak", pesan=pesan)


async def push(
    db: AsyncSession, *, toko_id: uuid.UUID, pengguna_id: uuid.UUID, role_id: uuid.UUID, body: SyncPushIn
) -> SyncPushOut:
    perangkat = await _ambil_perangkat_milik_toko(db, body.perangkat_id, toko_id)
    perangkat_id = perangkat.id  # disalin ke variabel polos - lihat catatan di bawah
    mulai = datetime.now(UTC)
    perangkat.terakhir_sync = mulai
    await db.commit()

    # perangkat_id disalin SEBELUM loop krn _tolak_item() bisa rollback()
    # session ini - rollback mengosongkan (expire) objek `perangkat`, dan
    # async SQLAlchemy TIDAK BISA lazy-load atribut yang ter-expire lewat
    # akses sinkron biasa (`perangkat.id`) di luar context greenlet -
    # akan meledak MissingGreenlet kalau dipakai lagi di akhir fungsi ini.

    hasil_transaksi: list[HasilItemPush] = []
    for item in body.transaksi:
        try:
            out = await checkout_service(
                db, toko_id=toko_id, pengguna_id=pengguna_id, role_id=role_id, body=item
            )
            hasil_transaksi.append(HasilItemPush(id=out.id, status="diterima"))
        except HTTPException as exc:
            hasil_transaksi.append(await _tolak_item(db, item.id, str(exc.detail)))
        except IntegrityError:
            hasil_transaksi.append(
                await _tolak_item(db, item.id, "Konflik data (kemungkinan push bersamaan) - coba lagi")
            )

    hasil_shift: list[HasilItemPush] = []
    for item in body.shift:
        try:
            hasil_shift.append(await _push_satu_shift(db, toko_id, pengguna_id, role_id, item))
        except HTTPException as exc:
            hasil_shift.append(await _tolak_item(db, item.id, str(exc.detail)))
        except IntegrityError:
            hasil_shift.append(
                await _tolak_item(db, item.id, "Konflik data (kemungkinan push bersamaan) - coba lagi")
            )

    hasil_kas_shift: list[HasilItemPush] = []
    for item in body.kas_shift:
        try:
            hasil_kas_shift.append(await _push_satu_kas_shift(db, toko_id, pengguna_id, item))
        except IntegrityError:
            hasil_kas_shift.append(
                await _tolak_item(db, item.id, "Konflik data (kemungkinan push bersamaan) - coba lagi")
            )

    hasil_pelanggan: list[HasilItemPush] = []
    for item in body.pelanggan:
        try:
            hasil_pelanggan.append(await _push_satu_pelanggan(db, toko_id, item))
        except IntegrityError:
            hasil_pelanggan.append(
                await _tolak_item(db, item.id, "Konflik data (kemungkinan push bersamaan) - coba lagi")
            )

    hasil_pembayaran: list[HasilItemPush] = []
    for item in body.pembayaran:
        try:
            hasil_pembayaran.append(await _push_satu_pembayaran(db, toko_id, pengguna_id, item))
        except HTTPException as exc:
            hasil_pembayaran.append(await _tolak_item(db, item.id, str(exc.detail)))
        except IntegrityError:
            hasil_pembayaran.append(
                await _tolak_item(db, item.id, "Konflik data (kemungkinan push bersamaan) - coba lagi")
            )

    hasil_pesanan_batal: list[HasilItemPush] = []
    for item in body.pesanan_batal:
        try:
            await batalkan_pesanan_tersimpan(
                db,
                toko_id=toko_id,
                pengguna_id=item.pengguna_id if item.pengguna_id is not None else pengguna_id,
                pesanan_id=item.id,
                alasan=item.alasan,
                disetujui_oleh=item.disetujui_oleh,
            )
            hasil_pesanan_batal.append(HasilItemPush(id=item.id, status="diterima"))
        except HTTPException as exc:
            hasil_pesanan_batal.append(await _tolak_item(db, item.id, str(exc.detail)))

    semua_hasil = (
        hasil_transaksi + hasil_shift + hasil_kas_shift + hasil_pelanggan + hasil_pembayaran + hasil_pesanan_batal
    )
    ada_ditolak = any(h.status == "ditolak" for h in semua_hasil)
    db.add(
        SyncLog(
            toko_id=toko_id,
            perangkat_id=perangkat_id,
            arah="push",
            mulai=mulai,
            selesai=datetime.now(UTC),
            jumlah_record=len(semua_hasil),
            status="sebagian" if ada_ditolak else "berhasil",
        )
    )
    await db.commit()

    return SyncPushOut(
        transaksi=hasil_transaksi,
        shift=hasil_shift,
        kas_shift=hasil_kas_shift,
        pelanggan=hasil_pelanggan,
        pembayaran=hasil_pembayaran,
        pesanan_batal=hasil_pesanan_batal,
    )


async def _push_satu_shift(
    db: AsyncSession, toko_id: uuid.UUID, pengguna_id: uuid.UUID, role_id: uuid.UUID, item: ShiftPushIn
) -> HasilItemPush:
    pengguna_id_efektif = item.pengguna_id if item.pengguna_id is not None else pengguna_id
    existing = await db.get(Shift, item.id)
    if existing is not None:
        if existing.toko_id != toko_id:
            return HasilItemPush(id=item.id, status="ditolak", pesan="Shift tidak ditemukan")

        # Shift yang SUDAH 'tutup' tidak boleh dibuka balik oleh push yang
        # datang terlambat (mis. device retry payload lama "buka" setelah
        # shift itu sudah berhasil ditutup oleh push/endpoint lain yang
        # lebih baru) - begitu tutup, baris ini jadi immutable lewat sync.
        if existing.status == "tutup":
            return HasilItemPush(id=item.id, status="sudah_ada")

        if item.status == "tutup":
            # kas_seharusnya WAJIB dihitung ulang di server dari
            # transaksi+kas_shift yang sungguhan tersimpan - tidak pernah
            # dipercaya dari HP (device bisa saja belum lihat transaksi
            # dari device lain di outlet/shift yang sama, atau nilainya
            # sengaja/tidak sengaja keliru).
            kas_seharusnya = await hitung_kas_seharusnya(db, existing.id, existing.modal_awal)
            existing.kas_seharusnya = kas_seharusnya
            existing.kas_aktual = item.kas_aktual
            existing.selisih = (item.kas_aktual - kas_seharusnya) if item.kas_aktual is not None else None
            existing.ditutup_pada = item.ditutup_pada
            existing.status = "tutup"
        else:
            # Masih 'buka' - cuma field non-rekonsiliasi (catatan dkk) yang
            # relevan diperbarui; kas_seharusnya/kas_aktual/selisih TIDAK
            # berarti apa pun selama shift belum ditutup.
            existing.catatan = item.catatan

        await db.commit()
        return HasilItemPush(id=item.id, status="diterima")

    await get_outlet_milik_toko(db, item.outlet_id, toko_id)
    await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=item.outlet_id)

    kas_seharusnya: Decimal | None = None
    selisih: Decimal | None = None
    if item.status == "tutup":
        # Shift dibuat SEKALIGUS sudah tutup (device offline penuh satu
        # shift sebelum sempat sync sama sekali) - tetap hitung ulang di
        # server, jangan percaya nilai dari payload.
        kas_seharusnya = await hitung_kas_seharusnya(db, item.id, item.modal_awal)
        selisih = (item.kas_aktual - kas_seharusnya) if item.kas_aktual is not None else None

    shift_baru = Shift(
        id=item.id,
        toko_id=toko_id,
        outlet_id=item.outlet_id,
        pengguna_id=pengguna_id_efektif,
        dibuka_pada=item.dibuka_pada,
        ditutup_pada=item.ditutup_pada if item.status == "tutup" else None,
        modal_awal=item.modal_awal,
        kas_seharusnya=kas_seharusnya,
        kas_aktual=item.kas_aktual if item.status == "tutup" else None,
        selisih=selisih,
        catatan=item.catatan,
        status=item.status,
    )
    db.add(shift_baru)
    await db.flush()
    await validasi_dan_tandai(
        db, toko_id=toko_id, pengguna_id=pengguna_id_efektif, outlet_id=item.outlet_id,
        kode_izin="shift.buka_tutup", operasi="shift", tabel="shift", record_id=shift_baru.id,
    )
    await db.commit()
    return HasilItemPush(id=item.id, status="diterima")


async def _push_satu_kas_shift(
    db: AsyncSession, toko_id: uuid.UUID, pengguna_id: uuid.UUID, item: KasShiftPushIn
) -> HasilItemPush:
    existing = await db.get(KasShift, item.id)
    if existing is not None:
        return HasilItemPush(id=item.id, status="sudah_ada")

    shift = await db.get(Shift, item.shift_id)
    if shift is None or shift.toko_id != toko_id:
        return HasilItemPush(id=item.id, status="ditolak", pesan="Shift tidak ditemukan")

    pengguna_id_efektif = item.pengguna_id if item.pengguna_id is not None else pengguna_id
    kas_shift_baru = KasShift(
        id=item.id,
        shift_id=item.shift_id,
        jenis=item.jenis,
        jumlah=item.jumlah,
        keterangan=item.keterangan,
        dibuat_oleh=pengguna_id_efektif,
    )
    db.add(kas_shift_baru)
    await db.flush()
    await validasi_dan_tandai(
        db, toko_id=toko_id, pengguna_id=pengguna_id_efektif, outlet_id=shift.outlet_id,
        kode_izin="kas.keluar_masuk", operasi="kas_shift", tabel="kas_shift", record_id=kas_shift_baru.id,
    )
    await db.commit()
    return HasilItemPush(id=item.id, status="diterima")


async def _push_satu_pelanggan(db: AsyncSession, toko_id: uuid.UUID, item: PelangganPushIn) -> HasilItemPush:
    existing = await db.get(Pelanggan, item.id)
    if existing is not None:
        if existing.toko_id != toko_id:
            return HasilItemPush(id=item.id, status="ditolak", pesan="ID pelanggan tidak tersedia")
        return HasilItemPush(id=item.id, status="sudah_ada")

    db.add(
        Pelanggan(
            id=item.id, toko_id=toko_id, nama=item.nama, no_hp=item.no_hp, email=item.email, catatan=item.catatan
        )
    )
    await db.commit()
    return HasilItemPush(id=item.id, status="diterima")


async def _push_satu_pembayaran(
    db: AsyncSession, toko_id: uuid.UUID, pengguna_id: uuid.UUID, item: PembayaranPushIn
) -> HasilItemPush:
    existing = await db.get(Pembayaran, item.id)
    if existing is not None:
        return HasilItemPush(id=item.id, status="sudah_ada")

    transaksi = await db.get(Transaksi, item.transaksi_id)
    if transaksi is None or transaksi.toko_id != toko_id:
        return HasilItemPush(id=item.id, status="ditolak", pesan="Transaksi tidak ditemukan")

    pengguna_id_efektif = item.pengguna_id if item.pengguna_id is not None else pengguna_id

    # catat_pembayaran() sendiri TIDAK PERNAH menolak krn "kelebihan
    # bayar" (aturan #3 - dua HP offline sama-sama melunasi tetap
    # diterima + ditandai di audit_log/notifikasi) - HTTPException yang
    # mungkin dilempar di sini murni krn validasi dasar (jumlah<=0, shift
    # tidak aktif, metode bayar tidak ditemukan, transaksi belum
    # 'selesai'), ditangkap pemanggil (push()) sbg item "ditolak" seperti
    # item sync lain.
    pembayaran = await catat_pembayaran(
        db,
        toko_id=toko_id,
        transaksi=transaksi,
        body=PembayaranIn(
            id=item.id,
            shift_id=item.shift_id,
            metode_bayar_id=item.metode_bayar_id,
            jumlah=item.jumlah,
            dibayar_pada=item.dibayar_pada,
            payload_gateway=item.payload_gateway,
        ),
    )
    await validasi_dan_tandai(
        db, toko_id=toko_id, pengguna_id=pengguna_id_efektif, outlet_id=transaksi.outlet_id,
        kode_izin=None, operasi="pembayaran", tabel="pembayaran", record_id=pembayaran.id,
    )
    await db.commit()
    return HasilItemPush(id=pembayaran.id, status="diterima")


def _ke_dict(row, kolom: list[str]) -> dict:
    hasil = {}
    for k in kolom:
        value = getattr(row, k)
        if value is not None and not isinstance(value, (str, bool, int, float)):
            value = str(value)
        hasil[k] = value
    return hasil


async def pull(
    db: AsyncSession,
    *,
    toko_id: uuid.UUID,
    pengguna_id: uuid.UUID,
    role_id: uuid.UUID,
    perangkat_id: uuid.UUID,
    outlet_id: uuid.UUID | None,
    since: datetime,
    limit: int = 500,
) -> SyncPullOut:
    """`limit` dipakai PER TABEL (bukan gabungan) - kalau satu tabel masih
    punya sisa, `has_more[nama_tabel]` jadi True dan client wajib pull lagi
    dgn `since` = updated_at baris TERAKHIR yang diterima utk tabel itu
    (tabel diurutkan `updated_at ASC` justru supaya ini valid - tabel lain
    yang sudah habis cukup dikirim ulang `since` yang sama, hasilnya cuma
    kosong/murah, bukan masalah)."""

    perangkat = await _ambil_perangkat_milik_toko(db, perangkat_id, toko_id)
    if outlet_id is not None:
        # outlet_id dari query string - tanpa ini toko A bisa membaca saldo
        # stok toko B (kebocoran baca) cuma dgn menebak outlet_id milik B.
        await get_outlet_milik_toko(db, outlet_id, toko_id)
        await require_outlet_access(db, pengguna_id=pengguna_id, role_id=role_id, outlet_id=outlet_id)

    mulai = datetime.now(UTC)
    perangkat.terakhir_sync = mulai
    await db.commit()

    has_more: dict[str, bool] = {}

    async def _ambil_toko_scoped(nama: str, model, kolom: list[str]) -> list[dict]:
        rows = (
            await db.execute(
                select(model)
                .where(model.toko_id == toko_id, model.updated_at > since)
                .order_by(model.updated_at.asc())
                .limit(limit + 1)
            )
        ).scalars().all()
        has_more[nama] = len(rows) > limit
        return [_ke_dict(r, kolom) for r in rows[:limit]]

    produk = await _ambil_toko_scoped(
        "produk",
        Produk,
        [
            "id", "kategori_id", "satuan_id", "sku", "barcode", "nama", "tipe", "lacak_stok",
            "hpp", "harga_jual", "aktif", "updated_at", "deleted_at",
        ],
    )
    kategori = await _ambil_toko_scoped(
        "kategori", Kategori, ["id", "nama", "warna", "urutan", "updated_at", "deleted_at"]
    )
    satuan = await _ambil_toko_scoped("satuan", Satuan, ["id", "nama", "singkatan", "updated_at", "deleted_at"])
    pajak = await _ambil_toko_scoped(
        "pajak", Pajak,
        ["id", "nama", "tipe", "persen", "termasuk_harga", "urutan", "aktif", "updated_at", "deleted_at"],
    )
    promo = await _ambil_toko_scoped(
        "promo", Promo,
        ["id", "nama", "kode", "tipe", "nilai", "min_belanja", "maks_diskon", "aktif", "updated_at", "deleted_at"],
    )
    metode_bayar = await _ambil_toko_scoped(
        "metode_bayar", MetodeBayar,
        ["id", "nama", "tipe", "butuh_gateway", "masuk_laci", "aktif", "updated_at", "deleted_at"],
    )
    pelanggan = await _ambil_toko_scoped(
        "pelanggan", Pelanggan, ["id", "nama", "no_hp", "email", "poin", "total_belanja", "updated_at", "deleted_at"]
    )
    # Tahap 5b (desain #2) - "daftar karyawan yang boleh masuk ke outlet
    # perangkat itu": Owner/Manajer (role is_system boleh semua outlet,
    # sama semantik dgn require_outlet_access) selalu disertakan; role
    # lain (Kasir dkk) HANYA kalau punya baris akses_outlet ke outlet_id
    # device ini - device di outlet lain tidak perlu (jangan) menerima
    # pin_hash karyawan yang tidak relevan baginya.
    kondisi_pengguna = Pengguna.toko_id == toko_id
    if outlet_id is not None:
        role_tanpa_batas = select(Role.id).where(Role.is_system.is_(True), Role.nama.in_(["Owner", "Manajer"]))
        pengguna_dgn_akses = select(AksesOutlet.pengguna_id).where(AksesOutlet.outlet_id == outlet_id)
        kondisi_pengguna = kondisi_pengguna & (
            Pengguna.role_id.in_(role_tanpa_batas) | Pengguna.id.in_(pengguna_dgn_akses)
        )
    pengguna_rows = (
        await db.execute(
            select(Pengguna)
            .where(kondisi_pengguna, Pengguna.updated_at > since)
            .order_by(Pengguna.updated_at.asc())
            .limit(limit + 1)
        )
    ).scalars().all()
    has_more["pengguna"] = len(pengguna_rows) > limit
    pengguna = [
        _ke_dict(r, ["id", "role_id", "nama", "no_hp", "aktif", "pin_hash", "updated_at", "deleted_at"])
        for r in pengguna_rows[:limit]
    ]

    role_rows = (
        await db.execute(
            select(Role)
            .where(Role.updated_at > since, or_(Role.toko_id == toko_id, Role.is_system.is_(True)))
            .order_by(Role.updated_at.asc())
            .limit(limit + 1)
        )
    ).scalars().all()
    has_more["role"] = len(role_rows) > limit
    role = [_ke_dict(r, ["id", "nama", "is_system", "updated_at", "deleted_at"]) for r in role_rows[:limit]]

    # role_izin: relasi murni (CreatedAtOnlyMixin, tanpa updated_at) - kode
    # izin diresolve langsung di sini (bukan izin_id) supaya device tidak
    # perlu pull tabel master `izin` terpisah cuma utk 1 kolom ini.
    role_izin_rows = (
        await db.execute(
            select(RoleIzin.role_id, Izin.kode)
            .join(Izin, Izin.id == RoleIzin.izin_id)
            .join(Role, Role.id == RoleIzin.role_id)
            .where(or_(Role.toko_id == toko_id, Role.is_system.is_(True)))
        )
    ).all()
    role_izin = [{"role_id": str(role_id), "izin_kode": kode} for role_id, kode in role_izin_rows]

    stok: list[dict] = []
    has_more["stok"] = False
    if outlet_id is not None:
        stok_rows = (
            await db.execute(
                select(Stok)
                .where(Stok.outlet_id == outlet_id, Stok.updated_at > since)
                .order_by(Stok.updated_at.asc())
                .limit(limit + 1)
            )
        ).scalars().all()
        has_more["stok"] = len(stok_rows) > limit
        stok = [
            _ke_dict(
                r,
                [
                    "id", "outlet_id", "produk_id", "varian_id", "jumlah", "batas_minimum",
                    "hpp_rata_rata", "updated_at", "deleted_at",
                ],
            )
            for r in stok_rows[:limit]
        ]

    harga_outlet: list[dict] = []
    has_more["harga_outlet"] = False
    if outlet_id is not None:
        harga_outlet_rows = (
            await db.execute(
                select(HargaOutlet)
                .where(HargaOutlet.outlet_id == outlet_id, HargaOutlet.updated_at > since)
                .order_by(HargaOutlet.updated_at.asc())
                .limit(limit + 1)
            )
        ).scalars().all()
        has_more["harga_outlet"] = len(harga_outlet_rows) > limit
        harga_outlet = [
            _ke_dict(r, ["id", "outlet_id", "produk_id", "varian_id", "harga_jual", "updated_at", "deleted_at"])
            for r in harga_outlet_rows[:limit]
        ]

    # harga_grosir: tier umum (outlet_id NULL, berlaku semua outlet toko
    # ini) SELALU disertakan; tier khusus-outlet cuma utk outlet_id device
    # ini - toko-scoped lewat join Produk (HargaGrosir sendiri tidak
    # punya kolom toko_id).
    kondisi_outlet = HargaGrosir.outlet_id.is_(None)
    if outlet_id is not None:
        kondisi_outlet = kondisi_outlet | (HargaGrosir.outlet_id == outlet_id)
    grosir_rows = (
        await db.execute(
            select(HargaGrosir)
            .join(Produk, Produk.id == HargaGrosir.produk_id)
            .where(Produk.toko_id == toko_id, HargaGrosir.updated_at > since, kondisi_outlet)
            .order_by(HargaGrosir.updated_at.asc())
            .limit(limit + 1)
        )
    ).scalars().all()
    has_more["harga_grosir"] = len(grosir_rows) > limit
    harga_grosir = [
        _ke_dict(r, ["id", "produk_id", "varian_id", "outlet_id", "min_qty", "harga", "updated_at", "deleted_at"])
        for r in grosir_rows[:limit]
    ]

    # tipe_order_pajak: relasi murni (CreatedAtOnlyMixin, tanpa updated_at)
    # - snapshot PENUH tiap pull, toko-scoped lewat join TipeOrder.
    tipe_order_pajak_rows = (
        await db.execute(
            select(TipeOrderPajak)
            .join(TipeOrder, TipeOrder.id == TipeOrderPajak.tipe_order_id)
            .where(TipeOrder.toko_id == toko_id)
        )
    ).scalars().all()
    tipe_order_pajak = [_ke_dict(r, ["tipe_order_id", "pajak_id"]) for r in tipe_order_pajak_rows]

    # pengaturan_outlet: satu baris per outlet (PK = outlet_id, bukan
    # `id`) - snapshot baris outlet device ini saja tiap pull (kecil,
    # tidak perlu delta/has_more).
    pengaturan_outlet: list[dict] = []
    if outlet_id is not None:
        pengaturan = await db.get(PengaturanOutlet, outlet_id)
        if pengaturan is not None:
            pengaturan_outlet = [
                _ke_dict(
                    pengaturan,
                    [
                        "outlet_id", "header_struk", "footer_struk", "tampil_logo", "lebar_kertas_mm",
                        "pembulatan", "izinkan_stok_minus", "wajib_buka_shift", "struk_ringkas",
                        "pakai_nomor_antrean", "updated_at", "deleted_at",
                    ],
                )
            ]

    paket = await paket_efektif(db, toko_id)
    kode_fitur = sorted(await kode_fitur_toko(db, toko_id))
    batas_fitur = await semua_batas_fitur_toko(db, toko_id)
    toko = await db.get(Toko, toko_id)

    jumlah_record = sum(
        len(x)
        for x in [
            produk, kategori, satuan, pajak, promo, metode_bayar, pelanggan, pengguna, role, role_izin, stok,
            harga_outlet, harga_grosir, tipe_order_pajak, pengaturan_outlet,
        ]
    )
    db.add(
        SyncLog(
            toko_id=toko_id,
            perangkat_id=perangkat.id,
            arah="pull",
            mulai=mulai,
            selesai=datetime.now(UTC),
            jumlah_record=jumlah_record,
            status="berhasil",
        )
    )
    await db.commit()

    return SyncPullOut(
        waktu_pull=datetime.now(UTC),
        produk=produk,
        kategori=kategori,
        satuan=satuan,
        pajak=pajak,
        promo=promo,
        metode_bayar=metode_bayar,
        pelanggan=pelanggan,
        pengguna=pengguna,
        role=role,
        role_izin=role_izin,
        stok=stok,
        harga_outlet=harga_outlet,
        harga_grosir=harga_grosir,
        tipe_order_pajak=tipe_order_pajak,
        pengaturan_outlet=pengaturan_outlet,
        paket=paket.nama,
        logo_url=toko.logo_url if toko is not None else None,
        kode_fitur=kode_fitur,
        batas_fitur=batas_fitur,
        has_more=has_more,
    )
