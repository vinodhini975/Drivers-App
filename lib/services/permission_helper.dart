import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class PermissionHelper {
  /// Check if all mandatory permissions are currently granted
  static Future<bool> hasAllPermissions() async {
    final status = await Permission.location.status;
    final bgStatus = await Permission.locationAlways.status;
    
    // Both foreground and background must be granted
    return status.isGranted && bgStatus.isGranted;
  }

  /// Request mandatory permissions in sequence
  static Future<bool> requestAllPermissions(BuildContext context) async {
    // 1. Request Foreground Location (Fine/Coarse)
    var status = await Permission.location.request();
    
    if (status.isGranted) {
      // 2. Request Background Location (Always)
      // Note: Android 11+ requires foreground to be granted first
      var bgStatus = await Permission.locationAlways.request();
      
      if (bgStatus.isGranted) {
        // 3. Check if GPS Hardware is enabled
        bool isGpsOn = await Geolocator.isLocationServiceEnabled();
        if (!isGpsOn) {
          if (context.mounted) {
            await _showGpsDialog(context);
          }
          return await Geolocator.isLocationServiceEnabled();
        }
        return true;
      }
    }
    
    if (status.isPermanentlyDenied || (await Permission.locationAlways.isPermanentlyDenied)) {
      if (context.mounted) {
        _showSettingsDialog(context);
      }
    }
    
    return false;
  }

  static Future<void> _showGpsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS Disabled'),
        content: const Text('Please turn on GPS/Location services to continue.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('OPEN SETMISSIONS'),
          ),
        ],
      ),
    );
  }

  static void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text('Location permission is mandatory. Please enable "Allow all the time" in settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('OPEN SETTINGS'),
          ),
        ],
      ),
    );
  }
}
