import 'package:hive_flutter/hive_flutter.dart';
import 'package:tracex/data/models/crash_hive_model.dart';

abstract class BaseCrashOfflineDatasource {
  Future<void> saveCrash(CrashHiveModel crash);
  List<CrashHiveModel> getCachedCrashes();
  Future<void> deleteCrash(dynamic key);
  Future<void> clear();
}

class CrashOfflineDatasource extends BaseCrashOfflineDatasource {
  static const String boxName = 'tracex_crashes';
  late Box<CrashHiveModel> _box;

  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(CrashHiveModelAdapter());
    }
    _box = await Hive.openBox<CrashHiveModel>(boxName);
  }

  @override
  Future<void> saveCrash(CrashHiveModel crash) async {
    await _box.add(crash);
  }

  @override
  List<CrashHiveModel> getCachedCrashes() {
    return _box.values.toList();
  }

  @override
  Future<void> deleteCrash(dynamic key) async {
    await _box.delete(key);
  }

  @override
  Future<void> clear() async {
    await _box.clear();
  }
}
