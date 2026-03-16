import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import '../models/route_point_model.dart';

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
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  /// Creates all tables from scratch (fresh install).
  Future _createDB(Database db, int version) async {
    // ── Existing table: offline location points for live tracking ──────
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

    // ── NEW table: offline route points for trip intelligence ──────────
    await _createRoutePointsTable(db);
  }

  /// Handles schema migration from version 1 to version 2.
  /// Adds the offline_route_points table without touching existing data.
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      debugPrint('📦 Upgrading database from v$oldVersion to v$newVersion: adding offline_route_points table');
      await _createRoutePointsTable(db);
    }
  }

  /// Creates the offline_route_points table and its indices.
  Future<void> _createRoutePointsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_route_points (
        id TEXT PRIMARY KEY,
        tripId TEXT NOT NULL,
        driverId TEXT NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        type TEXT NOT NULL,
        speed REAL NOT NULL,
        accuracy REAL NOT NULL,
        stopDurationSec INTEGER NOT NULL DEFAULT 0,
        isInsideWard INTEGER NOT NULL DEFAULT 1,
        isInsideRouteBuffer INTEGER NOT NULL DEFAULT 1,
        routeDeviationMeters REAL NOT NULL DEFAULT 0.0,
        isSynced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_route_points_synced 
      ON offline_route_points(isSynced)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_route_points_trip 
      ON offline_route_points(tripId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_route_points_timestamp 
      ON offline_route_points(timestamp)
    ''');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXISTING: Offline Location Methods (PRESERVED — no changes)
  // ═══════════════════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW: Offline Route Point Methods (for Trip Intelligence)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Insert a classified route point into the local offline table.
  Future<int> insertOfflineRoutePoint(RoutePointModel point) async {
    final db = await database;
    return await db.insert(
      'offline_route_points',
      point.toLocalStorage(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all unsynced route points, ordered by timestamp ascending.
  Future<List<RoutePointModel>> getUnsyncedRoutePoints() async {
    final db = await database;
    final maps = await db.query(
      'offline_route_points',
      where: 'isSynced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => RoutePointModel.fromLocalStorage(map)).toList();
  }

  /// Mark a single route point as synced after successful Firestore write.
  Future<void> markRoutePointSynced(String id) async {
    final db = await database;
    await db.update(
      'offline_route_points',
      {'isSynced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark multiple route points as synced.
  Future<void> markMultipleRoutePointsSynced(List<String> ids) async {
    final db = await database;
    final batch = db.batch();

    for (final id in ids) {
      batch.update(
        'offline_route_points',
        {'isSynced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get count of unsynced route points.
  Future<int> getUnsyncedRoutePointCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM offline_route_points WHERE isSynced = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get all route points for a specific trip (useful for local replay).
  Future<List<RoutePointModel>> getTripRoutePoints(String tripId) async {
    final db = await database;
    final maps = await db.query(
      'offline_route_points',
      where: 'tripId = ?',
      whereArgs: [tripId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => RoutePointModel.fromLocalStorage(map)).toList();
  }

  /// Delete synced route points older than specified days.
  Future<int> deleteSyncedRoutePoints({int olderThanDays = 7}) async {
    final db = await database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;

    return await db.delete(
      'offline_route_points',
      where: 'isSynced = ? AND timestamp < ?',
      whereArgs: [1, cutoffTime],
    );
  }

  /// Clear all route points (for development/testing only).
  Future<void> clearAllRoutePoints() async {
    final db = await database;
    await db.delete('offline_route_points');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GENERAL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Close database
  Future close() async {
    final db = await database;
    db.close();
  }
}
