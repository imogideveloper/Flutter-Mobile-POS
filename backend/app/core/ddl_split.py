"""Dipakai migrasi Alembic di alembic/versions/ - asyncpg (lihat
alembic/env.py) menolak mengirim banyak statement sekaligus lewat
prepared statement ("cannot insert multiple commands into a prepared
statement"), beda dari psycopg2 yang menerima DDL mentah apa adanya. Baru
ketahuan saat `alembic upgrade head` benar-benar dijalankan ke Postgres
sungguhan (sebelumnya cuma dites lewat SQLite create_all(), bukan lewat
Alembic - lihat README). split_statements() memecah blok SQL mentah jadi
per-statement, menghormati string literal ('' sbg escape), blok
dollar-quote ($$...$$ - fungsi/DO block), dan komentar baris (--) supaya
';' di dalamnya tidak dianggap pemisah statement.

Modul ini SENGAJA ditaruh di app/core/ (bukan alembic/) - file migrasi
dimuat Alembic lewat load_module_py dengan nama module sintetis, jadi
import relatif ("from .. import x") gagal (ImportError: attempted
relative import with no known parent package); app.core sudah terbukti
bisa diimpor absolut dari alembic/env.py (lihat `import app.models` di
sana), jadi modul util kecil ini ikut ditaruh di package yang sama.
"""


def split_statements(sql: str) -> list[str]:
    statements: list[str] = []
    buffer: list[str] = []
    in_single_quote = False
    in_dollar_quote = False
    in_line_comment = False
    i = 0
    n = len(sql)
    while i < n:
        ch = sql[i]
        if in_line_comment:
            buffer.append(ch)
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue
        if in_dollar_quote:
            buffer.append(ch)
            if ch == "$" and sql[i : i + 2] == "$$":
                buffer.append(sql[i + 1])
                i += 2
                in_dollar_quote = False
                continue
            i += 1
            continue
        if in_single_quote:
            buffer.append(ch)
            if ch == "'":
                if sql[i + 1 : i + 2] == "'":
                    buffer.append("'")
                    i += 2
                    continue
                in_single_quote = False
            i += 1
            continue
        # Tidak di dalam quote/comment/dollar-block apa pun.
        if ch == "-" and sql[i : i + 2] == "--":
            in_line_comment = True
            buffer.append(ch)
            i += 1
            continue
        if ch == "'":
            in_single_quote = True
            buffer.append(ch)
            i += 1
            continue
        if ch == "$" and sql[i : i + 2] == "$$":
            in_dollar_quote = True
            buffer.append(sql[i : i + 2])
            i += 2
            continue
        if ch == ";":
            statements.append("".join(buffer))
            buffer = []
            i += 1
            continue
        buffer.append(ch)
        i += 1
    sisa = "".join(buffer).strip()
    if sisa:
        statements.append(sisa)
    return [s for s in statements if s.strip()]
