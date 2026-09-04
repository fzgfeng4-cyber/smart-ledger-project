import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_schema.dart';

final class AppDatabase {
  AppDatabase({this.databasePath});

  static const fileName = 'smart-ledger.sqlite';

  final String? databasePath;
  Database? _database;

  Future<Database> open() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final resolvedPath = databasePath ?? await defaultDatabasePath();
    final db = await openAtPath(resolvedPath);
    _database = db;
    return db;
  }

  Future<void> close() async {
    final existing = _database;
    _database = null;
    await existing?.close();
  }

  static Future<String> defaultDatabasePath() async {
    return path.join(await getDatabasesPath(), fileName);
  }

  static Future<Database> openAtPath(
    String databasePath, {
    DatabaseFactory? databaseFactory,
  }) async {
    final factory = databaseFactory;
    if (factory != null) {
      return factory.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: DatabaseSchema.version,
          onConfigure: DatabaseSchema.configure,
          onCreate: DatabaseSchema.onCreate,
          onUpgrade: DatabaseSchema.onUpgrade,
          onDowngrade: DatabaseSchema.onDowngrade,
          onOpen: DatabaseSchema.onOpen,
        ),
      );
    }

    return openDatabase(
      databasePath,
      version: DatabaseSchema.version,
      onConfigure: DatabaseSchema.configure,
      onCreate: DatabaseSchema.onCreate,
      onUpgrade: DatabaseSchema.onUpgrade,
      onDowngrade: DatabaseSchema.onDowngrade,
      onOpen: DatabaseSchema.onOpen,
    );
  }
}
