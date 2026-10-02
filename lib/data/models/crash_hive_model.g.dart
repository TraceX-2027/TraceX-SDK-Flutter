// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crash_hive_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CrashHiveModelAdapter extends TypeAdapter<CrashHiveModel> {
  @override
  final int typeId = 0;

  @override
  CrashHiveModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CrashHiveModel(
      id: fields[9] as dynamic,
      projectKey: fields[0] as String,
      platform: fields[1] as String,
      language: fields[2] as String,
      occurredAt: fields[3] as DateTime,
      exceptionType: fields[4] as String,
      errorMessage: fields[5] as String,
      stackTrace: fields[6] as String,
      environment: (fields[7] as Map).cast<String, dynamic>(),
      breadcrumbs: (fields[8] as List)
          .map((dynamic e) => (e as Map).cast<String, dynamic>())
          .toList(),
    );
  }

  @override
  void write(BinaryWriter writer, CrashHiveModel obj) {
    writer
      ..writeByte(10)
      ..writeByte(9)
      ..write(obj.id)
      ..writeByte(0)
      ..write(obj.projectKey)
      ..writeByte(1)
      ..write(obj.platform)
      ..writeByte(2)
      ..write(obj.language)
      ..writeByte(3)
      ..write(obj.occurredAt)
      ..writeByte(4)
      ..write(obj.exceptionType)
      ..writeByte(5)
      ..write(obj.errorMessage)
      ..writeByte(6)
      ..write(obj.stackTrace)
      ..writeByte(7)
      ..write(obj.environment)
      ..writeByte(8)
      ..write(obj.breadcrumbs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CrashHiveModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
