import 'package:dio/dio.dart';

class AuthService {
  final Dio dio;

  AuthService(this.dio);

  Future<Response> register(Map<String, dynamic> payload) {
    return dio.post('/auth/register', data: payload);
  }

  Future<Response> activation(Map<String, dynamic> payload) {
    return dio.post("/auth/activation", data: payload);
  }

  Future<Response> login(Map<String, dynamic> payload) {
    return dio.post("/auth", data: payload);
  }

  Future<Response> getProfile() {
    return dio.get("/me");
  }
}
