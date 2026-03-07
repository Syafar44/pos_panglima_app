import 'package:dio/dio.dart';

class MenuService {
  final Dio dio;

  MenuService(this.dio);

  Future<Response> getList() {
    return dio.get("/pos/menu/list");
  }

  Future<Response> getDetail(int id) {
    return dio.get("/pos/menu/detail/$id");
  }
}
