import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  final Dio dio = Dio();
  final storage = const FlutterSecureStorage();

  ApiClient() {
    dio.options = BaseOptions(
      baseUrl: dotenv.env['BASE_URL']!,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        // "Content-Type": "application/json",
        "apikey": dotenv.env['API_KEY']!,
      },
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await storage.read(key: "accessToken");
          if (token != null) {
            options.headers["Authorization"] = "Bearer $token";
          }
          handler.next(options);
        },
        onError: (e, handler) {
          handler.next(e);
        },
      ),
    );
  }

  Future<void> saveToken(String token) async {
    await storage.write(key: "accessToken", value: token);
  }

  Future<void> clearToken() async {
    await storage.delete(key: "accessToken");
  }

  Future<String?> getToken() async {
    return await storage.read(key: "accessToken");
  }
}
