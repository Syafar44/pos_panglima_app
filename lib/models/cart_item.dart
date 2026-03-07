import 'package:hive/hive.dart';
import 'cart_variant.dart';

part 'cart_item.g.dart';

@HiveType(typeId: 0)
class CartItem extends HiveObject {
  @HiveField(0)
  final String cartItemId;

  @HiveField(1)
  final String codeProduct;

  @HiveField(2)
  final String title;

  @HiveField(3)
  final int price;

  @HiveField(4)
  int quantity;

  @HiveField(5)
  final List<CartVariant> variants;

  @HiveField(6)
  final int discount;

  @HiveField(7)
  final bool isPercent;

  CartItem({
    required this.cartItemId,
    required this.codeProduct,
    required this.title,
    required this.price,
    required this.quantity,
    required this.variants,
    required this.discount,
    required this.isPercent,
  });
}
