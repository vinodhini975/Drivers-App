import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../models/driver_model.dart';
import '../services/auth_service.dart';
import '../services/permission_edge_case_handler.dart';
import 'home_screen.dart';

class LocationPermissionScreen extends StatefulWidget {
  final DriverModel driver;
  const LocationPermissionScreen({super.key, required this.driver});

  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  final AuthService _authService = AuthService();
  bool _isCheckingPermissions = false;
  bool _permissionsGranted = false;
  String _statusMessage = 'Checking location permissions...';
  List<String> _permissionStatus = [];

  @override
  void initState() {
    super.initState();
    _handleEdgeCasesOnInit();
  }

  /// Handle all edge cases on initialization
  Future<void> _handleEdgeCasesOnInit() async {
    setState(() {
      _isCheckingPermissions = true;
      _statusMessage = 'Checking permissions and system status...';
    });

    try {
      final result = await PermissionEdgeCaseHandler.handleAllEdgeCases();
      
      switch (result.action) {
        case PermissionAction.PROCEED:
          setState(() {
            _permissionsGranted = true;
            _statusMessage = 'All permissions and services are ready!';
            _isCheckingPermissions = false;
          });
          
          // Auto-proceed to home screen
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            _navigateToHome();
          }
          break;
          
        case PermissionAction.REDIRECT_TO_PERMISSION_SCREEN:
        case PermissionAction.REDIRECT_TO_GPS_SETTINGS:
          setState(() {
            _permissionsGranted = false;
            _statusMessage = result.reason;
            _isCheckingPermissions = false;
          });
          
          // Show detailed status
          _permissionStatus = result.details.entries
              .map((e) => '${e.key}: ${e.value}')
              .toList();
          break;
          
        case PermissionAction.REDIRECT_TO_APP_SETTINGS:
          _handlePermanentlyDenied();
          break;
          
        case PermissionAction.SHOW_WARNING:
          _showWarningDialog(result.reason);
          break;
          
        case PermissionAction.SHOW_ERROR:
          setState(() {
            _statusMessage = 'Error: ${result.reason}';
            _isCheckingPermissions = false;
          });
          break;
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error during initialization: $e';
        _isCheckingPermissions = false;
      });
    }
  }

  /// Check all required location permissions
  Future<void> _checkAllPermissions() async {
    setState(() {
      _isCheckingPermissions = true;
      _statusMessage = 'Checking location permissions...';
      _permissionStatus = [];
    });

    try {
      // Check all required permissions
      final fineLocationStatus = await Permission.location.status;
      final coarseLocationStatus = await Permission.locationWhenInUse.status;
      final backgroundLocationStatus = await Permission.locationAlways.status;
      
      _updatePermissionStatus('Fine Location', fineLocationStatus);
      _updatePermissionStatus('Coarse Location', coarseLocationStatus);
      _updatePermissionStatus('Background Location', backgroundLocationStatus);

      // Check if all permissions are granted
      final allGranted = fineLocationStatus.isGranted && 
                        coarseLocationStatus.isGranted && 
                        backgroundLocationStatus.isGranted;

      if (allGranted) {
        // Also check if GPS is enabled
        final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
        if (isGpsEnabled) {
          setState(() {
            _permissionsGranted = true;
            _statusMessage = 'All location permissions granted!';
            _isCheckingPermissions = false;
          });
          
          // Auto-proceed to home screen after brief delay
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            _navigateToHome();
          }
        } else {
          setState(() {
            _statusMessage = 'Please enable GPS in device settings';
            _isCheckingPermissions = false;
          });
          _showGpsDialog();
        }
      } else {
        setState(() {
          _permissionsGranted = false;
          _statusMessage = 'Location permission is mandatory to continue';
          _isCheckingPermissions = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error checking permissions: $e';
        _isCheckingPermissions = false;
      });
    }
  }

  void _updatePermissionStatus(String permissionName, PermissionStatus status) {
    String statusText;
    switch (status) {
      case PermissionStatus.granted:
        statusText = '✓ GRANTED';
        break;
      case PermissionStatus.denied:
        statusText = '✗ DENIED';
        break;
      case PermissionStatus.permanentlyDenied:
        statusText = '✗ PERMANENTLY DENIED';
        break;
      case PermissionStatus.restricted:
        statusText = '✗ RESTRICTED';
        break;
      case PermissionStatus.limited:
        statusText = '⚠ LIMITED';
        break;
      default:
        statusText = '? UNKNOWN';
    }
    _permissionStatus.add('$permissionName: $statusText');
  }

  /// Request all required permissions
  Future<void> _requestAllPermissions() async {
    setState(() {
      _isCheckingPermissions = true;
      _statusMessage = 'Requesting location permissions...';
    });

    try {
      // Request fine location first
      var fineLocationStatus = await Permission.location.request();
      
      if (fineLocationStatus.isGranted) {
        // Request background location (Android 10+)
        var backgroundLocationStatus = await Permission.locationAlways.request();
        
        if (backgroundLocationStatus.isGranted) {
          // Verify GPS is enabled
          final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
          if (isGpsEnabled) {
            setState(() {
              _permissionsGranted = true;
              _statusMessage = 'All permissions granted successfully!';
            });
            
            // Navigate to home screen
            await Future.delayed(const Duration(seconds: 1));
            if (mounted) {
              _navigateToHome();
            }
          } else {
            setState(() {
              _statusMessage = 'Please enable GPS in device settings';
            });
            _showGpsDialog();
          }
        } else {
          _handlePermissionDenied('Background location permission is required for continuous tracking');
        }
      } else {
        _handlePermissionDenied('Location permission is mandatory to continue');
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error requesting permissions: $e';
        _isCheckingPermissions = false;
      });
    }
  }

  void _handlePermissionDenied(String message) {
    setState(() {
      _permissionsGranted = false;
      _statusMessage = message;
      _isCheckingPermissions = false;
    });
    
    // Show dialog explaining why permissions are mandatory
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Permission Required'),
          content: Text('$message\n\nThis app cannot function without location access.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _handlePermanentlyDenied() {
    setState(() {
      _statusMessage = 'Permissions permanently denied';
      _isCheckingPermissions = false;
    });
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permissions Required'),
          content: const Text('Location permissions are permanently denied. Please enable them in app settings to continue.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await PermissionEdgeCaseHandler.handlePermanentlyDenied();
                await openAppSettings();
              },
              child: const Text('OPEN SETTINGS'),
            ),
          ],
        ),
      );
    }
  }

  void _showWarningDialog(String message) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Warning'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showGpsDialog() {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable GPS'),
          content: const Text('Please enable GPS in your device settings to continue.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await Geolocator.openLocationSettings();
                // Recheck after user returns from settings
                await Future.delayed(const Duration(seconds: 2));
                if (mounted) {
                  _checkAllPermissions();
                }
              },
              child: const Text('OPEN SETTINGS'),
            ),
          ],
        ),
      );
    }
  }

  void _navigateToHome() {
    if (!mounted) return;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(driver: widget.driver),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Location Permission Required'),
        backgroundColor: Colors.red[700],
        automaticallyImplyLeading: false, // Prevent back navigation
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Permission Icon
            Icon(
              _permissionsGranted ? Icons.check_circle : Icons.location_on,
              size: 100,
              color: _permissionsGranted ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 30),
            
            // Status Message
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _permissionsGranted ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 30),
            
            // Permission Status List
            if (_permissionStatus.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Permission Status:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ..._permissionStatus.map((status) => 
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(status),
                      )
                    ).toList(),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
            
            // Action Button
            if (!_permissionsGranted && !_isCheckingPermissions)
              ElevatedButton(
                onPressed: _requestAllPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  'GRANT LOCATION PERMISSIONS',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            
            // Loading Indicator
            if (_isCheckingPermissions)
              const Column(
                children: [
                  SizedBox(height: 20),
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text('Please wait...'),
                ],
              ),
            
            const SizedBox(height: 30),
            
            // Warning Message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: const Column(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 30),
                  SizedBox(height: 10),
                  Text(
                    'Why Location Permission is Required',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  Text(
                    '• Real-time vehicle tracking\n• Municipal waste collection monitoring\n• Supervisor QR code verification\n• Safety and compliance reporting',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}