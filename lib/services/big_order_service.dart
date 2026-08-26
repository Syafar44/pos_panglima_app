import 'package:dio/dio.dart';

/// Service Big Order.
///
/// Base path API: `/pos/big-order`.
///
/// Big Order = pesanan besar (pesan hari ini, ambil beberapa hari kemudian):
/// Pesan + DP (min %) → cicilan → lunas → serah terima hari H.
/// Semua nilai uang (total, sisa_tagihan) dihitung SERVER — jangan hitung ulang.
class BigOrderService {
  final Dio dio;

  BigOrderService(this.dio);

  static const String _base = '/pos/big-order';

  // ─── Pemesan ────────────────────────────────────────────────────────────────

  /// Cari pemesan (nama, kontak, kode).
  Future<Response> searchCustomers({String? search, int limit = 20}) {
    final qp = <String, dynamic>{'limit': limit};
    if (search != null && search.isNotEmpty) qp['search'] = search;
    return dio.get('$_base/customers', queryParameters: qp);
  }

  /// Buat pemesan baru. `{name, contact, email?, dob?}` (name & contact wajib).
  Future<Response> createCustomer(Map<String, dynamic> payload) {
    return dio.post('$_base/customers', data: payload);
  }

  // ─── Big Order ──────────────────────────────────────────────────────────────

  /// Buat Big Order + pembayaran pertama (DP). Total dihitung server dari `lines`.
  Future<Response> createBigOrder(Map<String, dynamic> payload) {
    return dio.post(_base, data: payload);
  }

  /// Daftar Big Order (paginated).
  Future<Response> getList({
    int page = 1,
    int limit = 10,
    String? status,
    String? search,
    int? outletHubId,
    String? pickupFrom,
    String? pickupTo,
  }) {
    final qp = <String, dynamic>{'page': page, 'limit': limit};
    if (status != null && status.isNotEmpty) qp['status'] = status;
    if (search != null && search.isNotEmpty) qp['search'] = search;
    if (outletHubId != null) qp['outlet_hub_id'] = outletHubId;
    if (pickupFrom != null && pickupFrom.isNotEmpty) qp['pickup_from'] = pickupFrom;
    if (pickupTo != null && pickupTo.isNotEmpty) qp['pickup_to'] = pickupTo;
    return dio.get(_base, queryParameters: qp);
  }

  /// Detail Big Order + riwayat pembayaran.
  Future<Response> getDetail(int id) {
    return dio.get('$_base/$id');
  }

  /// Tambah pembayaran. `{pos_payment_method_id, amount, pos_shifts_id, is_cash}`.
  Future<Response> addPayment(int id, Map<String, dynamic> payload) {
    return dio.post('$_base/$id/payments', data: payload);
  }

  /// Serah terima (memotong stok, menutup pesanan). Syarat status `big_paid`.
  Future<Response> handover(int id, Map<String, dynamic> payload) {
    return dio.post('$_base/$id/handover', data: payload);
  }

  /// Batalkan. `{alasan}` wajib. Uang yang sudah dibayar hangus.
  Future<Response> cancel(int id, String alasan) {
    return dio.post('$_base/$id/cancel', data: {'alasan': alasan});
  }

  // ─── Helper error & label ───────────────────────────────────────────────────

  /// Kode error mentah dari response (`message`).
  static String errorCode(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    }
    return '';
  }

  /// Petakan kode error server ke teks Indonesia.
  static String humanizeError(Object e) {
    final code = errorCode(e);
    const map = {
      'pickup_at_minimal_h1':
          'Waktu pengambilan minimal besok (H+1).',
      'invalid_pos_payment_method_id': 'Metode pembayaran tidak valid.',
      'belum_lunas': 'Pesanan belum lunas, belum bisa diserahkan.',
      'bukan_big_order': 'Data ini bukan Big Order.',
      'no rows affected': 'Data tidak ditemukan.',
    };
    if (map.containsKey(code)) return map[code]!;
    if (code.startsWith('dp_kurang_dari_minimum')) {
      return 'DP kurang dari minimum: ${_afterColon(code)}';
    }
    if (code.startsWith('pembayaran_melebihi_total')) {
      return 'Pembayaran melebihi total pesanan.';
    }
    if (code.startsWith('pembayaran_melebihi_sisa_tagihan')) {
      return 'Nominal melebihi sisa tagihan.';
    }
    if (code.startsWith('status_tidak_menerima_pembayaran')) {
      return 'Pesanan sudah lunas — tidak menerima pembayaran lagi.';
    }
    if (code.startsWith('status_tidak_bisa_diserahterimakan')) {
      return 'Pesanan tidak bisa diserahterimakan (sudah diserahkan/dibatalkan).';
    }
    if (code.startsWith('insufficient_stock')) {
      return 'Stok tidak cukup untuk sebagian item.';
    }
    if (code.isEmpty) return 'Terjadi kendala. Coba kembali.';
    return code;
  }

  static String _afterColon(String code) {
    final idx = code.indexOf(':');
    return idx >= 0 ? code.substring(idx + 1).trim() : '';
  }

  /// Label status ramah untuk chip.
  static String statusLabel(String status) {
    switch (status) {
      case 'big_pending':
        return 'Belum lunas';
      case 'big_paid':
        return 'Lunas';
      case 'active':
        return 'Selesai';
      case 'big_cancelled':
        return 'Dibatalkan';
      default:
        return status;
    }
  }
}
