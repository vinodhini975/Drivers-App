import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/location_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('driver_locations.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE offline_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        driverId TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL NOT NULL,
        speed REAL NOT NULL,
        batteryLevel INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        isOnDuty INTEGER NOT NULL,
        isSynced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_synced ON offline_locations(isSynced)
    ''');

    await db.execute('''
      CREATE INDEX idx_timestamp ON offline_locations(timestamp)
    ''');
  }

  /// Insert location into local database
  Future<int> insertLocation(LocationModel location) async {
    final db = await database;
    return await db.insert('offline_locations', location.toLocalStorage());
  }

  /// Get all unsynced locations
  Future<List<LocationModel>> getUnsyncedLocations() async {
    final db = await database;
    final maps = await db.query(
      'offline_locations',
      where: 'isSynced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => LocationModel.fromLocalStorage(map)).toList();
  }

  /// Mark location as synced
  Future<void> markAsSynced(int id) async {
    final db = await database;
    await db.update(
      'offline_locations',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark multiple locations as synced
  Future<void> markMultipleAsSynced(List<int> ids) async {
    final db = await database;
    final batch = db.batch();
    
    for (final id in ids) {
      batch.update(
        'offline_locations',
        {'isSynced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    
    await batch.commit(noResult: true);
  }

  /// Delete synced locations older than specified days
  Future<int> deleteSyncedLocations({int olderThanDays = 7}) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;

    return await db.delete(
      'offline_locations',
      where: 'isSynced = ? AND timestamp < ?',
      whereArgs: [1, cutoffTime],
    );
  }

  /// Get total count of unsynced locations
  Future<int> getUnsyncedCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_locations WHERE isSynced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get all locations for a specific driver
  Future<List<LocationModel>> getDriverLocations(String driverId, {int limit = 100}) async {
    final db = await database;
    final maps = await db.query(
      'offline_locations',
      where: 'driverId = ?',
      whereArgs: [driverId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return maps.map((map) => LocationModel.fromLocalStorage(map)).toList();
  }

  /// Clear all locations
  Future<void> clearAllLocations() async {
    final db = await database;
    await db.delete('offline_locations');
  }

  /// Close database
  Future close() async {
    final db = await database;
    db.close();
  }
}
