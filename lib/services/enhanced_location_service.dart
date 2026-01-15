import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/location_model.dart';
import 'database_service.dart';
import 'duty_service.dart';

class EnhancedLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DatabaseService _dbService = DatabaseService.instance;
  final DutyService _dutyService = DutyService();

  Future<bool> captureLocation(String driverId) async {
    try {
      // CRITICAL: Verify Firebase user is authenticated before any operations
      if (!await _isDriverAuthenticated(driverId)) {
        debugPrint('⚠️ Driver authentication failed. Location capture blocked.');
        // Store locally but don't attempt Firestore write
        return await _captureAndStoreOffline(driverId);
      }

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
          debugPrint('⚠️ Sync timeout or error, saving offline: $e');
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

  Future<bool> _captureAndStoreOffline(String driverId) async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      final location = LocationModel(
        driverId: driverId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        speed: pos.speed,
        batteryLevel: await _battery.batteryLevel,
        timestamp: DateTime.now(),
        isSynced: false,
      );
      await _dbService.insertLocation(location);
      return true;
    } catch (e) {
      debugPrint('❌ Offline capture error: $e');
      return false;
    }
  }

  Future<void> _syncToFirebase(LocationModel location) async {
    // FINAL AUTHENTICATION GUARD - CRITICAL
    if (!await _isDriverAuthenticated(location.driverId)) {
      throw Exception('Permission Denied: User not authenticated or invalid driver');
    }

    final docRef = _firestore.collection('drivers').doc(location.driverId);
    WriteBatch batch = _firestore.batch();
    
    // Update main driver document
    batch.update(docRef, {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'lastUpdate': FieldValue.serverTimestamp(),
      'status': 'active',
      'isOnDuty': location.isOnDuty,
    });

    // Add to location history
    final historyRef = docRef.collection('locations').doc();
    batch.set(historyRef, {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'timestamp': Timestamp.fromDate(location.timestamp),
      'accuracy': location.accuracy,
      'speed': location.speed,
      'batteryLevel': location.batteryLevel,
    });

    await batch.commit();
  }

  Future<int> syncOfflineLocations() async {
    // Check authentication before sync
    if (!await _isDriverAuthenticatedForAnyDriver()) {
      debugPrint('Sync blocked: No authenticated driver');
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
          debugPrint('Sync failed for location, stopping retries: $e');
          break; // Stop on first failure to avoid spamming
        }
      }
      return count;
    } catch (e) {
      debugPrint('Sync error: $e');
      return 0;
    }
  }

  Future<bool> shouldContinueTracking() async {
    final active = await _dutyService.isDutyActive();
    return active && await _isDriverAuthenticatedForAnyDriver();
  }

  // CRITICAL: Authentication verification method
  Future<bool> _isDriverAuthenticated(String driverId) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    final email = user.email;
    if (email == null) return false;
    
    // Check email format and driver ID match
    final isValidFormat = RegExp(r'.*@driverapp\.com$').hasMatch(email);
    final containsDriverId = email.contains(driverId);
    
    return isValidFormat && containsDriverId;
  }

  // Helper to check if any driver is authenticated
  Future<bool> _isDriverAuthenticatedForAnyDriver() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    final email = user.email;
    if (email == null) return false;
    
    return RegExp(r'.*@driverapp\.com$').hasMatch(email);
  }

  Stream<ConnectivityResult> get connectivityStream => _connectivity.onConnectivityChanged;
}
