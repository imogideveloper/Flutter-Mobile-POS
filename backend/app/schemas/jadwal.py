import re
import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

ShiftJadwal = Literal["libur", "pagi", "siang"]
JenisCuti = Literal["cuti", "sakit", "izin"]

_JAM = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")

# Jam bawaan bila klien hanya mengirim shift tanpa jam (dapat diubah per karyawan).
JAM_BAWAAN = {"pagi": ("07:00", "15:00"), "siang": ("14:00", "22:00")}


class HariJadwalIn(BaseModel):
    hari: int = Field(ge=1, le=7)  # 1 = Senin ... 7 = Minggu
    shift: ShiftJadwal
    jam_mulai: str | None = None
    jam_selesai: str | None = None

    @field_validator("jam_mulai", "jam_selesai")
    @classmethod
    def _format_jam(cls, nilai: str | None) -> str | None:
        if nilai is not None and not _JAM.match(nilai):
            raise ValueError("Jam harus berformat HH:MM (00:00 sampai 23:59)")
        return nilai

    @model_validator(mode="after")
    def _isi_dan_urutan_jam(self) -> "HariJadwalIn":
        if self.shift == "libur":
            self.jam_mulai = None
            self.jam_selesai = None
            return self
        mulai, selesai = JAM_BAWAAN[self.shift]
        self.jam_mulai = self.jam_mulai or mulai
        self.jam_selesai = self.jam_selesai or selesai
        if self.jam_selesai <= self.jam_mulai:
            raise ValueError("Jam selesai harus setelah jam mulai (shift lintas tengah malam belum didukung)")
        return self


class JadwalMingguIn(BaseModel):
    hari: list[HariJadwalIn] = Field(min_length=1, max_length=7)

    @model_validator(mode="after")
    def _hari_unik(self) -> "JadwalMingguIn":
        nomor = [h.hari for h in self.hari]
        if len(nomor) != len(set(nomor)):
            raise ValueError("Hari tidak boleh dobel")
        return self


class HariJadwalOut(BaseModel):
    hari: int
    shift: str
    jam_mulai: str | None
    jam_selesai: str | None


class JadwalKaryawanOut(BaseModel):
    pengguna_id: uuid.UUID
    pengguna_nama: str
    hari: list[HariJadwalOut]  # hanya hari yang sudah diatur


class JadwalHariIniOut(BaseModel):
    tanggal: date
    hari: int
    shift: str | None  # null = belum diatur
    jam_mulai: str | None
    jam_selesai: str | None
    cuti: str | None  # jenis pengajuan yang disetujui dan mencakup tanggal ini


class JadwalSayaOut(BaseModel):
    hari: list[HariJadwalOut]
    hari_ini: JadwalHariIniOut


class CutiIn(BaseModel):
    jenis: JenisCuti
    tanggal_mulai: date
    tanggal_selesai: date
    alasan: str | None = Field(default=None, max_length=300)

    @model_validator(mode="after")
    def _rentang(self) -> "CutiIn":
        if self.tanggal_selesai < self.tanggal_mulai:
            raise ValueError("Tanggal selesai lebih awal dari tanggal mulai")
        if (self.tanggal_selesai - self.tanggal_mulai).days > 60:
            raise ValueError("Satu pengajuan maksimal 61 hari")
        return self


class KeputusanCutiIn(BaseModel):
    setuju: bool
    catatan: str | None = Field(default=None, max_length=300)


class CutiOut(BaseModel):
    id: uuid.UUID
    pengguna_id: uuid.UUID
    pengguna_nama: str
    jenis: str
    tanggal_mulai: date
    tanggal_selesai: date
    alasan: str | None
    status: str
    diputuskan_oleh: uuid.UUID | None
    diputuskan_pada: datetime | None
    catatan_keputusan: str | None
