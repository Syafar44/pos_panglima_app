import 'dart:io';

import 'package:dio/dio.dart';

/// Service Stock Opname Bulanan (Monthly Stock Opname).
///
/// Base path API: `/pos/monthly-stock-opname`.
///
/// JANGAN tertukar dengan `/pos/daily-stock-opname` — itu modul berbeda
/// (opname harian outlet), tabelnya berbeda, dan aturannya sengaja berlawanan.
///
/// Alur: Generate SO (web) → Hitung & isi (aplikasi) → Submit (aplikasi) →
/// Approval (web/Telegram) → Inventory Adjustment (ERP).
///
/// Catatan penting yang memengaruhi kode di sini:
/// - Petugas TIDAK boleh melihat stok sistem. Endpoint mode hitung memang tidak
///   mengirim `system_qty` maupun `difference_qty`. Jangan pernah menghitung
///   atau menampilkan selisih di aplikasi.
/// - Cakupan gudang diturunkan server dari token — aplikasi tidak pernah
///   mengirim `warehouse_id`.
/// - Angka yang diketik petugas dikirim APA ADANYA. Tidak ada konversi satuan
///   di mana pun.
class MonthlyStockOpnameService {
  final Dio dio;

  MonthlyStockOpnameService(this.dio);

  static const String _base = '/pos/monthly-stock-opname';

  /// Batas baris per request PATCH — lebih dari ini ditolak server.
  static const int maxLinesPerBatch = 500;

  /// Status dokumen. Case-sensitive di server: `draft` huruf kecil
  /// mengembalikan daftar kosong, bukan error.
  static const List<String> statuses = [
    'Draft',
    'Submitted',
    'Approved',
    'Rejected',
  ];

  /// 1. Daftar dokumen + progres (`counted_lines` / `total_lines`).
  Future<Response> getList({
    String status = 'Draft',
    int page = 1,
    int limit = 10,
    String? search,
  }) {
    final qp = <String, dynamic>{'page': page, 'limit': limit};
    if (status.isNotEmpty) qp['status'] = status;
    if (search != null && search.isNotEmpty) qp['search'] = search;
    return dio.get(_base, queryParameters: qp);
  }

  /// 2. Unduh baris untuk mode hitung.
  ///
  /// Dipanggil SEKALI saat dokumen dibuka, lalu seluruh barisnya disimpan lokal
  /// supaya aplikasi bisa offline penuh.
  Future<Response> getLines(int id) {
    return dio.get('$_base/$id/lines');
  }

  /// 3. Sinkronkan isian (batch). Maksimal [maxLinesPerBatch] baris per request.
  ///
  /// `lines`: `[{line_id, actual_qty, remarks}]`. Aman dikirim ulang —
  /// mengirim batch yang sama dua kali menghasilkan keadaan akhir yang sama.
  Future<Response> syncLines(int id, List<Map<String, dynamic>> lines) {
    return dio.patch('$_base/$id/lines', data: {'lines': lines});
  }

  /// 4. Submit (ajukan approval).
  ///
  /// [idempotencyKey] wajib: satu UUID per dokumen, dibuat saat petugas menekan
  /// Submit, disimpan lokal, dan dipakai ulang untuk SETIAP percobaan ulang
  /// dokumen itu. Membuat UUID baru saat retry justru membatalkan pengamannya.
  Future<Response> submit(int id, String idempotencyKey) {
    return dio.post(
      '$_base/$id/submit',
      data: {'idempotency_key': idempotencyKey},
    );
  }

  /// 5. Riwayat dokumen (read-only) untuk Submitted/Approved/Rejected.
  /// Tidak memuat baris item.
  Future<Response> getDetail(int id) {
    return dio.get('$_base/$id');
  }

  // ─── Helper error ───────────────────────────────────────────────────────────

  /// `true` bila kegagalan berasal dari jaringan (timeout / host tak
  /// terjangkau), bukan dari aturan bisnis.
  ///
  /// Dokumen API menegaskan keduanya harus dibedakan: menggabungkan jadi
  /// "gagal menyimpan" membuat petugas panik dan menghitung ulang dari awal.
  static bool isNetworkFailure(Object e) {
    if (e is SocketException) return true;
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        case DioExceptionType.unknown:
          return e.error is SocketException;
        default:
          return false;
      }
    }
    return false;
  }

  /// Pesan `message` dari server. Untuk 422/409/403 pesan ini sudah ditulis
  /// untuk pengguna akhir — tampilkan apa adanya.
  static String serverMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    }
    return '';
  }

  static int? statusCode(Object e) {
    if (e is DioException) return e.response?.statusCode;
    return null;
  }

  /// Pesan siap tampil: aturan → pesan server apa adanya, jaringan → pesan
  /// menenangkan bahwa isian aman di HP.
  static String humanizeError(Object e) {
    if (isNetworkFailure(e)) {
      return 'Server sedang tidak bisa dihubungi. Isian Anda tersimpan di HP '
          'dan akan dikirim otomatis saat koneksi kembali.';
    }
    final message = serverMessage(e);
    if (message.isNotEmpty) return message;
    final code = statusCode(e);
    switch (code) {
      case 403:
        return 'Dokumen ini bukan milik gudang akun Anda.';
      case 404:
        return 'Dokumen tidak ditemukan atau sudah dihapus di web.';
      case 409:
        return 'Dokumen sudah bukan Draft dan tidak bisa diubah lagi.';
      default:
        return 'Terjadi kendala. Coba kembali.';
    }
  }

  /// Label status ramah untuk chip.
  static String statusLabel(String status) {
    switch (status) {
      case 'Draft':
        return 'Draft';
      case 'Submitted':
        return 'Menunggu approval';
      case 'Approved':
        return 'Disetujui';
      case 'Rejected':
        return 'Ditolak';
      default:
        return status;
    }
  }
}
