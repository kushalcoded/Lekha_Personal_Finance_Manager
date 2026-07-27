// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_hive_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseHiveAdapter extends TypeAdapter<ExpenseHive> {
  @override
  final int typeId = 0;

  @override
  ExpenseHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExpenseHive(
      id: fields[0] as String,
      userId: fields[1] as String,
      amount: fields[2] as double,
      category: fields[3] as String,
      description: fields[4] as String?,
      date: fields[5] as DateTime,
      paymentMethod: fields[10] as String?,
      recurringTemplateId: fields[8] as String?,
      recurringDueDate: fields[9] as DateTime?,
      createdAt: fields[6] as DateTime,
      updatedAt: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ExpenseHive obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.category)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.date)
      ..writeByte(10)
      ..write(obj.paymentMethod)
      ..writeByte(8)
      ..write(obj.recurringTemplateId)
      ..writeByte(9)
      ..write(obj.recurringDueDate)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseHiveAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
