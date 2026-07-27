// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receivable_hive_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReceivableHiveAdapter extends TypeAdapter<ReceivableHive> {
  @override
  final int typeId = 1;

  @override
  ReceivableHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReceivableHive(
      id: fields[0] as String,
      userId: fields[1] as String,
      fromPerson: fields[2] as String,
      amount: fields[3] as double,
      description: fields[4] as String?,
      dueDate: fields[5] as DateTime,
      isPaid: fields[6] as bool,
      sourceExpenseId: fields[9] as String?,
      remainingAmount: fields[10] as double?,
      settlementsJson: fields[11] as String?,
      createdAt: fields[7] as DateTime,
      updatedAt: fields[8] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ReceivableHive obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.fromPerson)
      ..writeByte(3)
      ..write(obj.amount)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.dueDate)
      ..writeByte(6)
      ..write(obj.isPaid)
      ..writeByte(9)
      ..write(obj.sourceExpenseId)
      ..writeByte(10)
      ..write(obj.remainingAmount)
      ..writeByte(11)
      ..write(obj.settlementsJson)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceivableHiveAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
