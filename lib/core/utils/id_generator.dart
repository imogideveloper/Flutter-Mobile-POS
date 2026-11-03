import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUID v4, dibuat di HP saat offline sebagai primary key baris baru.
String generateId() => _uuid.v4();
