import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionEdgeCaseHandler {
  static const String _PERMISSION_STATUS_KEY = 'permission_status_verified';
  
  /// Handle all edge cases for permission management
  static Future<PermissionEdgeCaseResult> handleAllEdgeCases() async {
    try {
      // Check 1: Basic permission status
      final permissionStatus = await LocationPermissionService.checkAllPermissions();
      
      if (!permissionStatus.allGranted) {
        return PermissionEdgeCaseResult(
          action: PermissionAction.REDIRECT_TO_PERMISSION_SCREEN,
          reason: 'Required permissions not granted',
          details: permissionStatus.getPermissionStatusMap(),
        );
      }

      // Check 2: GPS status
      if (!permissionStatus.isGpsEnabled) {
        return PermissionEdgeCaseResult(
          action: PermissionAction.REDIRECT_TO_GPS_SETTINGS,
          reason: 'GPS is disabled',
          details: {'GPS': 'DISABLED'},
        );
      }

      // Check 3: Verify we can actually get location
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 5),
        );
        if (position.latitude == 0.0 && position.longitude == 0.0) {
          return PermissionEdgeCaseResult(
            action: PermissionAction.SHOW_WARNING,
            reason: 'Location services may not be working properly',
            details: {'Location': 'ZERO_COORDINATES'},
          );
        }
      } catch (e) {
        return PermissionEdgeCaseResult(
          action: PermissionAction.SHOW_WARNING,
          reason: 'Unable to get current location: $e',
          details: {'Location': 'UNAVAILABLE'},
        );
      }

      // All checks passed
      await _markPermissionsAsVerified();
      return PermissionEdgeCaseResult(
        action: PermissionAction.PROCEED,
        reason: 'All permissions and services are working correctly',
        details: permissionStatus.getPermissionStatusMap(),
      );

    } catch (e) {
      return PermissionEdgeCaseResult(
        action: PermissionAction.SHOW_ERROR,
        reason: 'Error during permission validation: $e',
        details: {'Error': e.toString()},
      );
    }
  }

  /// Handle app resume scenario
  static Future<PermissionEdgeCaseResult> handleAppResume() async {
    try {
      // Check if permissions were previously verified
      final wasVerified = await _wasPermissionVerified();
      
      if (!wasVerified) {
        return PermissionEdgeCaseResult(
          action: PermissionAction.REDIRECT_TO_PERMISSION_SCREEN,
          reason: 'Permissions need to be re-verified',
          details: {'Status': 'NOT_VERIFIED'},
        );
      }

      // Check current permission status
      final currentStatus = await LocationPermissionService.checkAllPermissions();
      
      if (!currentStatus.allGranted) {
        await _clearPermissionVerification();
        return PermissionEdgeCaseResult(
          action: PermissionAction.REDIRECT_TO_PERMISSION_SCREEN,
          reason: 'Permissions revoked while app was backgrounded',
          details: currentStatus.getPermissionStatusMap(),
        );
      }

      // Check GPS status
      if (!currentStatus.isGpsEnabled) {
        return PermissionEdgeCaseResult(
          action: PermissionAction.REDIRECT_TO_GPS_SETTINGS,
          reason: 'GPS disabled while app was backgrounded',
          details: {'GPS': 'DISABLED'},
        );
      }

      return PermissionEdgeCaseResult(
        action: PermissionAction.PROCEED,
        reason: 'Permissions still valid after app resume',
        details: currentStatus.getPermissionStatusMap(),
      );

    } catch (e) {
      return PermissionEdgeCaseResult(
        action: PermissionAction.SHOW_ERROR,
        reason: 'Error during app resume permission check: $e',
        details: {'Error': e.toString()},
      );
    }
  }

  /// Handle permission revocation during app usage
  static Future<PermissionEdgeCaseResult> handlePermissionRevocation() async {
    try {
      await _clearPermissionVerification();
      
      final currentStatus = await LocationPermissionService.checkAllPermissions();
      
      return PermissionEdgeCaseResult(
        action: PermissionAction.REDIRECT_TO_PERMISSION_SCREEN,
        reason: 'Permissions have been revoked',
        details: currentStatus.getPermissionStatusMap(),
      );

    } catch (e) {
      return PermissionEdgeCaseResult(
        action: PermissionAction.SHOW_ERROR,
        reason: 'Error handling permission revocation: $e',
        details: {'Error': e.toString()},
      );
    }
  }

  /// Handle permanently denied permissions
  static Future<PermissionEdgeCaseResult> handlePermanentlyDenied() async {
    return PermissionEdgeCaseResult(
      action: PermissionAction.REDIRECT_TO_APP_SETTINGS,
      reason: 'Permissions permanently denied. Please enable in app settings.',
      details: {'Status': 'PERMANENTLY_DENIED'},
    );
  }

  /// Mark permissions as verified in shared preferences
  static Future<void> _markPermissionsAsVerified() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_PERMISSION_STATUS_KEY, true);
  }

  /// Check if permissions were previously verified
  static Future<bool> _wasPermissionVerified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_PERMISSION_STATUS_KEY) ?? false;
  }

  /// Clear permission verification status
  static Future<void> _clearPermissionVerification() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_PERMISSION_STATUS_KEY);
  }

  /// Reset all permission-related state
  static Future<void> resetPermissionState() async {
    await _clearPermissionVerification();
  }
}

/// Result class for permission edge case handling
class PermissionEdgeCaseResult {
  final PermissionAction action;
  final String reason;
  final Map<String, String> details;

  PermissionEdgeCaseResult({
    required this.action,
    required this.reason,
    required this.details,
  });

  @override
  String toString() {
    return 'PermissionEdgeCaseResult{action: $action, reason: $reason, details: $details}';
  }
}

/// Actions that can be taken based on permission status
enum PermissionAction {
  PROCEED,                    // All good, continue normal flow
  REDIRECT_TO_PERMISSION_SCREEN,  // Need to request permissions
  REDIRECT_TO_GPS_SETTINGS,   // Need to enable GPS
  REDIRECT_TO_APP_SETTINGS,   // Need to go to app settings
  SHOW_WARNING,               // Show warning but allow proceeding
  SHOW_ERROR                  // Show error and block proceeding
}

/// Extension to make LocationPermissionService accessible
extension LocationPermissionService on Object {
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

  static Future<bool> areAllPermissionsGranted() async {
    try {
      final fineLocation = await Permission.location.status;
      final backgroundLocation = await Permission.locationAlways.status;
      final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      
      return fineLocation.isGranted && backgroundLocation.isGranted && isGpsEnabled;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return false;
    }
  }
}

/// Data class for detailed permission status (copied from location_permission_service.dart)
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