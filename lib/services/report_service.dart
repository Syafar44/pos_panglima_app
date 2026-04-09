import 'package:dio/dio.dart';

class ReportService {
  final Dio dio;

  ReportService(this.dio);

  Future<Response> getPenerimaan(int posShiftsId) {
    return dio.get(
      "/pos/report/outlet/penerimaan/summary?pos_shifts_id=$posShiftsId",
    );
  }

  Future<Response> getDetailPenerimaan(
    int posShiftsId,
    int posPaymentMethodId,
  ) {
    return dio.get(
      "/pos/report/outlet/penerimaan/detail?pos_shifts_id=$posShiftsId&pos_payment_method_id=$posPaymentMethodId",
    );
  }

  Future<Response> getPenjualan(int posShiftsId) {
    return dio.get(
      "/pos/report/outlet/tipe-penjualan/summary?pos_shifts_id=$posShiftsId",
    );
  }

  Future<Response> getDetailPenjualan(int posShiftsId, int posOrderMethodId) {
    return dio.get(
      "/pos/report/outlet/tipe-penjualan/detail?pos_shifts_id=$posShiftsId&pos_order_method_id=$posOrderMethodId",
    );
  }

  Future<Response> getPelanggan(int posShiftsId) {
    return dio.get(
      "/pos/report/outlet/per-pelanggan/summary?pos_shifts_id=$posShiftsId",
    );
  }

  Future<Response> getDetailPelanggan(int posShiftsId, int customersId) {
    return dio.get(
      "/pos/report/outlet/per-pelanggan/detail?pos_shifts_id=$posShiftsId&customers_id=$customersId",
    );
  }

  Future<Response> getBarang(int posShiftsId) {
    return dio.get(
      "/pos/report/outlet/per-barang/summary?pos_shifts_id=$posShiftsId",
    );
  }

  Future<Response> getDetailBarang(int posShiftsId, int posMenusId) {
    return dio.get(
      "/pos/report/outlet/per-barang/detail?pos_shifts_id=$posShiftsId&pos_menus_id=$posMenusId",
    );
  }
}
