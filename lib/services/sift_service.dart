import 'package:dio/dio.dart';

class SiftService {
  final Dio dio;

  SiftService(this.dio);

  Future<Response> startShift(Map<String, dynamic> payload) {
    return dio.post('/pos/shifts', data: payload);
  }

  Future<Response> endShift(int id, Map<String, dynamic> payload) {
    return dio.patch("/pos/shifts/$id", data: payload);
  }
}
