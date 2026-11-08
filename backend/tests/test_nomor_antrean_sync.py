"""Nomor antrian yang dibuat HP saat offline ikut tersimpan lewat sync push."""

import uuid
from datetime import UTC, datetime

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaksi import Transaksi
from tests.conftest import buat_metode_bayar, buat_perangkat, buat_produk


async def _push(client: AsyncClient, db_session: AsyncSession, toko, **tambahan) -> tuple[str, object]:
    produk = await buat_produk(db_session, toko.toko.id)
    metode = await buat_metode_bayar(db_session, toko.toko.id)
    perangkat = await buat_perangkat(db_session, toko.toko.id, toko.outlet.id)
    transaksi_id = str(uuid.uuid4())
    payload = {
        "perangkat_id": str(perangkat.id),
        "transaksi": [
            {
                "id": transaksi_id,
                "outlet_id": str(toko.outlet.id),
                "nomor_struk": "OUT1-ANTRE-0001",
                "tanggal": datetime.now(UTC).isoformat(),
                "items": [
                    {"produk_id": str(produk.id), "nama_produk": produk.nama, "qty": "1", "harga_satuan": "15000"}
                ],
                "metode_bayar_id": str(metode.id),
                "total_bayar": "15000",
                **tambahan,
            }
        ],
    }
    return transaksi_id, await client.post("/sync/push", headers=toko.headers, json=payload)


async def test_push_menyimpan_nomor_antrean_dari_hp(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    transaksi_id, resp = await _push(client, db_session, toko_a, nomor_antrean="A-007")
    assert resp.status_code == 200
    assert resp.json()["transaksi"][0]["status"] == "diterima"

    row = (await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(transaksi_id)))).scalar_one()
    assert row.nomor_antrean == "A-007"


async def test_push_tanpa_nomor_antrean_tetap_diterima(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    transaksi_id, resp = await _push(client, db_session, toko_a)
    assert resp.status_code == 200
    row = (await db_session.execute(select(Transaksi).where(Transaksi.id == uuid.UUID(transaksi_id)))).scalar_one()
    assert row.nomor_antrean is None


async def test_push_nomor_antrean_terlalu_panjang_ditolak(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    _, resp = await _push(client, db_session, toko_a, nomor_antrean="ABCDEFGHIJK")  # 11 karakter
    assert resp.status_code == 422
