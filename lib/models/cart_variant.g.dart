// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cart_variant.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CartVariantAdapter extends TypeAdapter<CartVariant> {
  @override
  final int typeId = 1;

  @override
  CartVariant read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CartVariant(
      codeProduct: fields[0] as String,
      title: fields[1] as String,
      quantity: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CartVariant obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.codeProduct)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.quantity);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartVariantAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
