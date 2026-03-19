import 'package:dio/dio.dart';

class OrderService {
  final Dio dio;

  OrderService(this.dio);

  Future<Response> postOrder(Map<String, dynamic> payload) {
    return dio.post('/pos/order', data: payload);
  }

  Future<Response> postLampiran(FormData formData) {
    return dio.post(
      '/pos/order-lampiran',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  Future<Response> getOrderDetail(int id) {
    return dio.get('/pos/order/$id');
  }

  Future<Response> checkVoucher(Map<String, dynamic> payload) {
    return dio.post('/pos/voucher/check', data: payload);
  }

  Future<Response> getOrderList(
    int userId,
    int page,
    int limit,
    String? search,
  ) {
    return dio.get(
      '/pos/order?users_id=$userId&page=$page&limit=$limit&search=$search',
    );
  }
}
