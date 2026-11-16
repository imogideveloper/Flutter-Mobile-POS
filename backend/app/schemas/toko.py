from pydantic import BaseModel


class LogoOut(BaseModel):
    logo_url: str


class QrisOut(BaseModel):
    qris_url: str | None
