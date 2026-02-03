import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/driver_model.dart';
import 'home_screen.dart';

class LocationPermissionScreen extends StatefulWidget {
  final DriverModel driver;
  const LocationPermissionScreen({super.key, required this.driver});

  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  static const _platform = MethodChannel('location_permission');
  bool _isProcessing = false;

  Future<void> _handleLocationAccess() async {
    setState(() => _isProcessing = true);

    try {
      // ONE BUTTON HANDSHAKE: Requests permissions + Enables GPS
      final String result = await _platform.invokeMethod('requestLocationAndEnableGPS');
      
      if (result == 'SUCCESS') {
        _navigateToHome();
      } else {
        _showErrorMessage('Location access is required to continue. Please try again.');
      }
    } on PlatformException catch (e) {
      debugPrint('Native error: ${e.message}');
      _showErrorMessage('An unexpected error occurred. Please check your GPS settings.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showErrorMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
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
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on_rounded, size: 100, color: Colors.red),
              const SizedBox(height: 40),
              const Text(
                'Location Permission Required',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 20),
              const Text(
                'TrackConnect requires location access to monitor vehicle movement and sync duty records correctly.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
              ),
              const Spacer(),
              if (_isProcessing)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _handleLocationAccess,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    minimumSize: const Size(double.infinity, 65),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'ALLOW LOCATION ACCESS',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
