"""Penyimpanan kode OTP sementara (TTL) - Redis di produksi (sesuai tech
stack #3.2), in-memory di test/dev lewat dependency override (lihat
tests/conftest.py) supaya test tidak butuh Redis sungguhan."""

import time
from abc import ABC, abstractmethod


class OtpStore(ABC):
    @abstractmethod
    async def simpan(self, no_hp: str, kode: str, ttl_detik: int) -> None: ...

    @abstractmethod
    async def ambil(self, no_hp: str) -> str | None: ...

    @abstractmethod
    async def hapus(self, no_hp: str) -> None: ...


class InMemoryOtpStore(OtpStore):
    """Dipakai dev lokal tanpa Redis & semua test. TIDAK untuk produksi
    multi-proses (state tidak dibagi antar worker)."""

    def __init__(self) -> None:
        self._data: dict[str, tuple[str, float]] = {}

    async def simpan(self, no_hp: str, kode: str, ttl_detik: int) -> None:
        self._data[no_hp] = (kode, time.time() + ttl_detik)

    async def ambil(self, no_hp: str) -> str | None:
        entry = self._data.get(no_hp)
        if entry is None:
            return None
        kode, kedaluwarsa = entry
        if time.time() > kedaluwarsa:
            del self._data[no_hp]
            return None
        return kode

    async def hapus(self, no_hp: str) -> None:
        self._data.pop(no_hp, None)


class RedisOtpStore(OtpStore):
    def __init__(self, redis_url: str) -> None:
        import redis.asyncio as redis

        self._client = redis.from_url(redis_url)

    def _key(self, no_hp: str) -> str:
        return f"otp:{no_hp}"

    async def simpan(self, no_hp: str, kode: str, ttl_detik: int) -> None:
        await self._client.set(self._key(no_hp), kode, ex=ttl_detik)

    async def ambil(self, no_hp: str) -> str | None:
        value = await self._client.get(self._key(no_hp))
        return value.decode() if value else None

    async def hapus(self, no_hp: str) -> None:
        await self._client.delete(self._key(no_hp))


_singleton: OtpStore | None = None


def get_otp_store() -> OtpStore:
    global _singleton
    if _singleton is None:
        from app.core.config import get_settings

        settings = get_settings()
        _singleton = RedisOtpStore(settings.redis_url) if settings.environment == "production" else InMemoryOtpStore()
    return _singleton
