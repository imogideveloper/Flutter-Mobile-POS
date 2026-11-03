"""Setiap file di shared/fixtures/refund/*.json dibaca di sini DAN di
test/refund_fixtures_test.dart (Flutter) - keduanya harus menghasilkan
angka yang identik. Lihat docs/aturan_harga.md bagian
"Refund proporsional (F3.D)"."""

import json
from decimal import Decimal
from pathlib import Path

import pytest

from app.services.harga.refund_kalkulator import ItemRefundInput, RefundLineInput, hitung_refund_proporsional

FIXTURES_DIR = Path(__file__).resolve().parents[2] / "shared" / "fixtures" / "refund"


def _muat_semua_fixture():
    return sorted(FIXTURES_DIR.glob("*.json"))


@pytest.mark.parametrize("path", _muat_semua_fixture(), ids=lambda p: p.stem)
def test_fixture_refund(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    inp = data["input"]

    items = tuple(
        ItemRefundInput(
            item_transaksi_id=i["item_transaksi_id"],
            qty=Decimal(str(i["qty"])),
            harga_satuan=Decimal(str(i["harga_satuan"])),
            diskon=Decimal(str(i["diskon"])),
            subtotal=Decimal(str(i["subtotal"])),
        )
        for i in inp["items"]
    )
    refund_lines = tuple(
        RefundLineInput(item_transaksi_id=r["item_transaksi_id"], qty_refund=Decimal(str(r["qty_refund"])))
        for r in inp["refund_lines"]
    )

    hasil = hitung_refund_proporsional(
        items=items,
        diskon_transaksi_total=Decimal(str(inp["diskon_transaksi_total"])),
        pajak_service_total=Decimal(str(inp["pajak_service_total"])),
        refund_lines=refund_lines,
    )

    exp_by_id = {line["item_transaksi_id"]: Decimal(str(line["jumlah"])) for line in data["expected"]["lines"]}
    assert len(hasil) == len(exp_by_id), data["nama"]
    for baris in hasil:
        assert baris.jumlah == exp_by_id[baris.item_transaksi_id], data["nama"]


def test_ada_minimal_6_fixture_refund():
    assert len(_muat_semua_fixture()) >= 6
