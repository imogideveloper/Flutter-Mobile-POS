from pydantic import BaseModel


class LogoOut(BaseModel):
    logo_url: str
