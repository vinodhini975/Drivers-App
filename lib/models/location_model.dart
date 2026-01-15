import 'package:cloud_firestore/cloud_firestore.dart';

class LocationModel {
  final int? id; // SQLite primary key
  final String driverId;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final int batteryLevel;
  final DateTime timestamp;
  final bool isOnDuty;
  final bool isSynced;

  LocationModel({
    this.id,
    required this.driverId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.batteryLevel,
    required this.timestamp,
    this.isOnDuty = true,
    this.isSynced = false,
  });

  factory LocationModel.fromMap(Map<String, dynamic> map) {
    return LocationModel(
      driverId: map['driverId'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      accuracy: (map['accuracy'] ?? 0.0).toDouble(),
      speed: (map['speed'] ?? 0.0).toDouble(),
      batteryLevel: map['batteryLevel'] ?? 0,
      timestamp: map['timestamp'] is Timestamp
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      isOnDuty: map['isOnDuty'] ?? true,
      isSynced: map['isSynced'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'batteryLevel': batteryLevel,
      'timestamp': Timestamp.fromDate(timestamp),
      'isOnDuty': isOnDuty,
      'isSynced': isSynced,
    };
  }

  Map<String, dynamic> toLocalStorage() {
    return {
      if (id != null) 'id': id,
      'driverId': driverId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'batteryLevel': batteryLevel,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isOnDuty': isOnDuty ? 1 : 0,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory LocationModel.fromLocalStorage(Map<String, dynamic> map) {
    return LocationModel(
      id: map['id'],
      driverId: map['driverId'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      accuracy: (map['accuracy'] ?? 0.0).toDouble(),
      speed: (map['speed'] ?? 0.0).toDouble(),
      batteryLevel: map['batteryLevel'] ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      isOnDuty: (map['isOnDuty'] ?? 1) == 1,
      isSynced: (map['isSynced'] ?? 0) == 1,
    );
  }
}
