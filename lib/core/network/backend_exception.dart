/// Error dari backend atau jaringan - dibungkus dari DioException supaya
/// lapisan atas (repository/UI) tidak perlu tahu soal Dio sama sekali.
class BackendException implements Exception {
  const BackendException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  bool get tidakAdaKoneksi => statusCode == null;

  @override
  String toString() => message;
}
