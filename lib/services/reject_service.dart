import 'package:dio/dio.dart';

class RejectService {
  final Dio dio;

  RejectService(this.dio);

  Future<Response> getListItems({String? search, int limit = 20}) {
    return dio.get("/pos/item?page=1&limit=$limit&search=${search ?? ''}");
  }

  Future<Response> getDetailItems(int id) {
    return dio.get("/pos/item/$id");
  }

  /// NEW API

  Future<Response> postReject(Map<String, dynamic> payload) {
    return dio.post('/pos/reject', data: payload);
  }

  Future<Response> getListReject(
    int customerId, {
    int page = 1,
    int limit = 20,
  }) {
    return dio.get(
      "/pos/reject?page=$page&limit=$limit&customer_id=$customerId",
    );
  }

  Future<Response> getDetailReject(int id) {
    return dio.get("/pos/reject/$id");
  }

  Future<Response> addLinesReject(int id, Map<String, dynamic> payload) {
    return dio.post("/pos/reject/$id/lines", data: payload);
  }

  Future<Response> deleteLinesReject(int id, int lineId) {
    return dio.delete("/pos/reject/$id/lines/$lineId");
  }

  Future<Response> postRejectDraft(int id, Map<String, dynamic> payload) {
    return dio.post('/pos/reject/$id/draft', data: payload);
  }

  Future<Response> postRejectSubmit(int id) {
    return dio.post('/pos/reject/$id/submit');
  }

  // Lampiran
  Future<Response> getLampiran(String fileUrl) {
    return dio.get(
      fileUrl,
      options: Options(responseType: ResponseType.bytes),
    );
  }

  Future<Response> postLampiran(int id, FormData payload) {
    return dio.post(
      "/pos/reject/$id/lampirans",
      data: payload,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
  }

  Future<Response> deleteLampiran(int id, int lampiranId) {
    return dio.delete("/pos/reject/$id/lampirans/$lampiranId");
  }
}
