import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../models/driver_model.dart';
import '../services/permission_edge_case_handler.dart';
import 'home_screen.dart';

class LocationPermissionScreen extends StatefulWidget {
  final DriverModel driver;
  const LocationPermissionScreen({super.key, required this.driver});

  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _isCheckingPermissions = false;
  bool _permissionsGranted = false;
  String _instructionMessage = 'Grant location access to continue';

  @override
  void initState() {
    super.initState();
    _handleEdgeCasesOnInit();
  }

  Future<void> _handleEdgeCasesOnInit() async {
    setState(() {
      _isCheckingPermissions = true;
    });

    try {
      final result = await PermissionEdgeCaseHandler.handleAllEdgeCases();
      
      if (!mounted) return;

      switch (result.action) {
        case PermissionAction.PROCEED:
          setState(() {
            _permissionsGranted = true;
            _isCheckingPermissions = false;
          });
          _navigateToHome();
          break;
          
        case PermissionAction.REDIRECT_TO_PERMISSION_SCREEN:
        case PermissionAction.REDIRECT_TO_GPS_SETTINGS:
          setState(() {
            _permissionsGranted = false;
            _instructionMessage = result.reason;
            _isCheckingPermissions = false;
          });
          break;
          
        case PermissionAction.REDIRECT_TO_APP_SETTINGS:
          _handlePermanentlyDenied();
          break;
          
        case PermissionAction.SHOW_WARNING:
          _showWarningDialog(result.reason);
          break;
          
        case PermissionAction.SHOW_ERROR:
          setState(() {
            _instructionMessage = result.reason;
            _isCheckingPermissions = false;
          });
          break;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingPermissions = false;
        });
      }
    }
  }

  Future<void> _requestAllPermissions() async {
    setState(() => _isCheckingPermissions = true);

    try {
      var status = await Permission.location.request();
      if (status.isGranted || status.isLimited) {
        var bgStatus = await Permission.locationAlways.request();
        if (bgStatus.isGranted) {
          if (await Geolocator.isLocationServiceEnabled()) {
            _navigateToHome();
            return;
          } else {
            _showGpsDialog();
          }
        }
      }
      
      if (status.isPermanentlyDenied) {
        _handlePermanentlyDenied();
      }
    } finally {
      if (mounted) setState(() => _isCheckingPermissions = false);
    }
  }

  void _handlePermanentlyDenied() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings Required'),
        content: const Text('Location access is mandatory. Please enable "Allow all the time" in App Settings.'),
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

  void _showGpsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS Disabled'),
        content: const Text('Please enable GPS in your device settings to start tracking.'),
        actions: [
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('ENABLE GPS'),
          ),
        ],
      ),
    );
  }

  void _showWarningDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notice'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => HomeScreen(driver: widget.driver)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(
                Icons.location_on_rounded,
                size: 100,
                color: _permissionsGranted ? Colors.green : Colors.redAccent,
              ),
              const SizedBox(height: 40),
              const Text(
                'Location Required',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                _instructionMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
              ),
              const Spacer(),
              if (_isCheckingPermissions)
                const CircularProgressIndicator()
              else if (!_permissionsGranted)
                ElevatedButton(
                  onPressed: _requestAllPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    minimumSize: const Size(double.infinity, 65),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'ALLOW ACCESS',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
