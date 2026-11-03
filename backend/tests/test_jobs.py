from datetime import UTC, datetime, timedelta
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit import Notifikasi
from app.models.outlet import Langganan, Paket
from app.models.stok import Stok
from app.services.jobs_service import cek_stok_menipis_dan_notifikasi, tandai_langganan_kedaluwarsa
from tests.conftest import buat_produk


async def test_tandai_langganan_kedaluwarsa_hanya_yang_sudah_lewat(
    db_session: AsyncSession, toko_a, toko_b
) -> None:
    paket_pro = (await db_session.execute(select(Paket).where(Paket.nama == "Pro"))).scalar_one()

    # Langganan toko_a (fixture) = Gratis, berakhir NULL - tidak boleh disentuh.
    kemarin = datetime.now(UTC) - timedelta(days=1)

    langganan_lewat = Langganan(
        toko_id=toko_b.toko.id, paket_id=paket_pro.id, jumlah_outlet=1, mulai=kemarin - timedelta(days=30),
        berakhir=kemarin, status="aktif",
    )
    db_session.add(langganan_lewat)
    await db_session.commit()

    jumlah = await tandai_langganan_kedaluwarsa(db_session)
    assert jumlah == 1

    await db_session.refresh(langganan_lewat)
    assert langganan_lewat.status == "kedaluwarsa"

    notif = (
        await db_session.execute(select(Notifikasi).where(Notifikasi.ref_id == langganan_lewat.id))
    ).scalar_one()
    assert notif.jenis == "langganan"
    assert notif.toko_id == toko_b.toko.id

    # Langganan toko_a (Gratis, berakhir NULL) tidak boleh kena.
    langganan_a = (
        await db_session.execute(select(Langganan).where(Langganan.toko_id == toko_a.toko.id))
    ).scalar_one()
    assert langganan_a.status == "aktif"

    # Jalankan lagi - tidak ada yang baru kedaluwarsa (sudah ditandai).
    jumlah2 = await tandai_langganan_kedaluwarsa(db_session)
    assert jumlah2 == 0


async def test_cek_stok_menipis_bikin_notifikasi_sekali_tidak_dobel(
    db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    stok = Stok(outlet_id=toko_a.outlet.id, produk_id=produk.id, jumlah=Decimal("2"), batas_minimum=Decimal("5"))
    db_session.add(stok)
    await db_session.commit()

    jumlah = await cek_stok_menipis_dan_notifikasi(db_session)
    assert jumlah == 1

    # Jalankan lagi - TIDAK bikin notifikasi dobel krn yang lama belum dibaca.
    jumlah2 = await cek_stok_menipis_dan_notifikasi(db_session)
    assert jumlah2 == 0

    notif_rows = (
        await db_session.execute(select(Notifikasi).where(Notifikasi.jenis == "stok_menipis"))
    ).scalars().all()
    assert len(notif_rows) == 1


async def test_cek_stok_menipis_mengabaikan_batas_minimum_nol(
    db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    # batas_minimum default 0 - produk yg belum diatur batasnya, bukan sinyal "menipis".
    stok = Stok(outlet_id=toko_a.outlet.id, produk_id=produk.id, jumlah=Decimal("0"))
    db_session.add(stok)
    await db_session.commit()

    jumlah = await cek_stok_menipis_dan_notifikasi(db_session)
    assert jumlah == 0


async def test_cek_stok_menipis_kirim_ulang_setelah_notifikasi_lama_dibaca(
    db_session: AsyncSession, toko_a
) -> None:
    produk = await buat_produk(db_session, toko_a.toko.id)
    stok = Stok(outlet_id=toko_a.outlet.id, produk_id=produk.id, jumlah=Decimal("1"), batas_minimum=Decimal("5"))
    db_session.add(stok)
    await db_session.commit()

    await cek_stok_menipis_dan_notifikasi(db_session)

    notif = (await db_session.execute(select(Notifikasi).where(Notifikasi.ref_id == stok.id))).scalar_one()
    notif.dibaca_pada = datetime.now(UTC)
    await db_session.commit()

    jumlah_kedua = await cek_stok_menipis_dan_notifikasi(db_session)
    assert jumlah_kedua == 1
