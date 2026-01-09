import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class NativeLocationService {
  static const MethodChannel _channel = MethodChannel('location_tracking_service');
  static const EventChannel _eventChannel = EventChannel('location_tracking_service/events');

  static Future<String?> startTracking(String driverId) async {
    try {
      final result = await _channel.invokeMethod('startTracking', {
        'username': driverId,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Error starting tracking: ${e.message}');
      return null;
    }
  }

  static Future<String?> stopTracking() async {
    try {
      final result = await _channel.invokeMethod('stopTracking');
      return result;
    } on PlatformException catch (e) {
      debugPrint('Error stopping tracking: ${e.message}');
      return null;
    }
  }

  static Future<bool> isTracking() async {
    try {
      final result = await _channel.invokeMethod('isTracking');
      return result ?? false;
    } on PlatformException catch (e) {
      return false;
    }
  }

  static Stream<Map<String, dynamic>?> getLocationUpdates() {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      if (event == null) return null;
      // SAFE CONVERSION: Converts the internal _Map<Object?, Object?> to Map<String, dynamic>
      return Map<String, dynamic>.from(event as Map);
    }).handleError((error) {
      debugPrint('Error receiving location updates: $error');
      return null;
    });
  }
}
