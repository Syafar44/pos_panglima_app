import 'package:dio/dio.dart';

class InventoryService {
  final Dio dio;

  InventoryService(this.dio);

  Future<Response> getList({
    required int page,
    required int limit,
    required String outletHubId,
  }) {
    return dio.get(
      "/inventory/inventory_transfer",
      queryParameters: {
        'page': page,
        'limit': limit,
        'to_outlet_hub_id': outletHubId,
      },
    );
  }

  Future<Response> getDetail(int id) {
    return dio.get("/inventory/inventory_transfer/$id");
  }

  Future<Response> patchRealisasi(int id, Map<String, dynamic> payload) {
    return dio.patch(
      "/inventory/inventory_transfer/$id/realisasi",
      data: payload,
    );
  }

  /// Realisasi sebagian (Gerai Panglima). `lines` = [{ id, realisasi }, ...]
  Future<Response> realisasiPartial(int id, List<Map<String, dynamic>> lines) {
    return dio.patch(
      "/inventory/inventory_transfer/$id/realisasi-partial",
      data: {"inventory_transfer_lines": lines},
    );
  }

  /// Tutup/selesaikan realisasi (Gerai Panglima).
  Future<Response> realisasiClose(int id, int approveUsersId) {
    return dio.patch(
      "/inventory/inventory_transfer/$id/close",
      data: {"approve_users_id": approveUsersId},
    );
  }
}
