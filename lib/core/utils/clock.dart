/// Epoch milidetik UTC - format waktu yang dipakai di semua kolom
/// created_at/updated_at/deleted_at pada database lokal.
int nowEpochMs() => DateTime.now().toUtc().millisecondsSinceEpoch;
