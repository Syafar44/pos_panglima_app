import 'package:dio/dio.dart';

class MethodService {
  final Dio dio;

  MethodService(this.dio);

  Future<Response> getPaymentMethods() {
    return dio.get("/pos/payment-method");
  }

  Future<Response> getOrderMethods() {
    return dio.get("/pos/order-method");
  }
}
