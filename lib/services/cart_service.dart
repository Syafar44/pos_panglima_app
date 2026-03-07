import 'package:dio/dio.dart';

class CartService {
  final Dio dio;

  CartService(this.dio);

  Future<Response> postCart(Map<String, dynamic> payload) {
    return dio.post('/pos/cart', data: payload);
  }

  Future<Response> getCart() {
    return dio.get("/pos/cart");
  }

  Future<Response> detailCart(int id) {
    return dio.get("/pos/cart/detail/$id");
  }

  Future<Response> plusCart(int id) {
    return dio.get("/pos/cart/plus-buttons/$id");
  }

  Future<Response> minusCart(int id) {
    return dio.get("/pos/cart/minus-buttons/$id");
  }

  Future<Response> updateCart(int id, Map<String, dynamic> payload) {
    return dio.patch("/pos/cart/update/$id", data: payload);
  }

  Future<Response> deleteCart(int id) {
    return dio.delete("/pos/cart/delete/$id");
  }
}
