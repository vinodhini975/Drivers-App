import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  /// Shows a custom dialog to request location permissions
  static Future<bool> requestLocationPermissionWithDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _LocationPermissionDialog(),
    ) ?? false;
  }
}

class _LocationPermissionDialog extends StatefulWidget {
  const _LocationPermissionDialog();

  @override
  State<_LocationPermissionDialog> createState() => _LocationPermissionDialogState();
}

class _LocationPermissionDialogState extends State<_LocationPermissionDialog> {
  bool _isLoading = true;
  String _status = 'Checking permissions...';

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    try {
      setState(() {
        _status = 'Checking location permissions...';
      });

      // Check current location permission status
      var locationStatus = await Permission.location.status;
      
      if (locationStatus.isGranted) {
        // Check background location permission for Android 10+
        final backgroundLocationStatus = await Permission.locationAlways.status;
        
        if (backgroundLocationStatus.isGranted) {
          // Both permissions granted
          if (mounted) {
            Navigator.of(context).pop(true);
          }
          return;
        } else {
          setState(() {
            _status = 'Requesting background location permission...';
          });

          // Request background location permission
          final result = await Permission.locationAlways.request();
          
          if (result.isGranted) {
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          } else {
            // Handle denied permission
            setState(() {
              _isLoading = false;
              _status = 'Permission required for tracking';
            });
          }
        }
      } else {
        setState(() {
          _status = 'Requesting location permission...';
        });

        // Request location permission
        final result = await Permission.location.request();
        
        if (result.isGranted) {
          // Now request background location permission
          setState(() {
            _status = 'Requesting background location permission...';
          });

          final backgroundResult = await Permission.locationAlways.request();
          
          if (backgroundResult.isGranted) {
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          } else {
            setState(() {
              _isLoading = false;
              _status = 'Background permission required for tracking';
            });
          }
        } else {
          setState(() {
            _isLoading = false;
            _status = 'Location permission required for tracking';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Error requesting permissions';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.location_on, color: Colors.green),
          SizedBox(width: 8),
          Text('Location Permission Required'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _status,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          if (_isLoading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Please allow the requested permissions to enable location tracking.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_isLoading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _checkAndRequestPermissions,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ],
    );
  }
}