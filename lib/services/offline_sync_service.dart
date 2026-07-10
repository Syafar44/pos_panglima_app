import 'package:dio/dio.dart';

class OfflineSyncService {
  final Dio dio;

  OfflineSyncService(this.dio);

  Future<Response> getOfflineSync() {
    return dio.get("/pos/offline-sync");
  }

  Future<Response> postOrderSync(List<Map<String, dynamic>> orders) {
    return dio.post("/pos/order/sync", data: orders);
  }
}
