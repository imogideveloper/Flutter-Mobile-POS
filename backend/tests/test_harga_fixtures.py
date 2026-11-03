"""Setiap file di shared/fixtures/harga/*.json dibaca di sini DAN di
test/harga_fixtures_test.dart (Flutter) - keduanya harus menghasilkan
angka yang identik, supaya kalkulator.py dan kalkulator.dart tidak
diam-diam melenceng. Lihat docs/aturan_harga.md."""

import json
from decimal import Decimal
from pathlib import Path

import pytest

from app.services.harga import kalkulator as k

FIXTURES_DIR = Path(__file__).resolve().parents[2] / "shared" / "fixtures" / "harga"


def _dec(nilai):
    if nilai is None:
        return None
    return Decimal(str(nilai))


def _bangun_item(data: dict) -> k.ItemInput:
    return k.ItemInput(
        produk_id=data["produk_id"],
        varian_id=data.get("varian_id"),
        nama_produk=data.get("nama_produk", ""),
        qty=_dec(data["qty"]),
        harga_jual=_dec(data["harga_jual"]),
        harga_outlet=_dec(data.get("harga_outlet")),
        harga_grosir_tiers=tuple(
            k.HargaGrosirTier(min_qty=_dec(t["min_qty"]), harga=_dec(t["harga"]), outlet_id=t.get("outlet_id"))
            for t in data.get("harga_grosir_tiers", [])
        ),
        modifiers=tuple(k.ModifierInput(nama=m["nama"], harga=_dec(m["harga"])) for m in data.get("modifiers", [])),
        pajak_produk=(
            None
            if data.get("pajak_produk") is None
            else tuple(_bangun_pajak(p) for p in data["pajak_produk"])
        ),
    )


def _bangun_pajak(data: dict) -> k.PajakInput:
    return k.PajakInput(
        id=data["id"],
        nama=data["nama"],
        persen=_dec(data["persen"]),
        termasuk_harga=data["termasuk_harga"],
        urutan=data.get("urutan", 0),
    )


def _bangun_promo(data: dict | None) -> k.PromoInput | None:
    if data is None:
        return None
    return k.PromoInput(
        id=data["id"],
        nama=data["nama"],
        tipe=data["tipe"],
        cakupan=data["cakupan"],
        nilai=_dec(data["nilai"]),
        min_belanja=_dec(data.get("min_belanja", 0)),
        maks_diskon=_dec(data.get("maks_diskon")),
        produk_ids=frozenset(data.get("produk_ids", [])),
    )


def _bangun_tipe_order(data: dict | None) -> k.TipeOrderInput | None:
    if data is None:
        return None
    return k.TipeOrderInput(
        id=data["id"],
        markup_persen=_dec(data.get("markup_persen", 0)),
        pajak_ids=frozenset(data.get("pajak_ids", [])),
    )


def _bangun_input(data: dict) -> k.TransaksiInput:
    return k.TransaksiInput(
        items=tuple(_bangun_item(i) for i in data["items"]),
        fitur_aktif=frozenset(data.get("fitur_aktif", [])),
        promo=_bangun_promo(data.get("promo")),
        diskon_member_persen=_dec(data.get("diskon_member_persen")),
        tipe_order=_bangun_tipe_order(data.get("tipe_order")),
        pajak_default=tuple(_bangun_pajak(p) for p in data.get("pajak_default", [])),
        service_default=tuple(_bangun_pajak(p) for p in data.get("service_default", [])),
        pembulatan=data.get("pembulatan", 0),
    )


def _muat_semua_fixture():
    return sorted(FIXTURES_DIR.glob("*.json"))


@pytest.mark.parametrize("path", _muat_semua_fixture(), ids=lambda p: p.stem)
def test_fixture_harga(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    hasil = k.hitung(_bangun_input(data["input"]))
    exp = data["expected"]

    assert hasil.subtotal == _dec(exp["subtotal"]), data["nama"]
    assert hasil.diskon_member == _dec(exp["diskon_member"]), data["nama"]
    assert hasil.diskon_promo == _dec(exp["diskon_promo"]), data["nama"]
    assert hasil.total_diskon == _dec(exp["total_diskon"]), data["nama"]
    assert hasil.service == _dec(exp["service"]), data["nama"]
    assert hasil.pajak == _dec(exp["pajak"]), data["nama"]
    assert hasil.total_sebelum_pembulatan == _dec(exp["total_sebelum_pembulatan"]), data["nama"]
    assert hasil.pembulatan == _dec(exp["pembulatan"]), data["nama"]
    assert hasil.total == _dec(exp["total"]), data["nama"]

    assert len(hasil.items) == len(exp["items"]), data["nama"]
    for item_hasil, item_exp in zip(hasil.items, exp["items"]):
        assert item_hasil.produk_id == item_exp["produk_id"], data["nama"]
        assert item_hasil.harga_satuan == _dec(item_exp["harga_satuan"]), data["nama"]
        assert item_hasil.diskon == _dec(item_exp["diskon"]), data["nama"]
        assert item_hasil.subtotal == _dec(item_exp["subtotal"]), data["nama"]

    assert len(hasil.rincian_service) == len(exp["rincian_service"]), data["nama"]
    for r_hasil, r_exp in zip(hasil.rincian_service, exp["rincian_service"]):
        assert r_hasil.nama == r_exp["nama"], data["nama"]
        assert r_hasil.jumlah == _dec(r_exp["jumlah"]), data["nama"]
        assert r_hasil.termasuk_harga == r_exp["termasuk_harga"], data["nama"]

    assert len(hasil.rincian_pajak) == len(exp["rincian_pajak"]), data["nama"]
    rincian_pajak_hasil = sorted(hasil.rincian_pajak, key=lambda r: r.nama)
    rincian_pajak_exp = sorted(exp["rincian_pajak"], key=lambda r: r["nama"])
    for r_hasil, r_exp in zip(rincian_pajak_hasil, rincian_pajak_exp):
        assert r_hasil.nama == r_exp["nama"], data["nama"]
        assert r_hasil.jumlah == _dec(r_exp["jumlah"]), data["nama"]
        assert r_hasil.termasuk_harga == r_exp["termasuk_harga"], data["nama"]


def test_ada_minimal_25_fixture():
    assert len(_muat_semua_fixture()) >= 25
