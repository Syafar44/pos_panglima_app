import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class CartStorageService {
  static const String cartKey = 'cart_items';

  static Future<List<Map<String, dynamic>>> getCart() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(cartKey);

    if (data == null) return [];

    final List decoded = jsonDecode(data);
    return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> saveCart(List<Map<String, dynamic>> cart) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cartKey, jsonEncode(cart));
  }

  static Future<void> addToCart(Map<String, dynamic> newItem) async {
    final cart = await getCart();

    final bool isPackage = newItem['props'] != null;

    if (!isPackage) {
      final index = cart.indexWhere(
        (item) =>
            item['code_produk'] == newItem['code_produk'] &&
            item['props'] == null,
      );

      if (index != -1) {
        cart[index]['quantity'] += newItem['quantity'];
      } else {
        newItem['cartItemId'] = const Uuid().v4();
        cart.add(newItem);
      }

      await saveCart(cart);
      return;
    }

    final List newProps = newItem['props'];

    final index = cart.indexWhere((item) {
      if (item['code_produk'] != newItem['code_produk']) return false;
      if (item['props'] == null) return false;

      final List oldProps = item['props'];

      if (oldProps.length != newProps.length) return false;

      for (int i = 0; i < oldProps.length; i++) {
        if (oldProps[i]['code_produk'] != newProps[i]['code_produk']) {
          return false;
        }
        if (oldProps[i]['quantity'] != newProps[i]['quantity']) return false;
      }

      return true;
    });

    if (index != -1) {
      cart[index]['quantity'] += newItem['quantity'];
    } else {
      newItem['cartItemId'] = const Uuid().v4();
      cart.add(newItem);
    }

    await saveCart(cart);
  }

  static Future<void> updateItem(
    String cartItemId,
    Map<String, dynamic> updatedData,
  ) async {
    final cart = await getCart();

    final index = cart.indexWhere((item) => item['cartItemId'] == cartItemId);

    if (index != -1) {
      updatedData.forEach((key, value) {
        cart[index][key] = value;
      });

      await saveCart(cart);
    }
  }

  static Future<void> removeItem(String cartItemId) async {
    final cart = await getCart();
    cart.removeWhere((item) => item['cartItemId'] == cartItemId);
    await saveCart(cart);
  }

  static Future<void> clearCart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cartKey);
  }

  static Future<void> increaseQuantity(String cartItemId) async {
    final cart = await getCart();

    final index = cart.indexWhere((item) => item['cartItemId'] == cartItemId);
    if (index != -1) {
      cart[index]['quantity'] += 1;
      await saveCart(cart);
    }
  }

  static Future<void> decreaseQuantity(String cartItemId) async {
    final cart = await getCart();

    final index = cart.indexWhere((item) => item['cartItemId'] == cartItemId);
    if (index != -1) {
      cart[index]['quantity'] -= 1;

      // Jika quantity jadi 0 → hapus item
      if (cart[index]['quantity'] <= 0) {
        cart.removeAt(index);
      }

      await saveCart(cart);
    }
  }
}
