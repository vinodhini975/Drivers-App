import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class LocationPermissionService {
  /// Check if all required location permissions are granted
  static Future<bool> areAllPermissionsGranted() async {
    try {
      final fineLocation = await Permission.location.status;
      final backgroundLocation = await Permission.locationAlways.status;
      
      return fineLocation.isGranted && backgroundLocation.isGranted;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return false;
    }
  }

  /// Check detailed permission status for all required permissions
  static Future<PermissionStatusDetails> checkAllPermissions() async {
    try {
      final fineLocation = await Permission.location.status;
      final coarseLocation = await Permission.locationWhenInUse.status;
      final backgroundLocation = await Permission.locationAlways.status;
      final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      
      return PermissionStatusDetails(
        fineLocation: fineLocation,
        coarseLocation: coarseLocation,
        backgroundLocation: backgroundLocation,
        isGpsEnabled: isGpsEnabled,
        allGranted: fineLocation.isGranted && 
                   backgroundLocation.isGranted && 
                   isGpsEnabled,
      );
    } catch (e) {
      debugPrint('Error checking detailed permissions: $e');
      return PermissionStatusDetails(
        fineLocation: PermissionStatus.denied,
        coarseLocation: PermissionStatus.denied,
        backgroundLocation: PermissionStatus.denied,
        isGpsEnabled: false,
        allGranted: false,
      );
    }
  }

  /// Request all required location permissions
  static Future<PermissionRequestResult> requestAllPermissions() async {
    try {
      // Request fine location permission first
      var fineLocationStatus = await Permission.location.request();
      
      if (!fineLocationStatus.isGranted) {
        return PermissionRequestResult(
          success: false,
          message: 'Fine location permission is required',
          deniedPermissions: ['Fine Location'],
        );
      }

      // Request background location permission
      var backgroundLocationStatus = await Permission.locationAlways.request();
      
      if (!backgroundLocationStatus.isGranted) {
        return PermissionRequestResult(
          success: false,
          message: 'Background location permission is required for continuous tracking',
          deniedPermissions: ['Background Location'],
        );
      }

      // Check if GPS is enabled
      final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isGpsEnabled) {
        return PermissionRequestResult(
          success: false,
          message: 'Please enable GPS in device settings',
          deniedPermissions: ['GPS'],
        );
      }

      return PermissionRequestResult(
        success: true,
        message: 'All location permissions granted successfully',
        deniedPermissions: [],
      );
    } catch (e) {
      return PermissionRequestResult(
        success: false,
        message: 'Error requesting permissions: $e',
        deniedPermissions: ['Unknown'],
      );
    }
  }

  /// Open app settings for permission management
  static Future<void> openAppSettings() async {
    await openAppSettings();
  }

  /// Open location settings
  static Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Monitor permission changes
  static Stream<bool> get permissionChangeStream {
    return Permission.location.status.then((_) => true).asStream();
  }
}

/// Data class for detailed permission status
class PermissionStatusDetails {
  final PermissionStatus fineLocation;
  final PermissionStatus coarseLocation;
  final PermissionStatus backgroundLocation;
  final bool isGpsEnabled;
  final bool allGranted;

  PermissionStatusDetails({
    required this.fineLocation,
    required this.coarseLocation,
    required this.backgroundLocation,
    required this.isGpsEnabled,
    required this.allGranted,
  });

  /// Get human-readable status for each permission
  Map<String, String> getPermissionStatusMap() {
    return {
      'Fine Location': _getStatusText(fineLocation),
      'Coarse Location': _getStatusText(coarseLocation),
      'Background Location': _getStatusText(backgroundLocation),
      'GPS Enabled': isGpsEnabled ? '✓ ENABLED' : '✗ DISABLED',
    };
  }

  String _getStatusText(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return '✓ GRANTED';
      case PermissionStatus.denied:
        return '✗ DENIED';
      case PermissionStatus.permanentlyDenied:
        return '✗ PERMANENTLY DENIED';
      case PermissionStatus.restricted:
        return '✗ RESTRICTED';
      case PermissionStatus.limited:
        return '⚠ LIMITED';
      default:
        return '? UNKNOWN';
    }
  }
}

/// Data class for permission request results
class PermissionRequestResult {
  final bool success;
  final String message;
  final List<String> deniedPermissions;

  PermissionRequestResult({
    required this.success,
    required this.message,
    required this.deniedPermissions,
  });
}