import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_panglima_app/utils/bom_calculator.dart';

class OfflineStockService {
  static const _snapshotKey = 'offline_snapshot';
  static const _menuKey = 'offline_menu';
  static const _syncedAtKey = 'offline_synced_at';
  static const _cartSnapshotKey = 'offline_cart_snapshot';

  // ── Snapshot ──────────────────────────────────────────────────────────────

  static Future<void> saveSnapshot(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(data));
    await prefs.setString(
        _syncedAtKey, data['synced_at']?.toString() ?? '');
  }

  static Future<Map<String, dynamic>?> getSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<String?> getSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_syncedAtKey);
  }

  // ── Menu ──────────────────────────────────────────────────────────────────

  static Future<void> saveMenu(List menu) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_menuKey, jsonEncode(menu));
  }

  static Future<List<dynamic>> getMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_menuKey);
    if (raw == null) return [];
    return jsonDecode(raw) as List;
  }

  // ── Cart snapshot (untuk payment_page saat offline) ───────────────────────

  static Future<void> saveCartSnapshot(
      List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cartSnapshotKey, jsonEncode(items));
  }

  static Future<List<Map<String, dynamic>>> getCartSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cartSnapshotKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> clearCartSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cartSnapshotKey);
  }

  // ── Mutasi cart offline (struktur sama dengan server-cart) ────────────────

  /// Hitung ulang subtotal & total sebuah baris cart berdasarkan qty + diskon.
  static void _recalc(Map<String, dynamic> item) {
    final price = (item['price'] as num? ?? 0).toInt();
    final qty = (item['quantity'] as num? ?? 0).toInt();
    final tax = (item['tax'] as num? ?? 0).toInt();
    final isPercent = (item['is_percentage'] as num? ?? 0).toInt() == 1;
    final discount = (item['discount'] as num? ?? 0).toInt();
    final discountVal = (item['discount_val'] as num? ?? 0).toInt();
    final subtotal = price * qty;
    final totalDiscount =
        isPercent ? subtotal * discountVal ~/ 100 : discount;
    item['subtotal'] = subtotal;
    item['total'] = subtotal - totalDiscount + tax;
  }

  /// Tambah item ke cart offline. Item tanpa varian & tanpa diskon digabung
  /// (qty ditambah) dengan baris sejenis; selain itu jadi baris baru.
  static Future<void> addCartItem(Map<String, dynamic> item) async {
    final cart = await getCartSnapshot();
    final props = (item['pos_cart_props'] as List? ?? []);
    final noDiscount = ((item['discount'] as num? ?? 0) == 0) &&
        ((item['discount_val'] as num? ?? 0) == 0);

    if (props.isEmpty && noDiscount) {
      final idx = cart.indexWhere((c) =>
          c['pos_menus_id'] == item['pos_menus_id'] &&
          ((c['pos_cart_props'] as List?) ?? const []).isEmpty &&
          ((c['discount'] as num? ?? 0) == 0) &&
          ((c['discount_val'] as num? ?? 0) == 0));
      if (idx != -1) {
        cart[idx]['quantity'] = (cart[idx]['quantity'] as num).toInt() +
            (item['quantity'] as num).toInt();
        _recalc(cart[idx]);
        await saveCartSnapshot(cart);
        return;
      }
    }

    _recalc(item);
    cart.add(item);
    await saveCartSnapshot(cart);
  }

  static Future<void> increaseCartItem(int id) async {
    final cart = await getCartSnapshot();
    final idx = cart.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    cart[idx]['quantity'] = (cart[idx]['quantity'] as num).toInt() + 1;
    _recalc(cart[idx]);
    await saveCartSnapshot(cart);
  }

  static Future<void> decreaseCartItem(int id) async {
    final cart = await getCartSnapshot();
    final idx = cart.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    final q = (cart[idx]['quantity'] as num).toInt() - 1;
    if (q <= 0) {
      cart.removeAt(idx);
    } else {
      cart[idx]['quantity'] = q;
      _recalc(cart[idx]);
    }
    await saveCartSnapshot(cart);
  }

  static Future<void> removeCartItem(int id) async {
    final cart = await getCartSnapshot();
    cart.removeWhere((c) => c['id'] == id);
    await saveCartSnapshot(cart);
  }

  /// Ganti isi sebuah baris cart (hasil edit dari modal update). `id` baris
  /// dipertahankan; subtotal & total dihitung ulang.
  static Future<void> updateCartItem(
      int id, Map<String, dynamic> updated) async {
    final cart = await getCartSnapshot();
    final idx = cart.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    updated['id'] = id;
    // Pertahankan asal-usul item: kalau baris ini draft offline, edit-nya tetap
    // ikut dimigrasi; kalau berasal dari server, jangan ditandai offline supaya
    // tidak terkirim ganda saat online.
    if (cart[idx]['_offline'] == true) updated['_offline'] = true;
    _recalc(updated);
    cart[idx] = updated;
    await saveCartSnapshot(cart);
  }

  // ── Validasi stok lokal ───────────────────────────────────────────────────

  /// Mengembalikan daftar bahan yang stoknya kurang dalam format yang sama
  /// dengan [parseInsufficientStock]/`ModalInsufficientStock`: {name, required,
  /// stock}. List kosong = stok cukup (atau belum pernah sync → best-effort,
  /// tidak memblokir).
  static Future<List<Map<String, String>>> validateDetailed(
      List<Map<String, dynamic>> cart) async {
    final snap = await getSnapshot();
    if (snap == null) {
      debugPrint('[StockValidate] snapshot NULL — belum pernah sync stok → '
          'validasi DILEWATI (semua lolos).');
      return [];
    }
    final bomList = snap['bom'] as List? ?? [];
    final stocks = (snap['stocks'] as List? ?? []);
    final bomIndex = BomCalculator.indexBom(bomList);
    final need = BomCalculator.totalNeed(cart, bomIndex);

    final cartMenus = cart.map((c) => c['pos_menus_id']).toList();
    debugPrint('[StockValidate] bom_rows=${bomList.length}, '
        'stocks=${stocks.length}, cart_menus=$cartMenus, need=$need');

    if (need.isEmpty) {
      debugPrint('[StockValidate] need KOSONG — menu di cart tidak punya BOM '
          '(bom kosong / menu tak ada di bom) → tidak bisa cek stok, lolos.');
      return [];
    }
    final lacking = <Map<String, String>>[];
    for (final entry in need.entries) {
      final stock = stocks.cast<Map>().firstWhere(
            (s) => (s['items_id'] as num).toInt() == entry.key,
            orElse: () => <String, dynamic>{},
          );
      if (stock.isEmpty) {
        debugPrint('[StockValidate] items_id=${entry.key} TIDAK ADA di stocks '
            '→ dilewati.');
        continue;
      }
      if (stock['skip_validation'] == true) continue;
      // Material satuan "Gr" tidak wajib presisi → lewati pengecekan stok.
      if (stock['uom']?.toString().toLowerCase() == 'gr') {
        debugPrint('[StockValidate] items_id=${entry.key} uom=Gr '
            '→ dilewati (tidak wajib presisi).');
        continue;
      }
      final qty = (stock['qty'] as num? ?? 0).toInt();
      if (entry.value > qty) {
        lacking.add({
          'name': stock['name']?.toString() ?? 'Item',
          'required': entry.value.toString(),
          'stock': qty.toString(),
        });
      }
    }
    debugPrint('[StockValidate] hasil kurang: $lacking');
    return lacking;
  }

  // ── Decrement stok lokal ──────────────────────────────────────────────────

  static Future<void> applyDecrement(
      List<Map<String, dynamic>> cart) async {
    final snap = await getSnapshot();
    if (snap == null) return;
    final bomIndex =
        BomCalculator.indexBom(snap['bom'] as List? ?? []);
    final need = BomCalculator.totalNeed(cart, bomIndex);
    if (need.isEmpty) return;
    final stocks = (snap['stocks'] as List).cast<Map<String, dynamic>>();
    for (final s in stocks) {
      final id = (s['items_id'] as num).toInt();
      if (need.containsKey(id)) {
        s['qty'] = (s['qty'] as num).toInt() - need[id]!;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(snap));
  }
}
