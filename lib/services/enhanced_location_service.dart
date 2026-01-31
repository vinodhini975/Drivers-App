import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import 'database_service.dart';
import 'duty_service.dart';
import 'auth_service.dart';

class EnhancedLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DatabaseService _dbService = DatabaseService.instance;
  final DutyService _dutyService = DutyService();
  final AuthService _authService = AuthService();

  Future<bool> captureLocation(String driverId) async {
    // 1. Guard: Ensure driver ID is valid
    if (driverId.isEmpty) {
      debugPrint('Sync skipped: Waiting for driver identity');
      return false;
    }

    try {
      final isDutyActive = await _dutyService.isDutyActive();
      if (!isDutyActive) return false;

      final batteryLevel = await _battery.batteryLevel;
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      final location = LocationModel(
        driverId: driverId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: position.speed,
        batteryLevel: batteryLevel,
        timestamp: DateTime.now(),
        isOnDuty: true,
        isSynced: false,
      );

      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        try {
          await _syncToFirebase(location).timeout(const Duration(seconds: 5));
          return true;
        } catch (e) {
          debugPrint('⚠️ Network lag, saving offline: $e');
          await _dbService.insertLocation(location);
          return true;
        }
      } else {
        await _dbService.insertLocation(location);
        return true;
      }
    } catch (e) {
      debugPrint('❌ Capture Error: $e');
      return false;
    }
  }

  Future<void> _syncToFirebase(LocationModel location) async {
    final docRef = _firestore.collection('drivers').doc(location.driverId);
    WriteBatch batch = _firestore.batch();
    
    batch.update(docRef, {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'lastUpdate': FieldValue.serverTimestamp(),
      'isActive': true,
    });

    final historyRef = docRef.collection('location_history').doc();
    batch.set(historyRef, {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'timestamp': Timestamp.fromDate(location.timestamp),
    });

    await batch.commit();
  }

  Future<int> syncOfflineLocations() async {
    final driverId = await _authService.getCurrentDriverId();
    if (driverId == null) {
      debugPrint('Sync skipped: No authenticated driver found');
      return 0;
    }

    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) return 0;

      final unsynced = await _dbService.getUnsyncedLocations();
      if (unsynced.isEmpty) return 0;

      int count = 0;
      for (var loc in unsynced) {
        try {
          await _syncToFirebase(loc).timeout(const Duration(seconds: 3));
          if (loc.id != null) {
             await _dbService.markAsSynced(loc.id!);
             count++;
          }
        } catch (e) {
          break; 
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> shouldContinueTracking() async {
    final driverId = await _authService.getCurrentDriverId();
    if (driverId == null) return false;
    
    final active = await _dutyService.isDutyActive();
    return active;
  }

  Stream<ConnectivityResult> get connectivityStream => _connectivity.onConnectivityChanged;
}
