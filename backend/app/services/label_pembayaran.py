"""Label tujuan pembayaran (IMOGI no. 18): daftar tujuan uang untuk rekonsiliasi,
mis. QRIS -> GoPay, OVO, ShopeePay, BCA. Disimpan sebagai teks dipisah koma di
`metode_bayar.label_tujuan`; kasir memilih satu saat menerima pembayaran."""

MAKS_LABEL = 10
MAKS_PANJANG_LABEL = 30
TIPE_BOLEH_LABEL = ("qris", "ewallet", "transfer", "kartu")


def normalisasi_label_tujuan(mentah: str | None) -> str | None:
    """Rapikan daftar label: potong spasi, buang kosong dan duplikat (tanpa membedakan
    huruf besar/kecil). Mengembalikan None bila kosong. Melempar ValueError bila
    terlalu banyak atau satu label terlalu panjang."""
    if mentah is None:
        return None
    hasil: list[str] = []
    terlihat: set[str] = set()
    for bagian in mentah.split(","):
        label = " ".join(bagian.split())
        if not label or label.lower() in terlihat:
            continue
        if len(label) > MAKS_PANJANG_LABEL:
            raise ValueError(f"Label '{label[:12]}...' lebih dari {MAKS_PANJANG_LABEL} karakter")
        terlihat.add(label.lower())
        hasil.append(label)
    if len(hasil) > MAKS_LABEL:
        raise ValueError(f"Maksimal {MAKS_LABEL} label per metode bayar")
    return ",".join(hasil) or None
