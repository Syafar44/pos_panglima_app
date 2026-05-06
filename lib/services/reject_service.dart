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
}
