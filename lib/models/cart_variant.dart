import 'package:hive/hive.dart';

part 'cart_variant.g.dart';

@HiveType(typeId: 1)
class CartVariant {
  @HiveField(0)
  final String codeProduct;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final int quantity;

  CartVariant({
    required this.codeProduct,
    required this.title,
    required this.quantity,
  });
}
