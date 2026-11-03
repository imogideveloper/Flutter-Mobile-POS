"""Skema awal - DDL mentah resmi dari PROMPT_Senior_Mobile_Dev_POS (1).md
bagian 7 (versi 2, 69 tabel), ditempel apa adanya lewat op.execute().

Keputusan arsitektur (lihat plan): migrasi pertama ini SENGAJA bukan hasil
`alembic revision --autogenerate` dari model SQLAlchemy - dokumen adalah
sumber kebenaran skema, model di app/models/*.py ditulis mengikuti DDL ini
kolom-demi-kolom. Migrasi berikutnya (0002 dst.) baru boleh pakai
autogenerate dari model.

Revision ID: 0001
Revises:
Create Date: 2026-10-11
"""

from typing import Sequence, Union

from alembic import op

from app.core.ddl_split import split_statements

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_DDL = """
-- =====================================================================
-- SKEMA DATABASE APLIKASI POS (multi-toko, offline-first) - versi 2
-- v2: fitur per paket langganan, tipe pesanan, meja, tiket dapur, antrean,
--     kasbon + DP, level member, aturan poin, survei, absensi, bundling,
--     batch kedaluwarsa, harga grosir, pajak per produk
-- Target  : PostgreSQL 15+
-- Konvensi:
--   * Semua PK pakai UUID (bisa dibuat di HP saat offline)
--   * Semua tabel punya created_at, updated_at, deleted_at (soft delete)
--     -> HP cukup pull data dengan updated_at > waktu sync terakhir
--   * Data per toko dipisah lewat kolom toko_id (multi-tenant)
--   * Nama produk/harga di transaksi disimpan sebagai snapshot
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Fungsi untuk auto-update kolom updated_at
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
-- 1. MODUL BISNIS / TENANT
-- =====================================================================

CREATE TABLE paket (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama            varchar(50)  NOT NULL,
  urutan          int NOT NULL DEFAULT 0,          -- tingkat: 0 Gratis, 1 Pro, 2 Bisnis
  harga_bulanan   numeric(14,2) NOT NULL DEFAULT 0,  -- per outlet
  harga_tahunan   numeric(14,2),                     -- per outlet
  maks_outlet     int,                 -- NULL = tak terbatas
  maks_pengguna   int,
  maks_produk     int,
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE toko (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama            varchar(150) NOT NULL,
  jenis_usaha     varchar(50),         -- retail, fnb, jasa, dll
  pemilik_nama    varchar(150),
  email           varchar(150),
  no_hp           varchar(20),
  alamat          text,
  logo_url        text,
  zona_waktu      varchar(50) NOT NULL DEFAULT 'Asia/Jakarta',
  mata_uang       char(3) NOT NULL DEFAULT 'IDR',
  pengaturan_fitur jsonb NOT NULL DEFAULT '{}'::jsonb, -- fitur yang dinyalakan/dimatikan owner sesuai jenis usaha
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE langganan (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  paket_id        uuid NOT NULL REFERENCES paket(id),
  jumlah_outlet   int NOT NULL DEFAULT 1 CHECK (jumlah_outlet > 0),
  periode         varchar(10) NOT NULL DEFAULT 'bulanan' CHECK (periode IN ('bulanan','tahunan')),
  mulai           timestamptz NOT NULL,
  berakhir        timestamptz,
  status          varchar(20) NOT NULL DEFAULT 'aktif'
                  CHECK (status IN ('trial','aktif','kedaluwarsa','batal')),
  jumlah_bayar    numeric(14,2) NOT NULL DEFAULT 0,
  ref_pembayaran  varchar(100),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE outlet (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  kode            varchar(20) NOT NULL,   -- dipakai di nomor struk, mis. OUT1
  nama            varchar(150) NOT NULL,
  alamat          text,
  no_hp           varchar(20),
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (toko_id, kode)
);

CREATE TABLE pengaturan_outlet (
  outlet_id         uuid PRIMARY KEY REFERENCES outlet(id),
  header_struk      text,
  footer_struk      text,
  tampil_logo       boolean NOT NULL DEFAULT true,
  lebar_kertas_mm   int NOT NULL DEFAULT 58 CHECK (lebar_kertas_mm IN (58,80)),
  pembulatan        int NOT NULL DEFAULT 0,      -- 0, 100, 500, 1000 rupiah
  izinkan_stok_minus boolean NOT NULL DEFAULT true,
  wajib_buka_shift  boolean NOT NULL DEFAULT true,
  struk_ringkas     boolean NOT NULL DEFAULT false,  -- tanpa rincian modifier & pajak
  pakai_nomor_antrean boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE TABLE perangkat (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  outlet_id       uuid REFERENCES outlet(id),
  nama            varchar(100) NOT NULL,      -- "HP Kasir 1"
  device_uid      varchar(150) NOT NULL,
  platform        varchar(20),                -- android, ios
  versi_app       varchar(20),
  fcm_token       text,
  terakhir_sync   timestamptz,
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (toko_id, device_uid)
);

-- =====================================================================
-- 2. MODUL PENGGUNA & HAK AKSES
-- =====================================================================

CREATE TABLE role (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid REFERENCES toko(id),   -- NULL = role bawaan sistem
  nama            varchar(50) NOT NULL,
  is_system       boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE izin (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kode            varchar(60) NOT NULL UNIQUE,  -- mis. transaksi.void
  modul           varchar(30) NOT NULL,
  deskripsi       text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE role_izin (
  role_id         uuid NOT NULL REFERENCES role(id),
  izin_id         uuid NOT NULL REFERENCES izin(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role_id, izin_id)
);

CREATE TABLE pengguna (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  role_id         uuid NOT NULL REFERENCES role(id),
  nama            varchar(150) NOT NULL,
  email           varchar(150),
  no_hp           varchar(20),
  password_hash   text,
  pin_hash        text,                -- PIN 4-6 digit untuk login cepat / approval
  aktif           boolean NOT NULL DEFAULT true,
  terakhir_login  timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE UNIQUE INDEX uq_pengguna_email ON pengguna (lower(email)) WHERE email IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_pengguna_hp    ON pengguna (no_hp) WHERE no_hp IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE akses_outlet (
  pengguna_id     uuid NOT NULL REFERENCES pengguna(id),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (pengguna_id, outlet_id)
);

-- =====================================================================
-- 3. MODUL PRODUK
-- =====================================================================

CREATE TABLE kategori (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(100) NOT NULL,
  warna           varchar(9),
  urutan          int NOT NULL DEFAULT 0,
  stasiun_dapur_id uuid,                -- tiket item kategori ini dicetak di stasiun mana
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE satuan (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(50) NOT NULL,      -- Pieces, Kilogram
  singkatan       varchar(10) NOT NULL,      -- pcs, kg
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE produk (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  kategori_id     uuid REFERENCES kategori(id),
  satuan_id       uuid REFERENCES satuan(id),
  sku             varchar(50),
  barcode         varchar(50),
  nama            varchar(150) NOT NULL,
  deskripsi       text,
  gambar_url      text,
  tipe            varchar(20) NOT NULL DEFAULT 'barang'
                  CHECK (tipe IN ('barang','jasa','bahan_baku','bundling')),
  lacak_stok      boolean NOT NULL DEFAULT true,
  punya_varian    boolean NOT NULL DEFAULT false,
  pakai_resep     boolean NOT NULL DEFAULT false,  -- potong stok bahan baku saat terjual
  lacak_kedaluwarsa boolean NOT NULL DEFAULT false, -- stok dicatat per batch_stok
  hpp             numeric(14,2) NOT NULL DEFAULT 0,
  harga_jual      numeric(14,2) NOT NULL DEFAULT 0,
  dijual          boolean NOT NULL DEFAULT true,   -- false untuk bahan baku
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE UNIQUE INDEX uq_produk_sku     ON produk (toko_id, sku)     WHERE sku IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_produk_barcode ON produk (toko_id, barcode) WHERE barcode IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE produk_varian (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  nama            varchar(100) NOT NULL,     -- "Large", "Merah / XL"
  sku             varchar(50),
  barcode         varchar(50),
  hpp             numeric(14,2) NOT NULL DEFAULT 0,
  harga_jual      numeric(14,2) NOT NULL DEFAULT 0,
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- Harga khusus per outlet (opsional, override harga_jual)
CREATE TABLE harga_outlet (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  varian_id       uuid REFERENCES produk_varian(id),
  harga_jual      numeric(14,2) NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE NULLS NOT DISTINCT (outlet_id, produk_id, varian_id)
);

CREATE TABLE grup_modifier (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(100) NOT NULL,     -- "Level Pedas", "Topping"
  min_pilih       int NOT NULL DEFAULT 0,
  maks_pilih      int NOT NULL DEFAULT 1,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE modifier (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grup_modifier_id  uuid NOT NULL REFERENCES grup_modifier(id),
  nama              varchar(100) NOT NULL,
  harga_tambahan    numeric(14,2) NOT NULL DEFAULT 0,
  urutan            int NOT NULL DEFAULT 0,
  aktif             boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE TABLE produk_grup_modifier (
  produk_id         uuid NOT NULL REFERENCES produk(id),
  grup_modifier_id  uuid NOT NULL REFERENCES grup_modifier(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (produk_id, grup_modifier_id)
);

-- Resep: 1 produk jadi memakai beberapa bahan baku
CREATE TABLE resep (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  varian_id       uuid REFERENCES produk_varian(id),
  bahan_id        uuid NOT NULL REFERENCES produk(id),
  qty             numeric(14,4) NOT NULL CHECK (qty > 0),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- =====================================================================
-- 4. MODUL STOK & PEMBELIAN
-- =====================================================================

-- Saldo stok saat ini per outlet (dihitung ulang dari mutasi_stok bila perlu)
CREATE TABLE stok (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  varian_id       uuid REFERENCES produk_varian(id),
  jumlah          numeric(14,4) NOT NULL DEFAULT 0,
  batas_minimum   numeric(14,4) NOT NULL DEFAULT 0,
  hpp_rata_rata   numeric(14,2) NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE NULLS NOT DISTINCT (outlet_id, produk_id, varian_id)
);

CREATE TABLE supplier (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(150) NOT NULL,
  kontak          varchar(150),
  no_hp           varchar(20),
  email           varchar(150),
  alamat          text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE pembelian (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  supplier_id     uuid REFERENCES supplier(id),
  nomor           varchar(50) NOT NULL,
  tanggal         date NOT NULL DEFAULT current_date,
  status          varchar(20) NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','dipesan','diterima','batal')),
  subtotal        numeric(14,2) NOT NULL DEFAULT 0,
  diskon          numeric(14,2) NOT NULL DEFAULT 0,
  pajak           numeric(14,2) NOT NULL DEFAULT 0,
  total           numeric(14,2) NOT NULL DEFAULT 0,
  status_bayar    varchar(20) NOT NULL DEFAULT 'belum'
                  CHECK (status_bayar IN ('belum','sebagian','lunas')),
  catatan         text,
  dibuat_oleh     uuid REFERENCES pengguna(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (toko_id, nomor)
);

CREATE TABLE item_pembelian (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pembelian_id    uuid NOT NULL REFERENCES pembelian(id),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  varian_id       uuid REFERENCES produk_varian(id),
  qty             numeric(14,4) NOT NULL CHECK (qty > 0),
  harga_satuan    numeric(14,2) NOT NULL DEFAULT 0,
  subtotal        numeric(14,2) NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE stok_opname (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  nomor           varchar(50) NOT NULL,
  tanggal         date NOT NULL DEFAULT current_date,
  status          varchar(20) NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','selesai','batal')),
  catatan         text,
  dibuat_oleh     uuid REFERENCES pengguna(id),
  disetujui_oleh  uuid REFERENCES pengguna(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (outlet_id, nomor)
);

CREATE TABLE item_opname (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stok_opname_id  uuid NOT NULL REFERENCES stok_opname(id),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  varian_id       uuid REFERENCES produk_varian(id),
  qty_sistem      numeric(14,4) NOT NULL,
  qty_fisik       numeric(14,4) NOT NULL,
  selisih         numeric(14,4) GENERATED ALWAYS AS (qty_fisik - qty_sistem) STORED,
  catatan         text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE transfer_stok (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  dari_outlet_id  uuid NOT NULL REFERENCES outlet(id),
  ke_outlet_id    uuid NOT NULL REFERENCES outlet(id),
  nomor           varchar(50) NOT NULL,
  status          varchar(20) NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','dikirim','diterima','batal')),
  dikirim_pada    timestamptz,
  diterima_pada   timestamptz,
  dibuat_oleh     uuid REFERENCES pengguna(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  CHECK (dari_outlet_id <> ke_outlet_id),
  UNIQUE (toko_id, nomor)
);

CREATE TABLE item_transfer (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_stok_id  uuid NOT NULL REFERENCES transfer_stok(id),
  produk_id         uuid NOT NULL REFERENCES produk(id),
  varian_id         uuid REFERENCES produk_varian(id),
  qty               numeric(14,4) NOT NULL CHECK (qty > 0),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

-- =====================================================================
-- 5. MODUL PENJUALAN
-- =====================================================================

CREATE TABLE pelanggan (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(150) NOT NULL,
  no_hp           varchar(20),
  email           varchar(150),
  tanggal_lahir   date,
  level_member_id uuid,
  poin            int NOT NULL DEFAULT 0,
  total_belanja   numeric(14,2) NOT NULL DEFAULT 0,
  catatan         text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE UNIQUE INDEX uq_pelanggan_hp ON pelanggan (toko_id, no_hp) WHERE no_hp IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE pajak (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(50) NOT NULL,      -- PPN, PB1, Service
  tipe            varchar(20) NOT NULL DEFAULT 'pajak' CHECK (tipe IN ('pajak','service')),
  persen          numeric(5,2) NOT NULL CHECK (persen >= 0),
  termasuk_harga  boolean NOT NULL DEFAULT false,
  urutan          int NOT NULL DEFAULT 0,    -- service dihitung dulu sebelum pajak
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE promo (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(100) NOT NULL,
  kode            varchar(30),
  tipe            varchar(20) NOT NULL CHECK (tipe IN ('persen','nominal')),
  nilai           numeric(14,2) NOT NULL CHECK (nilai >= 0),
  cakupan         varchar(20) NOT NULL DEFAULT 'transaksi' CHECK (cakupan IN ('transaksi','produk')),
  min_belanja     numeric(14,2) NOT NULL DEFAULT 0,
  maks_diskon     numeric(14,2),
  berlaku_mulai   timestamptz,
  berlaku_sampai  timestamptz,
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE promo_produk (
  promo_id        uuid NOT NULL REFERENCES promo(id),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (promo_id, produk_id)
);

CREATE TABLE promo_outlet (
  promo_id        uuid NOT NULL REFERENCES promo(id),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (promo_id, outlet_id)
);

CREATE TABLE metode_bayar (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(50) NOT NULL,
  tipe            varchar(20) NOT NULL
                  CHECK (tipe IN ('tunai','qris','kartu','transfer','ewallet','lainnya')),
  butuh_gateway   boolean NOT NULL DEFAULT false,  -- true untuk QRIS dinamis
  masuk_laci      boolean NOT NULL DEFAULT false,  -- true hanya untuk tunai
  urutan          int NOT NULL DEFAULT 0,
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE shift (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  perangkat_id    uuid REFERENCES perangkat(id),
  pengguna_id     uuid NOT NULL REFERENCES pengguna(id),
  dibuka_pada     timestamptz NOT NULL DEFAULT now(),
  ditutup_pada    timestamptz,
  modal_awal      numeric(14,2) NOT NULL DEFAULT 0,
  kas_seharusnya  numeric(14,2),
  kas_aktual      numeric(14,2),
  selisih         numeric(14,2),
  catatan         text,
  status          varchar(20) NOT NULL DEFAULT 'buka' CHECK (status IN ('buka','tutup')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE kas_shift (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id        uuid NOT NULL REFERENCES shift(id),
  jenis           varchar(10) NOT NULL CHECK (jenis IN ('masuk','keluar')),
  jumlah          numeric(14,2) NOT NULL CHECK (jumlah > 0),
  keterangan      text NOT NULL,
  dibuat_oleh     uuid REFERENCES pengguna(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE transaksi (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  shift_id        uuid REFERENCES shift(id),
  perangkat_id    uuid REFERENCES perangkat(id),
  pengguna_id     uuid NOT NULL REFERENCES pengguna(id),
  pelanggan_id    uuid REFERENCES pelanggan(id),
  tipe_order_id   uuid,
  meja_id         uuid,
  nomor_struk     varchar(50) NOT NULL,       -- mis. OUT1-HP1-20261009-0001
  tanggal         timestamptz NOT NULL DEFAULT now(),
  nomor_antrean   varchar(10),                -- mis. A-012
  status_pesanan  varchar(20) CHECK (status_pesanan IN ('baru','diproses','siap','diambil','dibatalkan')),
  status          varchar(20) NOT NULL DEFAULT 'selesai'
                  CHECK (status IN ('draft','tersimpan','selesai','void','refund_sebagian','refund')),
  subtotal        numeric(14,2) NOT NULL DEFAULT 0,
  total_diskon    numeric(14,2) NOT NULL DEFAULT 0,
  total_pajak     numeric(14,2) NOT NULL DEFAULT 0,
  pembulatan      numeric(14,2) NOT NULL DEFAULT 0,
  total           numeric(14,2) NOT NULL DEFAULT 0,
  total_bayar     numeric(14,2) NOT NULL DEFAULT 0,
  kembalian       numeric(14,2) NOT NULL DEFAULT 0,
  status_bayar    varchar(20) NOT NULL DEFAULT 'lunas'
                  CHECK (status_bayar IN ('lunas','sebagian','belum_bayar')),  -- kasbon
  sisa_tagihan    numeric(14,2) NOT NULL DEFAULT 0,
  jatuh_tempo     date,
  catatan         text,
  alasan_void     text,
  void_disetujui_oleh uuid REFERENCES pengguna(id),
  disinkron_pada  timestamptz,                -- NULL = belum tersync ke server
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (outlet_id, nomor_struk)
);

CREATE TABLE item_transaksi (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaksi_id    uuid NOT NULL REFERENCES transaksi(id),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  varian_id       uuid REFERENCES produk_varian(id),
  staf_id         uuid REFERENCES pengguna(id),  -- yang mengerjakan (usaha jasa)
  nama_produk     varchar(200) NOT NULL,      -- snapshot nama + varian
  qty             numeric(14,4) NOT NULL CHECK (qty > 0),
  harga_satuan    numeric(14,2) NOT NULL,     -- snapshot harga + modifier
  hpp_satuan      numeric(14,2) NOT NULL DEFAULT 0,
  diskon          numeric(14,2) NOT NULL DEFAULT 0,
  subtotal        numeric(14,2) NOT NULL,
  catatan         text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE item_transaksi_modifier (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_transaksi_id  uuid NOT NULL REFERENCES item_transaksi(id),
  modifier_id        uuid REFERENCES modifier(id),
  nama               varchar(100) NOT NULL,   -- snapshot
  harga              numeric(14,2) NOT NULL DEFAULT 0,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz
);

CREATE TABLE transaksi_pajak (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaksi_id    uuid NOT NULL REFERENCES transaksi(id),
  pajak_id        uuid REFERENCES pajak(id),
  nama            varchar(50) NOT NULL,
  persen          numeric(5,2) NOT NULL,
  jumlah          numeric(14,2) NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE transaksi_promo (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaksi_id    uuid NOT NULL REFERENCES transaksi(id),
  promo_id        uuid REFERENCES promo(id),
  nama            varchar(100) NOT NULL,
  jumlah_diskon   numeric(14,2) NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE pembayaran (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaksi_id    uuid NOT NULL REFERENCES transaksi(id),
  metode_bayar_id uuid NOT NULL REFERENCES metode_bayar(id),
  jumlah          numeric(14,2) NOT NULL CHECK (jumlah > 0),
  jenis           varchar(20) NOT NULL DEFAULT 'penuh'
                  CHECK (jenis IN ('penuh','dp','cicilan','pelunasan')),
  status          varchar(20) NOT NULL DEFAULT 'berhasil'
                  CHECK (status IN ('pending','berhasil','gagal','kedaluwarsa')),
  ref_gateway     varchar(150),               -- order_id / transaction_id dari Midtrans/Xendit
  payload_gateway jsonb,
  dibayar_pada    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE refund (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaksi_id    uuid NOT NULL REFERENCES transaksi(id),
  shift_id        uuid REFERENCES shift(id),
  metode_bayar_id uuid REFERENCES metode_bayar(id),
  nomor           varchar(50) NOT NULL,
  alasan          text NOT NULL,
  total           numeric(14,2) NOT NULL,
  kembalikan_stok boolean NOT NULL DEFAULT true,
  dibuat_oleh     uuid REFERENCES pengguna(id),
  disetujui_oleh  uuid REFERENCES pengguna(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE item_refund (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refund_id          uuid NOT NULL REFERENCES refund(id),
  item_transaksi_id  uuid NOT NULL REFERENCES item_transaksi(id),
  qty                numeric(14,4) NOT NULL CHECK (qty > 0),
  jumlah             numeric(14,2) NOT NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz
);

CREATE TABLE riwayat_poin (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pelanggan_id    uuid NOT NULL REFERENCES pelanggan(id),
  transaksi_id    uuid REFERENCES transaksi(id),
  poin            int NOT NULL,               -- + dapat, - tukar
  keterangan      text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- Log semua perubahan stok (sumber kebenaran untuk tabel stok)
CREATE TABLE mutasi_stok (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  varian_id       uuid REFERENCES produk_varian(id),
  batch_id        uuid,
  jenis           varchar(20) NOT NULL CHECK (jenis IN (
                    'stok_awal','pembelian','penjualan','refund','void',
                    'opname','transfer_masuk','transfer_keluar','penyesuaian','produksi')),
  qty             numeric(14,4) NOT NULL,     -- + masuk, - keluar
  hpp_satuan      numeric(14,2) NOT NULL DEFAULT 0,
  saldo_setelah   numeric(14,4),
  ref_tipe        varchar(30),                -- 'transaksi','pembelian','stok_opname',...
  ref_id          uuid,
  catatan         text,
  dibuat_oleh     uuid REFERENCES pengguna(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- =====================================================================
-- 6. MODUL TEKNIS
-- =====================================================================

CREATE TABLE sync_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  perangkat_id    uuid NOT NULL REFERENCES perangkat(id),
  arah            varchar(10) NOT NULL CHECK (arah IN ('push','pull')),
  mulai           timestamptz NOT NULL DEFAULT now(),
  selesai         timestamptz,
  jumlah_record   int NOT NULL DEFAULT 0,
  status          varchar(20) NOT NULL DEFAULT 'berjalan'
                  CHECK (status IN ('berjalan','berhasil','gagal','sebagian')),
  pesan_error     text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE audit_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid REFERENCES toko(id),
  pengguna_id     uuid REFERENCES pengguna(id),
  perangkat_id    uuid REFERENCES perangkat(id),
  aksi            varchar(30) NOT NULL,       -- create, update, delete, void, login, approve
  tabel           varchar(50),
  record_id       uuid,
  data_lama       jsonb,
  data_baru       jsonb,
  ip_address      inet,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifikasi (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  pengguna_id     uuid REFERENCES pengguna(id),  -- NULL = untuk semua owner
  jenis           varchar(30) NOT NULL,          -- stok_menipis, selisih_kas, langganan
  judul           varchar(150) NOT NULL,
  isi             text,
  ref_tipe        varchar(30),
  ref_id          uuid,
  dibaca_pada     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- =====================================================================
-- 7. MODUL FITUR LANGGANAN
-- =====================================================================

-- Daftar baku semua fitur yang bisa dikunci per paket
CREATE TABLE fitur (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kode            varchar(50) NOT NULL UNIQUE,   -- dipakai app: if (punyaFitur('tiket_dapur'))
  nama            varchar(100) NOT NULL,
  modul           varchar(30) NOT NULL,
  tingkat         int NOT NULL DEFAULT 0,         -- paket minimal: 0 Gratis, 1 Pro, 2 Bisnis
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE paket_fitur (
  paket_id        uuid NOT NULL REFERENCES paket(id),
  fitur_id        uuid NOT NULL REFERENCES fitur(id),
  batas           int,                            -- opsional, mis. kuota; NULL = tanpa batas
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (paket_id, fitur_id)
);

-- =====================================================================
-- 8. MODUL OPERASIONAL LANJUTAN
-- =====================================================================

-- Tipe pesanan: Makan di tempat, Bawa pulang, GoFood, GrabFood, dll
CREATE TABLE tipe_order (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  nama            varchar(50) NOT NULL,
  kanal           varchar(20) NOT NULL DEFAULT 'langsung'
                  CHECK (kanal IN ('makan_di_tempat','bawa_pulang','antar','online','langsung')),
  pakai_meja      boolean NOT NULL DEFAULT false,
  markup_persen   numeric(5,2) NOT NULL DEFAULT 0,   -- mis. harga ojol +20%
  urutan          int NOT NULL DEFAULT 0,
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- Service fee / pajak yang berlaku per tipe pesanan
CREATE TABLE tipe_order_pajak (
  tipe_order_id   uuid NOT NULL REFERENCES tipe_order(id),
  pajak_id        uuid NOT NULL REFERENCES pajak(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tipe_order_id, pajak_id)
);

-- Pajak khusus per produk (jika kosong, pakai pajak default toko)
CREATE TABLE produk_pajak (
  produk_id       uuid NOT NULL REFERENCES produk(id),
  pajak_id        uuid NOT NULL REFERENCES pajak(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (produk_id, pajak_id)
);

CREATE TABLE meja (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  nama            varchar(30) NOT NULL,      -- "A1", "Teras 3"
  area            varchar(50),
  kapasitas       int,
  urutan          int NOT NULL DEFAULT 0,
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE (outlet_id, nama)
);

-- Stasiun dapur/bar, masing-masing dengan printer tiket sendiri
CREATE TABLE stasiun_dapur (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  nama            varchar(50) NOT NULL,      -- "Dapur", "Bar"
  printer_alamat  varchar(100),              -- MAC Bluetooth atau IP printer
  lebar_kertas_mm int NOT NULL DEFAULT 58 CHECK (lebar_kertas_mm IN (58,80)),
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- Tiket pesanan dapur (bisa lebih dari satu per transaksi: pesan tambahan)
CREATE TABLE pesanan_dapur (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaksi_id      uuid NOT NULL REFERENCES transaksi(id),
  stasiun_dapur_id  uuid REFERENCES stasiun_dapur(id),
  urutan_kirim      int NOT NULL DEFAULT 1,  -- kiriman ke-1, ke-2 (tambah pesanan)
  status            varchar(20) NOT NULL DEFAULT 'baru'
                    CHECK (status IN ('baru','dimasak','siap','disajikan','dibatalkan')),
  dicetak_pada      timestamptz,
  siap_pada         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE TABLE item_pesanan_dapur (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pesanan_dapur_id   uuid NOT NULL REFERENCES pesanan_dapur(id),
  item_transaksi_id  uuid NOT NULL REFERENCES item_transaksi(id),
  qty                numeric(14,4) NOT NULL CHECK (qty > 0),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  deleted_at         timestamptz
);

-- Penghitung nomor antrean per outlet per hari.
-- Saat offline, HP membuat nomor dari penghitung lokalnya; bila 2+ HP kasir
-- di satu outlet, beri prefix per perangkat (A-012, B-007) agar tidak bentrok.
CREATE TABLE antrean_harian (
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  perangkat_id    uuid NOT NULL REFERENCES perangkat(id),
  tanggal         date NOT NULL,
  prefix          varchar(3) NOT NULL DEFAULT '',
  nomor_terakhir  int NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (outlet_id, perangkat_id, tanggal)
);

CREATE TABLE level_member (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id           uuid NOT NULL REFERENCES toko(id),
  nama              varchar(50) NOT NULL,      -- Silver, Gold, Platinum
  min_total_belanja numeric(14,2) NOT NULL DEFAULT 0,
  diskon_persen     numeric(5,2) NOT NULL DEFAULT 0,
  pengali_poin      numeric(5,2) NOT NULL DEFAULT 1,
  urutan            int NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE TABLE aturan_poin (
  toko_id             uuid PRIMARY KEY REFERENCES toko(id),
  nominal_per_poin    numeric(14,2) NOT NULL DEFAULT 10000,  -- belanja Rp10.000 = 1 poin
  nilai_tukar_poin    numeric(14,2) NOT NULL DEFAULT 100,    -- 1 poin = Rp100 saat ditukar
  min_tukar_poin      int NOT NULL DEFAULT 0,
  kedaluwarsa_hari    int,                                    -- NULL = tidak hangus
  aktif               boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz
);

CREATE TABLE survei (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  judul           varchar(150) NOT NULL,
  tampil_di       varchar(20) NOT NULL DEFAULT 'struk' CHECK (tampil_di IN ('struk','layar_pelanggan','whatsapp')),
  aktif           boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE pertanyaan_survei (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survei_id       uuid NOT NULL REFERENCES survei(id),
  teks            text NOT NULL,
  tipe            varchar(20) NOT NULL CHECK (tipe IN ('rating','pilihan','teks')),
  opsi            jsonb,                      -- untuk tipe pilihan
  wajib           boolean NOT NULL DEFAULT false,
  urutan          int NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE jawaban_survei (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survei_id       uuid NOT NULL REFERENCES survei(id),
  transaksi_id    uuid REFERENCES transaksi(id),
  pelanggan_id    uuid REFERENCES pelanggan(id),
  dijawab_pada    timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

CREATE TABLE item_jawaban_survei (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  jawaban_survei_id     uuid NOT NULL REFERENCES jawaban_survei(id),
  pertanyaan_survei_id  uuid NOT NULL REFERENCES pertanyaan_survei(id),
  nilai_angka           int,
  nilai_teks            text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  deleted_at            timestamptz
);

CREATE TABLE absensi (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  toko_id         uuid NOT NULL REFERENCES toko(id),
  outlet_id       uuid NOT NULL REFERENCES outlet(id),
  pengguna_id     uuid NOT NULL REFERENCES pengguna(id),
  perangkat_id    uuid REFERENCES perangkat(id),
  jam_masuk       timestamptz NOT NULL,
  jam_keluar      timestamptz,
  foto_masuk_url  text,
  foto_keluar_url text,
  lat_masuk       numeric(9,6),
  lng_masuk       numeric(9,6),
  status          varchar(20) NOT NULL DEFAULT 'hadir'
                  CHECK (status IN ('hadir','terlambat','izin','sakit','alpa')),
  catatan         text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- Isi produk bundling (produk dengan tipe = 'bundling')
CREATE TABLE bundling_item (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bundling_produk_id  uuid NOT NULL REFERENCES produk(id),
  produk_id           uuid NOT NULL REFERENCES produk(id),
  varian_id           uuid REFERENCES produk_varian(id),
  qty                 numeric(14,4) NOT NULL CHECK (qty > 0),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz,
  CHECK (bundling_produk_id <> produk_id)
);

-- Batch stok dengan tanggal kedaluwarsa (untuk produk lacak_kedaluwarsa = true)
CREATE TABLE batch_stok (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  outlet_id           uuid NOT NULL REFERENCES outlet(id),
  produk_id           uuid NOT NULL REFERENCES produk(id),
  varian_id           uuid REFERENCES produk_varian(id),
  pembelian_id        uuid REFERENCES pembelian(id),
  nomor_batch         varchar(50),
  tanggal_kedaluwarsa date NOT NULL,
  qty_awal            numeric(14,4) NOT NULL CHECK (qty_awal >= 0),
  qty_sisa            numeric(14,4) NOT NULL CHECK (qty_sisa >= 0),
  ingatkan_hari       int NOT NULL DEFAULT 30,   -- notifikasi H-30
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz
);

-- Harga grosir bertingkat: beli >= min_qty dapat harga ini
CREATE TABLE harga_grosir (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  produk_id       uuid NOT NULL REFERENCES produk(id),
  varian_id       uuid REFERENCES produk_varian(id),
  outlet_id       uuid REFERENCES outlet(id),   -- NULL = berlaku di semua outlet
  min_qty         numeric(14,4) NOT NULL CHECK (min_qty > 1),
  harga           numeric(14,2) NOT NULL CHECK (harga >= 0),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  UNIQUE NULLS NOT DISTINCT (produk_id, varian_id, outlet_id, min_qty)
);

-- Relasi ke tabel yang dibuat setelah tabel induknya
ALTER TABLE kategori    ADD CONSTRAINT fk_kategori_stasiun  FOREIGN KEY (stasiun_dapur_id) REFERENCES stasiun_dapur(id);
ALTER TABLE pelanggan   ADD CONSTRAINT fk_pelanggan_level   FOREIGN KEY (level_member_id)  REFERENCES level_member(id);
ALTER TABLE transaksi   ADD CONSTRAINT fk_transaksi_tipe    FOREIGN KEY (tipe_order_id)    REFERENCES tipe_order(id);
ALTER TABLE transaksi   ADD CONSTRAINT fk_transaksi_meja    FOREIGN KEY (meja_id)          REFERENCES meja(id);
ALTER TABLE mutasi_stok ADD CONSTRAINT fk_mutasi_batch      FOREIGN KEY (batch_id)         REFERENCES batch_stok(id);

-- =====================================================================
-- INDEX (filter per toko, pull sync berdasarkan updated_at, laporan)
-- =====================================================================

CREATE INDEX ix_outlet_toko          ON outlet (toko_id);
CREATE INDEX ix_pengguna_toko        ON pengguna (toko_id);
CREATE INDEX ix_kategori_toko        ON kategori (toko_id, updated_at);
CREATE INDEX ix_produk_toko_upd      ON produk (toko_id, updated_at);
CREATE INDEX ix_produk_kategori      ON produk (kategori_id);
CREATE INDEX ix_varian_produk        ON produk_varian (produk_id);
CREATE INDEX ix_modifier_grup        ON modifier (grup_modifier_id);
CREATE INDEX ix_resep_produk         ON resep (produk_id);
CREATE INDEX ix_stok_outlet_upd      ON stok (outlet_id, updated_at);
CREATE INDEX ix_pelanggan_toko_upd   ON pelanggan (toko_id, updated_at);
CREATE INDEX ix_shift_outlet         ON shift (outlet_id, dibuka_pada);
CREATE INDEX ix_shift_buka           ON shift (outlet_id) WHERE status = 'buka';
CREATE INDEX ix_transaksi_outlet_tgl ON transaksi (outlet_id, tanggal);
CREATE INDEX ix_transaksi_shift      ON transaksi (shift_id);
CREATE INDEX ix_transaksi_pelanggan  ON transaksi (pelanggan_id);
CREATE INDEX ix_transaksi_belum_sync ON transaksi (perangkat_id) WHERE disinkron_pada IS NULL;
CREATE INDEX ix_item_trx_transaksi   ON item_transaksi (transaksi_id);
CREATE INDEX ix_item_trx_produk      ON item_transaksi (produk_id);
CREATE INDEX ix_pembayaran_trx       ON pembayaran (transaksi_id);
CREATE INDEX ix_pembayaran_ref       ON pembayaran (ref_gateway) WHERE ref_gateway IS NOT NULL;
CREATE INDEX ix_refund_trx           ON refund (transaksi_id);
CREATE INDEX ix_mutasi_produk        ON mutasi_stok (outlet_id, produk_id, created_at);
CREATE INDEX ix_mutasi_ref           ON mutasi_stok (ref_tipe, ref_id);
CREATE INDEX ix_item_pembelian       ON item_pembelian (pembelian_id);
CREATE INDEX ix_item_opname          ON item_opname (stok_opname_id);
CREATE INDEX ix_item_transfer        ON item_transfer (transfer_stok_id);
CREATE INDEX ix_audit_toko_tgl       ON audit_log (toko_id, created_at);
CREATE INDEX ix_audit_record         ON audit_log (tabel, record_id);
CREATE INDEX ix_notif_belum_baca     ON notifikasi (toko_id, pengguna_id) WHERE dibaca_pada IS NULL;
CREATE INDEX ix_sync_perangkat       ON sync_log (perangkat_id, mulai);
CREATE INDEX ix_tipe_order_toko      ON tipe_order (toko_id, updated_at);
CREATE INDEX ix_meja_outlet          ON meja (outlet_id);
CREATE INDEX ix_pesanan_dapur_trx    ON pesanan_dapur (transaksi_id);
CREATE INDEX ix_pesanan_dapur_aktif  ON pesanan_dapur (stasiun_dapur_id) WHERE status IN ('baru','dimasak');
CREATE INDEX ix_item_pesanan_dapur   ON item_pesanan_dapur (pesanan_dapur_id);
CREATE INDEX ix_transaksi_kasbon     ON transaksi (toko_id, jatuh_tempo) WHERE status_bayar <> 'lunas';
CREATE INDEX ix_transaksi_meja_buka  ON transaksi (meja_id) WHERE status = 'tersimpan';
CREATE INDEX ix_level_member_toko    ON level_member (toko_id);
CREATE INDEX ix_jawaban_survei       ON jawaban_survei (survei_id, dijawab_pada);
CREATE INDEX ix_item_jawaban         ON item_jawaban_survei (jawaban_survei_id);
CREATE INDEX ix_absensi_pengguna     ON absensi (pengguna_id, jam_masuk);
CREATE INDEX ix_bundling_item        ON bundling_item (bundling_produk_id);
CREATE INDEX ix_batch_kedaluwarsa    ON batch_stok (outlet_id, tanggal_kedaluwarsa) WHERE qty_sisa > 0;
CREATE INDEX ix_harga_grosir_produk  ON harga_grosir (produk_id);

-- =====================================================================
-- TRIGGER updated_at untuk semua tabel yang punya kolom updated_at
-- =====================================================================

DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'updated_at'
  LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON %1$I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t);
  END LOOP;
END $$;

-- =====================================================================
-- DATA AWAL (seed)
-- =====================================================================

-- Harga contoh, silakan sesuaikan
INSERT INTO paket (nama, urutan, harga_bulanan, harga_tahunan, maks_outlet, maks_pengguna, maks_produk) VALUES
  ('Gratis', 0, 0,      0,       1,    2,    100),
  ('Pro',    1, 59000,  590000,  NULL, 10,   NULL),
  ('Bisnis', 2, 99000,  990000,  NULL, NULL, NULL);

-- Daftar fitur baku. tingkat = paket minimal yang membuka fitur ini.
INSERT INTO fitur (kode, nama, modul, tingkat) VALUES
  ('pos',                    'Kasir (POS)',                        'penjualan', 0),
  ('cetak_struk',            'Cetak struk',                        'penjualan', 0),
  ('scan_barcode',           'Scan produk',                        'produk',    0),
  ('kelola_stok',            'Kelola stok produk',                 'stok',      0),
  ('kelola_pelanggan',       'Kelola pelanggan',                   'pelanggan', 0),
  ('laporan_dasar',          'Laporan penjualan',                  'laporan',   0),
  ('qris',                   'Pembayaran QRIS',                    'penjualan', 1),
  ('kasbon',                 'Bayar dengan utang (kasbon)',        'penjualan', 1),
  ('tren_penjualan',         'Tren penjualan',                     'laporan',   1),
  ('multi_outlet',           'Multi-outlet (biaya per outlet)',    'bisnis',    1),
  ('resep',                  'Bahan baku dan resep',               'stok',      1),
  ('ekspor_impor',           'Ekspor dan unggah template',         'produk',    1),
  ('diskon',                 'Kelola diskon',                      'penjualan', 1),
  ('pajak_per_produk',       'Pajak per produk',                   'penjualan', 1),
  ('tipe_order',             'Tipe pesanan',                       'penjualan', 1),
  ('kelola_karyawan',        'Kelola karyawan',                    'pengguna',  1),
  ('poin_loyalitas',         'Poin loyalitas pelanggan',           'pelanggan', 1),
  ('diskon_member',          'Diskon member',                      'pelanggan', 1),
  ('survei',                 'Survei pelanggan',                   'pelanggan', 1),
  ('absensi',                'Absensi karyawan',                   'pengguna',  1),
  ('struk_ringkas',          'Struk ringkas',                      'penjualan', 2),
  ('tiket_dapur',            'Cetak tiket dapur',                  'penjualan', 2),
  ('catatan_struk',          'Catatan tambahan di struk',          'penjualan', 2),
  ('service_per_tipe_order', 'Service fee per tipe pesanan',       'penjualan', 2),
  ('status_pesanan',         'Status pesanan',                     'penjualan', 2),
  ('dp_kasbon',              'DP untuk kasbon',                    'penjualan', 2),
  ('nomor_antrean',          'Nomor antrean',                      'penjualan', 2),
  ('label_pembayaran',       'Label metode pembayaran',            'penjualan', 2),
  ('logo_struk',             'Logo usaha di struk',                'penjualan', 2),
  ('bundling',               'Kelola bundling produk',             'produk',    2),
  ('pengingat_kedaluwarsa',  'Pengingat kedaluwarsa produk',       'stok',      2),
  ('harga_grosir',           'Harga grosir',                       'produk',    2);

-- Setiap paket membuka semua fitur dengan tingkat <= urutan paketnya
INSERT INTO paket_fitur (paket_id, fitur_id)
SELECT p.id, f.id FROM paket p JOIN fitur f ON f.tingkat <= p.urutan;

INSERT INTO izin (kode, modul, deskripsi) VALUES
  ('transaksi.buat',        'penjualan', 'Membuat transaksi'),
  ('transaksi.diskon',      'penjualan', 'Memberi diskon manual'),
  ('transaksi.void',        'penjualan', 'Membatalkan transaksi'),
  ('transaksi.refund',      'penjualan', 'Melakukan refund'),
  ('shift.buka_tutup',      'penjualan', 'Membuka dan menutup shift'),
  ('kas.keluar_masuk',      'penjualan', 'Mencatat kas keluar/masuk'),
  ('produk.kelola',         'produk',    'Tambah/ubah/hapus produk'),
  ('stok.kelola',           'stok',      'Stok masuk, opname, transfer'),
  ('pembelian.kelola',      'stok',      'Mengelola pembelian supplier'),
  ('pelanggan.kelola',      'penjualan', 'Mengelola data pelanggan'),
  ('promo.kelola',          'penjualan', 'Mengelola promo dan pajak'),
  ('laporan.lihat',         'laporan',   'Melihat laporan'),
  ('pengguna.kelola',       'pengaturan','Mengelola karyawan dan role'),
  ('pengaturan.kelola',     'pengaturan','Mengubah pengaturan toko/outlet');

INSERT INTO role (nama, is_system) VALUES ('Owner', true), ('Manajer', true), ('Kasir', true);

-- Owner: semua izin
INSERT INTO role_izin (role_id, izin_id)
SELECT r.id, i.id FROM role r CROSS JOIN izin i WHERE r.nama = 'Owner' AND r.is_system;

-- Manajer: semua kecuali kelola pengguna & pengaturan
INSERT INTO role_izin (role_id, izin_id)
SELECT r.id, i.id FROM role r CROSS JOIN izin i
WHERE r.nama = 'Manajer' AND r.is_system
  AND i.kode NOT IN ('pengguna.kelola','pengaturan.kelola');

-- Kasir: hanya transaksi dasar
INSERT INTO role_izin (role_id, izin_id)
SELECT r.id, i.id FROM role r CROSS JOIN izin i
WHERE r.nama = 'Kasir' AND r.is_system
  AND i.kode IN ('transaksi.buat','shift.buka_tutup','kas.keluar_masuk','pelanggan.kelola');
"""


def upgrade() -> None:
    for statement in split_statements(_DDL):
        op.execute(statement)


def downgrade() -> None:
    # Migrasi pertama - downgrade = buang ulang seluruh schema public.
    # Sengaja destruktif (tidak drop tabel satu-satu sesuai urutan FK)
    # karena ini migrasi paling awal, tidak ada data produksi yang
    # diharapkan hilang selain hasil migrasi ini sendiri.
    op.execute("DROP SCHEMA public CASCADE")
    op.execute("CREATE SCHEMA public")
