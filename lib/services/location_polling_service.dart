import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_location_service.dart';

class LocationPollingService {
  static Timer? _timer;
  static bool _isPolling = false;
  static String? _currentUsername;
  static DateTime? _lastLocationUpdate;
  
  // Throttle updates to avoid excessive Firestore writes
  static const Duration _minUpdateInterval = Duration(seconds: 30);

  /// Starts polling for location updates from the native service
  static void startPolling(String username) {
    _currentUsername = username;
    if (!_isPolling) {
      _isPolling = true;
      print('📍 LocationPollingService: Starting to poll for $username');
      // Poll every 10 seconds instead of 5 to reduce resource usage
      _timer = Timer.periodic(const Duration(seconds: 10), (timer) async {
        await _checkForLocationUpdates();
      });
    }
  }

  /// Stops polling for location updates
  static void stopPolling() {
    _timer?.cancel();
    _isPolling = false;
    _currentUsername = null;
    _lastLocationUpdate = null;
    print('📍 LocationPollingService: Stopped polling');
  }

  /// Checks if there are any location updates from the native service
  static Future<void> _checkForLocationUpdates() async {
    if (_currentUsername == null) return;

    final locationData = await NativeLocationService.getLastLocation();
    
    if (locationData != null && locationData['updated'] == true) {
      final lat = locationData['lat'] as double;
      final lng = locationData['lng'] as double;
      final username = locationData['username'] as String;
      
      print('📍 LocationPollingService: Received location update for $username: $lat, $lng');
      
      // Check if enough time has passed since the last update to avoid excessive writes
      final now = DateTime.now();
      if (_lastLocationUpdate == null || 
          now.difference(_lastLocationUpdate!) >= _minUpdateInterval) {
        // Update location in Firestore
        await NativeLocationService.updateLocation(username, lat, lng);
        _lastLocationUpdate = now;
        print('📍 LocationPollingService: Updated location in Firestore for $username at $now');
      } else {
        print('📍 LocationPollingService: Skipping update for $username (throttled)');
      }
    }
  }

  /// Returns whether the polling service is currently active
  static bool isPolling() {
    return _isPolling;
  }
  
  /// Gets the last update time
  static DateTime? getLastUpdateTime() {
    return _lastLocationUpdate;
  }
}