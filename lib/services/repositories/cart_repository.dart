import 'package:hive/hive.dart';
import '../../models/cart_item.dart';

class CartRepository {
  static final Box<CartItem> _box = Hive.box<CartItem>('cartBox');

  static List<CartItem> getAll() {
    return _box.values.toList();
  }

  static Future<void> add(CartItem item) async {
    await _box.put(item.cartItemId, item);
  }

  static Future<void> updateQuantity(String id, int qty) async {
    final item = _box.get(id);
    if (item != null) {
      item.quantity = qty;
      await item.save();
    }
  }

  static Future<void> remove(String id) async {
    await _box.delete(id);
  }

  static Future<void> clear() async {
    await _box.clear();
  }
}
