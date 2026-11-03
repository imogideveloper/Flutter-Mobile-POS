"""Tahap 5 B.2 - PATCH (termasuk akses outlet), reset-pin, DELETE
pengguna, + proteksi self/last-owner."""

import uuid

from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token, verify_password
from app.models.akun import AksesOutlet, Izin, Pengguna, Role, RoleIzin
from app.models.audit import AuditLog
from app.models.outlet import Outlet


async def _buat_hr_custom(db: AsyncSession, toko_id) -> tuple[Pengguna, str]:
    """Role custom (BUKAN Owner/Manajer bawaan) yang HANYA dikasih izin
    pengguna.kelola - dipakai utk membuktikan proteksi "Owner terakhir"
    berlaku independen dari role Owner/Manajer bawaan (yang mana Manajer
    SENGAJA tidak punya izin ini sama sekali, lihat seed.py
    _MANAJER_KECUALI, jadi tidak bisa dipakai utk skenario ini)."""
    role = Role(toko_id=toko_id, nama="HR Custom", is_system=False)
    db.add(role)
    await db.flush()
    izin = (await db.execute(select(Izin).where(Izin.kode == "pengguna.kelola"))).scalar_one()
    db.add(RoleIzin(role_id=role.id, izin_id=izin.id))
    hr = Pengguna(toko_id=toko_id, role_id=role.id, nama="Staf HR")
    db.add(hr)
    await db.commit()
    await db.refresh(hr)
    token = create_access_token(pengguna_id=hr.id, toko_id=toko_id, role_id=role.id)
    return hr, token


async def _buat_kasir(db: AsyncSession, toko_id) -> tuple[Pengguna, str]:
    role = (await db.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))).scalar_one()
    kasir = Pengguna(toko_id=toko_id, role_id=role.id, nama="Kasir Biasa")
    db.add(kasir)
    await db.commit()
    await db.refresh(kasir)
    token = create_access_token(pengguna_id=kasir.id, toko_id=toko_id, role_id=role.id)
    return kasir, token


async def test_kasir_tanpa_izin_ubah_pengguna_ditolak(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    _, token_kasir = await _buat_kasir(db_session, toko_a.toko.id)
    resp = await client.patch(
        f"/pengguna/{toko_a.pengguna.id}",
        headers={"Authorization": f"Bearer {token_kasir}"},
        json={"nama": "Coba ubah"},
    )
    assert resp.status_code == 403


async def test_ubah_pengguna_tercatat_audit_log(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    kasir, _ = await _buat_kasir(db_session, toko_a.toko.id)
    resp = await client.patch(
        f"/pengguna/{kasir.id}", headers=toko_a.headers, json={"nama": "Nama Baru"}
    )
    assert resp.status_code == 200
    assert resp.json()["nama"] == "Nama Baru"

    audit = (
        await db_session.execute(select(AuditLog).where(AuditLog.aksi == "ubah_pengguna"))
    ).scalar_one()
    assert audit.data_baru["nama"] == "Nama Baru"


async def test_ubah_akses_outlet_replace_all(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    kasir, _ = await _buat_kasir(db_session, toko_a.toko.id)
    outlet2 = Outlet(toko_id=toko_a.toko.id, kode="OUT2", nama="Outlet Kedua")
    db_session.add(outlet2)
    await db_session.commit()

    resp = await client.patch(
        f"/pengguna/{kasir.id}",
        headers=toko_a.headers,
        json={"outlet_ids": [str(toko_a.outlet.id), str(outlet2.id)]},
    )
    assert resp.status_code == 200
    assert set(resp.json()["outlet_ids"]) == {str(toko_a.outlet.id), str(outlet2.id)}

    rows = (
        await db_session.execute(select(AksesOutlet).where(AksesOutlet.pengguna_id == kasir.id))
    ).scalars().all()
    assert len(rows) == 2

    # Replace-all lagi dgn 1 outlet saja - harus TIMPA, bukan tambah.
    resp2 = await client.patch(
        f"/pengguna/{kasir.id}", headers=toko_a.headers, json={"outlet_ids": [str(toko_a.outlet.id)]}
    )
    assert resp2.status_code == 200
    rows2 = (
        await db_session.execute(select(AksesOutlet).where(AksesOutlet.pengguna_id == kasir.id))
    ).scalars().all()
    assert len(rows2) == 1


async def test_tidak_bisa_menonaktifkan_diri_sendiri(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    resp = await client.patch(
        f"/pengguna/{toko_a.pengguna.id}", headers=toko_a.headers, json={"aktif": False}
    )
    assert resp.status_code == 400


async def test_tidak_bisa_ganti_role_sendiri_keluar_dari_owner(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    kasir_role = (
        await db_session.execute(select(Role).where(Role.nama == "Kasir", Role.is_system.is_(True)))
    ).scalar_one()
    resp = await client.patch(
        f"/pengguna/{toko_a.pengguna.id}", headers=toko_a.headers, json={"role_id": str(kasir_role.id)}
    )
    assert resp.status_code == 400


async def test_tidak_bisa_nonaktifkan_owner_terakhir_oleh_orang_lain(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    """toko_a.pengguna adalah satu2nya Owner - staf lain yang punya izin
    pengguna.kelola (role custom, BUKAN Owner/Manajer) tidak boleh
    menonaktifkannya."""
    _, token_hr = await _buat_hr_custom(db_session, toko_a.toko.id)

    resp = await client.patch(
        f"/pengguna/{toko_a.pengguna.id}",
        headers={"Authorization": f"Bearer {token_hr}"},
        json={"aktif": False},
    )
    assert resp.status_code == 400

    # Tapi KALAU ada Owner lain yang masih aktif, boleh.
    owner_role = (
        await db_session.execute(select(Role).where(Role.nama == "Owner", Role.is_system.is_(True)))
    ).scalar_one()
    owner_kedua = Pengguna(toko_id=toko_a.toko.id, role_id=owner_role.id, nama="Owner Kedua")
    db_session.add(owner_kedua)
    await db_session.commit()

    resp2 = await client.patch(
        f"/pengguna/{toko_a.pengguna.id}",
        headers={"Authorization": f"Bearer {token_hr}"},
        json={"aktif": False},
    )
    assert resp2.status_code == 200


async def test_patch_role_id_tidak_valid_tetap_404_bukan_ketimpa_proteksi_self(
    client: AsyncClient, db_session: AsyncSession, toko_a
) -> None:
    resp = await client.patch(
        f"/pengguna/{toko_a.pengguna.id}", headers=toko_a.headers, json={"role_id": str(uuid.uuid4())}
    )
    assert resp.status_code == 404


async def test_reset_pin_pengguna(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    kasir, _ = await _buat_kasir(db_session, toko_a.toko.id)
    resp = await client.post(
        f"/pengguna/{kasir.id}/reset-pin", headers=toko_a.headers, json={"pin": "135790"}
    )
    assert resp.status_code == 204

    await db_session.refresh(kasir)
    assert verify_password("135790", kasir.pin_hash)

    audit = (
        await db_session.execute(select(AuditLog).where(AuditLog.aksi == "reset_pin_pengguna"))
    ).scalar_one()
    assert audit.record_id == kasir.id


async def test_hapus_pengguna_soft_delete(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    kasir, _ = await _buat_kasir(db_session, toko_a.toko.id)
    resp = await client.delete(f"/pengguna/{kasir.id}", headers=toko_a.headers)
    assert resp.status_code == 204

    await db_session.refresh(kasir)
    assert kasir.deleted_at is not None
    assert kasir.aktif is False

    resp2 = await client.get(f"/pengguna/{kasir.id}", headers=toko_a.headers)
    assert resp2.status_code == 404


async def test_tidak_bisa_hapus_diri_sendiri(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    resp = await client.delete(f"/pengguna/{toko_a.pengguna.id}", headers=toko_a.headers)
    assert resp.status_code == 400


async def test_tidak_bisa_hapus_owner_terakhir(client: AsyncClient, db_session: AsyncSession, toko_a) -> None:
    _, token_hr = await _buat_hr_custom(db_session, toko_a.toko.id)

    resp = await client.delete(
        f"/pengguna/{toko_a.pengguna.id}", headers={"Authorization": f"Bearer {token_hr}"}
    )
    assert resp.status_code == 400
