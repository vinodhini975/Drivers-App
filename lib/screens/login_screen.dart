import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../models/driver_model.dart';
import 'location_permission_screen.dart';
import 'gov_map_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _govPasswordController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _isDriverRole = true;
  bool _otpSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _mobileController.dispose();
    _otpController.dispose();
    _govPasswordController.dispose();
    super.dispose();
  }

  /* ================= DRIVER LOGIN (PERSISTENT) ================= */

  Future<void> _requestOtp() async {
    final mobile = _mobileController.text.trim();
    if (mobile.length != 10) {
      _showMessage('Enter valid 10-digit mobile number', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() { _otpSent = true; _isLoading = false; });
    _showMessage('OTP sent successfully');
  }

  Future<void> _verifyAndLogin() async {
    final otp = _otpController.text.trim();
    final mobile = _mobileController.text.trim();

    final isValid = await _authService.verifyOtp(otp);
    if (!isValid) {
      _showMessage("Enter valid OTP", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final driverId = mobile;
      final driverRef = FirebaseFirestore.instance.collection('drivers').doc(driverId);
      final snapshot = await driverRef.get();

      if (!snapshot.exists) {
        await driverRef.set({
          'driverId': driverId,
          'phoneNumber': driverId,
          'mobile': driverId,
          'name': 'Driver $driverId',
          'vehicleId': 'V-$driverId',
          'createdAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'status': 'active',
        });
      }

      final driverDoc = await driverRef.get();
      final driver = DriverModel.fromFirestore(driverDoc);

      // ✅ SAVE DRIVER SESSION LOCALLY
      await _authService.saveDriverSession(mobile);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LocationPermissionScreen(driver: driver)),
      );
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /* ================= GOVT LOGIN (PERSISTENT) ================= */

  void _loginGovernment() async {
    if (_govPasswordController.text == 'admin') {
      // ✅ SAVE GOVT SESSION LOCALLY
      await _authService.saveGovSession();
      
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GovMapScreen()));
    } else {
      _showMessage('Invalid password', isError: true);
    }
  }

  /* ================= UI COMPONENTS ================= */

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color mainColor = _isDriverRole ? Colors.green[700]! : Colors.blue[900]!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Icon(Icons.local_shipping, size: 100, color: mainColor),
              const SizedBox(height: 10),
              Text('BBMP VEHICLE', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: mainColor)),
              const SizedBox(height: 40),
              ToggleButtons(
                isSelected: [_isDriverRole, !_isDriverRole],
                onPressed: (i) => setState(() { _isDriverRole = i == 0; _otpSent = false; }),
                borderRadius: BorderRadius.circular(15),
                fillColor: mainColor,
                selectedColor: Colors.white,
                constraints: BoxConstraints(minWidth: (MediaQuery.of(context).size.width - 60) / 2, minHeight: 60),
                children: const [
                  Text('DRIVER', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('GOVT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 40),
              Expanded(child: SingleChildScrollView(child: _isDriverRole ? _driverUI(mainColor) : _govUI(mainColor))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _driverUI(Color color) {
    return Column(
      children: [
        TextField(
          controller: _mobileController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          enabled: !_otpSent && !_isLoading,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: InputDecoration(labelText: 'MOBILE NUMBER', prefixIcon: const Icon(Icons.phone_android), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)), counterText: ''),
        ),
        const SizedBox(height: 25),
        if (_otpSent) ...[
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 10),
            decoration: InputDecoration(labelText: 'ENTER OTP', border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)), counterText: ''),
          ),
          const SizedBox(height: 25),
          _bigButton('VERIFY & LOGIN', _verifyAndLogin, color),
        ] else
          _bigButton('GET OTP', _requestOtp, color),
      ],
    );
  }

  Widget _govUI(Color color) {
    return Column(
      children: [
        TextField(
          controller: _govPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'ADMIN PASSWORD',
            prefixIcon: const Icon(Icons.admin_panel_settings),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
        const SizedBox(height: 30),
        _bigButton('GOVT LOGIN', _loginGovernment, color),
      ],
    );
  }

  Widget _bigButton(String text, VoidCallback onTap, Color color) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(backgroundColor: color, minimumSize: const Size(double.infinity, 80), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}
