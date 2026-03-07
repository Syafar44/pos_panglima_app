// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cart_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CartItemAdapter extends TypeAdapter<CartItem> {
  @override
  final int typeId = 0;

  @override
  CartItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CartItem(
      cartItemId: fields[0] as String,
      codeProduct: fields[1] as String,
      title: fields[2] as String,
      price: fields[3] as int,
      quantity: fields[4] as int,
      variants: (fields[5] as List).cast<CartVariant>(),
      discount: fields[6] as int,
      isPercent: fields[7] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, CartItem obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.cartItemId)
      ..writeByte(1)
      ..write(obj.codeProduct)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.price)
      ..writeByte(4)
      ..write(obj.quantity)
      ..writeByte(5)
      ..write(obj.variants)
      ..writeByte(6)
      ..write(obj.discount)
      ..writeByte(7)
      ..write(obj.isPercent);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
