import 'package:dio/dio.dart';

class InventoryService {
  final Dio dio;

  InventoryService(this.dio);

  Future<Response> getList(String params) {
    return dio.get("/inventory/inventory_transfer?$params");
  }

  Future<Response> getDetail(int id) {
    return dio.get("/inventory/inventory_transfer/$id");
  }

  Future<Response> patchRealisasi(int id, Map<String, dynamic> payload) {
    return dio.patch("/inventory/inventory_transfer/$id/realisasi", data: payload);
  }
}
