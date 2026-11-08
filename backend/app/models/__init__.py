"""Import semua modul model supaya Base.metadata lengkap dengan satu
`import app.models` - dibutuhkan Alembic autogenerate & fixture pytest
(Base.metadata.create_all())."""

from . import (  # noqa: F401
    akun,
    audit,
    fitur,
    ops,
    order,
    outlet,
    pelanggan,
    platform,
    produk,
    promo,
    stok,
    transaksi,
)
