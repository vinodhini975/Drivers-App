import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NativeLocationService {
  static const MethodChannel _channel = MethodChannel('location_tracking_service');

  /// Starts the native location tracking service
  static Future<String?> startTracking(String username) async {
    try {
      final result = await _channel.invokeMethod('startTracking', {
        'username': username,
      });
      print('📍 NativeLocationService: Tracking started for $username');
      return result;
    } on PlatformException catch (e) {
      print('Error starting tracking: ${e.message}');
      return null;
    }
  }

  /// Stops the native location tracking service
  static Future<String?> stopTracking() async {
    try {
      final result = await _channel.invokeMethod('stopTracking');
      print('📍 NativeLocationService: Tracking stopped');
      return result;
    } on PlatformException catch (e) {
      print('Error stopping tracking: ${e.message}');
      return null;
    }
  }

  /// Checks if tracking is currently active
  static Future<bool> isTracking() async {
    try {
      final result = await _channel.invokeMethod('isTracking');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Error checking tracking status: ${e.message}');
      return false;
    }
  }
  
  /// Gets the last location from the native service
  static Future<Map<String, dynamic>?> getLastLocation() async {
    try {
      final result = await _channel.invokeMethod('getLastLocation');
      return result;
    } on PlatformException catch (e) {
      print('Error getting last location: ${e.message}');
      return null;
    }
  }
  
  /// Updates location in Firestore - this will be called from the Flutter side
  /// when location updates are received from the native service
  static Future<void> updateLocation(String username, double lat, double lng) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('drivers')
          .doc(username);

      await docRef.set({
        'name': username,
        'lat': lat,
        'lng': lng,
        'isActive': true,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print("📍 Native location updated for $username: $lat, $lng");
    } catch (e) {
      print("❌ Error updating location in Firestore: $e");
    }
  }
}