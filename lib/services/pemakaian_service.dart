import 'package:dio/dio.dart';

/// Service Pemakaian Barang (Goods Consumption).
///
/// Base path API: `/pos/goods-consumption`.
///
/// Semua endpoint sudah memakai API real:
///   getListPemakaian   → GET   /pos/goods-consumption
///   postPemakaian      → POST  /pos/goods-consumption
///   getDetailPemakaian → GET   /pos/goods-consumption/:id
///   getListItems       → GET   /pos/goods-consumption/items
///   getDetailItem      → GET   /pos/goods-consumption/items/:id
///   patchLines         → PATCH /pos/goods-consumption/:id/lines  (REPLACE semua baris)
///   submitPemakaian    → POST  /pos/goods-consumption/:id/submit
class PemakaianService {
  final Dio dio;

  PemakaianService(this.dio);

  static const String _base = '/pos/goods-consumption';

  /// Daftar dokumen pemakaian (paginated).
  /// [customerId] = filter outlet (0 / null → semua outlet milik user).
  Future<Response> getListPemakaian(
    int customerId, {
    int page = 1,
    int limit = 10,
    String? status,
    String? search,
  }) {
    final qp = <String, dynamic>{'page': page, 'limit': limit};
    if (customerId > 0) qp['customers_id'] = customerId;
    if (status != null && status.isNotEmpty) qp['status'] = status;
    if (search != null && search.isNotEmpty) qp['search'] = search;
    return dio.get(_base, queryParameters: qp);
  }

  /// Buat draft (header dokumen).
  /// Payload real: `{customers_id?, date: 'dd/MM/yyyy' (hari ini WITA), remarks?}`.
  Future<Response> postPemakaian(Map<String, dynamic> payload) {
    return dio.post(_base, data: payload);
  }

  /// Detail dokumen + baris.
  Future<Response> getDetailPemakaian(int id) {
    return dio.get('$_base/$id');
  }

  /// Autocomplete pencarian item yang eligible untuk pemakaian barang.
  Future<Response> getListItems({String? search, int limit = 20}) {
    final qp = <String, dynamic>{'limit': limit};
    if (search != null && search.isNotEmpty) qp['q'] = search;
    return dio.get('$_base/items', queryParameters: qp);
  }

  /// Detail item: `uom_options`, `stock` (NISIK), `avg_price` (per NISIK).
  /// [customersId] wajib bila user memegang >1 outlet.
  Future<Response> getDetailItem(int itemId, {int? customersId}) {
    final qp = <String, dynamic>{};
    if (customersId != null) qp['customers_id'] = customersId;
    return dio.get('$_base/items/$itemId', queryParameters: qp);
  }

  /// Simpan/ganti SELURUH baris draft (replace, bukan delta).
  /// [items] = `[{item_id, uom_id?, qty, remarks?}, ...]`.
  Future<Response> patchLines(int id, List<Map<String, dynamic>> items) {
    return dio.patch('$_base/$id/lines', data: {'items': items});
  }

  /// Ajukan dokumen untuk approval (tanpa body). Idempoten — aman di-retry.
  Future<Response> submitPemakaian(int id) {
    return dio.post('$_base/$id/submit');
  }

  // ─── Lampiran (milik dokumen, hanya bisa diubah saat status Draft) ──────────

  /// Upload lampiran baru (multipart: file, name?, mime_type?).
  Future<Response> postLampiran(int id, FormData payload) {
    return dio.post(
      '$_base/$id/lampirans',
      data: payload,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
  }

  /// Ganti isi lampiran (id lampiran & file_url tetap sama).
  Future<Response> putLampiran(int id, int lampiranId, FormData payload) {
    return dio.put(
      '$_base/$id/lampirans/$lampiranId',
      data: payload,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
  }

  /// Hapus lampiran.
  Future<Response> deleteLampiran(int id, int lampiranId) {
    return dio.delete('$_base/$id/lampirans/$lampiranId');
  }

  /// Ambil isi file lampiran (bytes). [fileUrl] = path relatif dari response
  /// (dio sudah menambahkan base URL + header Authorization otomatis).
  Future<Response> getLampiranFile(String fileUrl) {
    return dio.get(fileUrl, options: Options(responseType: ResponseType.bytes));
  }

  /// Petakan kode error server (`{message: "kode"}`) ke teks Indonesia.
  static String humanizeError(Object e) {
    final code = errorCode(e);

    const map = {
      'lokasi_belum_dipetakan_hubungi_admin':
          'Akun Anda belum terhubung ke outlet. Hubungi admin.',
      'outlet_bukan_milik_user': 'Outlet tidak tersedia untuk akun Anda.',
      'customers_id_wajib_diisi_user_memegang_lebih_dari_satu_outlet':
          'Pilih outlet terlebih dahulu.',
      'format_tanggal_harus_dd/mm/yyyy': 'Format tanggal tidak valid.',
      'tanggal_harus_sama_dengan_tanggal_input_hari_ini':
          'Pemakaian hanya bisa dicatat untuk tanggal hari ini.',
      'outlet_belum_terhubung_ke_company_hubungi_admin':
          'Data outlet belum lengkap. Hubungi admin.',
      'dokumen_tidak_ditemukan': 'Dokumen tidak ditemukan.',
      'dokumen_sudah_diajukan_tidak_bisa_diubah':
          'Dokumen sudah diajukan dan tidak bisa diubah.',
      'item_tidak_boleh_dobel_dalam_satu_dokumen':
          'Item ini sudah ada di daftar. Ubah jumlahnya pada baris tersebut.',
      'dokumen_tanpa_item_tidak_bisa_disubmit': 'Tambahkan minimal satu item.',
    };

    if (map.containsKey(code)) return map[code]!;
    if (code.startsWith('insufficient_stock')) {
      return 'Stok tidak cukup untuk sebagian item.';
    }
    if (code.startsWith('customers_id_wajib_diisi')) {
      return 'Pilih outlet terlebih dahulu.';
    }
    if (code.contains('tidak_dapat_dicatat_lewat_pemakaian_barang')) {
      return 'Item ini tidak bisa dicatat lewat Pemakaian Barang.';
    }
    return 'Terjadi kendala. Coba kembali.';
  }

  /// Ambil kode error mentah dari response (`message`) untuk penanganan khusus
  /// (mis. parsing daftar `insufficient_stock`).
  static String errorCode(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    }
    return '';
  }
}
