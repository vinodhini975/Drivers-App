import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class PermissionHelper {
  /// Comprehensive check for Permissions + GPS Hardware Status
  static Future<bool> ensureLocationRequirement(BuildContext context) async {
    // 1. Check Permissions (Runtime)
    bool hasPermissions = await _handlePermissions(context);
    if (!hasPermissions) return false;

    // 2. Check GPS Hardware (Is it turned ON?)
    bool isGpsOn = await _ensureGpsEnabled(context);
    return isGpsOn;
  }

  static Future<bool> _handlePermissions(BuildContext context) async {
    var status = await Permission.location.status;
    
    if (status.isDenied) {
      status = await Permission.location.request();
    }

    if (status.isPermanentlyDenied) {
      if (context.mounted) {
        _showSettingsDialog(context, 'Location permission is permanently denied. Please enable it in app settings.');
      }
      return false;
    }

    if (status.isGranted) {
      // For Background Tracking (Android 10+)
      var bgStatus = await Permission.locationAlways.status;
      if (bgStatus.isDenied) {
        bgStatus = await Permission.locationAlways.request();
      }
      return bgStatus.isGranted;
    }

    return status.isGranted;
  }

  static Future<bool> _ensureGpsEnabled(BuildContext context) async {
    bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    
    if (!isServiceEnabled) {
      // This will trigger the system dialog on Android if configured correctly,
      // or we provide a clear prompt to the user.
      if (context.mounted) {
        bool userWantsToEnable = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('GPS is Disabled'),
            content: const Text('Location tracking requires GPS to be ON. Would you like to enable it now?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true), 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('YES, ENABLE'),
              ),
            ],
          ),
        ) ?? false;

        if (userWantsToEnable) {
          // Open system location settings
          await Geolocator.openLocationSettings();
          
          // Wait and check again (User comes back from settings)
          int retries = 0;
          while (retries < 5) {
            await Future.delayed(const Duration(seconds: 2));
            if (await Geolocator.isLocationServiceEnabled()) return true;
            retries++;
          }
        }
      }
      return false;
    }
    return true;
  }

  static void _showSettingsDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(onPressed: () => openAppSettings(), child: const Text('OPEN SETTINGS')),
        ],
      ),
    );
  }
}
