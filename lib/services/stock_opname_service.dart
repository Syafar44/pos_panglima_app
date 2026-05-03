import 'package:dio/dio.dart';

class StockOpnameService {
  final Dio dio;

  StockOpnameService(this.dio);

  Future<Response> generateSO(Map<String, dynamic> payload) {
    return dio.post("/pos/daily-stock-opname/generate", data: payload);
  }

  Future<Response> getListSO(int page, int limit, int outletHubId) {
    return dio.get(
      "/pos/daily-stock-opname?page=$page&limit=$limit&outlet_hub_id=$outletHubId",
    );
  }

  Future<Response> getDetailSO(int id) {
    return dio.get("/pos/daily-stock-opname/$id");
  }

  Future<Response> updateDraftSO(int id, Map<String, dynamic> payload) {
    return dio.patch("/pos/daily-stock-opname/$id/lines", data: payload);
  }

  Future<Response> submitSO(int id) {
    return dio.post("/pos/daily-stock-opname/$id/submit");
  }
}
