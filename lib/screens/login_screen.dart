import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/driver_model.dart';
import 'location_permission_screen.dart';
import 'gov_map_screen.dart';
import 'register_screen.dart';
import 'google_signup_complete_screen.dart';
import 'home_screen.dart';
import 'location_permission_screen.dart';

import '../services/location_permission_service.dart';

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
  bool _isLoading = false;
  bool _otpSent = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _mobileController.dispose();
    _otpController.dispose();
    _govPasswordController.dispose();
    super.dispose();
  }

  /* ================= DRIVER OTP LOGIN/SIGNUP ================= */

  Future<void> _handleGetOtp() async {
    final mobile = _mobileController.text.trim();
    if (mobile.length < 10) {
      _showMessage(
        'Please enter a valid 10-digit mobile number',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.requestOtp(mobile);
      setState(() => _otpSent = true);
      _showMessage('OTP has been sent to $mobile');
    } catch (e) {
      _showMessage('Error sending OTP: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerifyAndProceed() async {
    final otp = _otpController.text.trim();
    final mobile = _mobileController.text.trim();

    if (otp.isEmpty) {
      _showMessage('Please enter the OTP', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final isValid = await _authService.verifyOtp(otp);
      if (!isValid) {
        _showMessage('Invalid OTP. Please try again.', isError: true);
        return;
      }

      // Check if driver exists
      final driver = await _authService.getDriverByMobile(mobile);

      if (!mounted) return;

      if (driver != null) {
        // Existing User - Login
        _showMessage('Welcome back, ${driver.name}!');
        await _authService.saveDriverSession(mobile, driverId: driver.id);

        if (!mounted) return;

        // Check permissions before proceeding to Home
        final hasPerms =
            await LocationPermissionService.areAllPermissionsGranted();

        if (hasPerms) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomeScreen(driver: driver)),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => LocationPermissionScreen(driver: driver),
            ),
          );
        }
      } else {
        // New User - Redirect to Register
        _showMessage('Mobile verified. Please complete your registration.');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RegisterScreen(verifiedMobile: mobile),
          ),
        );
      }
    } catch (e) {
      _showMessage('Verification failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final result = await _authService.signInWithGoogle();
      if (!mounted) return;

      if (result['success']) {
        _showMessage(result['message']);
        final driver = result['driver'] as DriverModel;

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => LocationPermissionScreen(driver: driver),
          ),
        );
      } else if (result['isNewUser'] == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoogleSignupCompleteScreen(
              email: result['email'],
              name: result['name'],
              suggestedDriverId: result['suggestedDriverId'],
            ),
          ),
        );
      } else {
        _showMessage(result['message'], isError: true);
      }
    } catch (e) {
      _showMessage('Google sign-in failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /* ================= GOVT LOGIN ================= */

  void _loginGovernment() async {
    if (_govPasswordController.text == 'admin') {
      await _authService.saveGovSession();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GovMapScreen()),
      );
    } else {
      _showMessage('Invalid password', isError: true);
    }
  }

  /* ================= UI COMPONENTS ================= */

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color mainColor = _isDriverRole
        ? Colors.green[700]!
        : Colors.blue[900]!;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.local_shipping, size: 80, color: mainColor),
                const SizedBox(height: 15),
                Text(
                  _isDriverRole ? 'BBMP VEHICLE TRACKING' : 'GOVERNMENT ACCESS',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: mainColor,
                  ),
                ),
                const SizedBox(height: 40),

                // Role Selector
                ToggleButtons(
                  isSelected: [_isDriverRole, !_isDriverRole],
                  onPressed: (index) => setState(() {
                    _isDriverRole = index == 0;
                    _otpSent = false;
                  }),
                  borderRadius: BorderRadius.circular(12),
                  selectedColor: Colors.white,
                  fillColor: mainColor,
                  constraints: BoxConstraints(
                    minWidth: (MediaQuery.of(context).size.width - 60) / 2,
                    minHeight: 60,
                  ),
                  children: const [
                    Text(
                      'DRIVER',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'GOVERNMENT',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                if (_isDriverRole) _driverUI(mainColor) else _govUI(mainColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _driverUI(Color color) {
    return Column(
      children: [
        _buildTextField(
          _mobileController,
          'MOBILE NUMBER',
          Icons.phone_android,
          hintText: 'Enter 10-digit number',
          keyboardType: TextInputType.phone,
          enabled: !_otpSent && !_isLoading,
        ),
        if (_otpSent) ...[
          const SizedBox(height: 16),
          _buildTextField(
            _otpController,
            'ENTER OTP',
            Icons.vpn_key,
            hintText: '6-digit OTP',
            keyboardType: TextInputType.number,
          ),
        ],
        const SizedBox(height: 30),
        _bigButton(
          _otpSent ? 'VERIFY & PROCEED' : 'GET OTP',
          _otpSent ? _handleVerifyAndProceed : _handleGetOtp,
          color,
        ),
        const SizedBox(height: 16),

        if (_otpSent) ...[
          TextButton(
            onPressed: () => setState(() => _otpSent = false),
            child: Text(
              'Change Mobile Number',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  Widget _govUI(Color color) {
    return Column(
      children: [
        _buildTextField(
          _govPasswordController,
          'GOVERNMENT PASSWORD',
          Icons.admin_panel_settings,
          isPassword: true,
        ),
        const SizedBox(height: 30),
        _bigButton('GOVERNMENT LOGIN', _loginGovernment, color),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isPassword = false,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _bigButton(String text, VoidCallback onTap, Color color) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size(double.infinity, 64),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : Text(
              text,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
    );
  }
}
