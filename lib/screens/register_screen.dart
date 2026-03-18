import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/driver_model.dart';
import 'home_screen.dart';
import 'location_permission_screen.dart';


class RegisterScreen extends StatefulWidget {
  final String? verifiedMobile;
  const RegisterScreen({super.key, this.verifiedMobile});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  
  final _driverIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController(); // Hidden for OTP flow
  final _confirmPasswordController = TextEditingController();
  final _vehicleIdController = TextEditingController();
  final _licenseController = TextEditingController();
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.verifiedMobile != null) {
      _phoneController.text = widget.verifiedMobile!;
    }
  }

  @override
  void dispose() {
    _driverIdController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _vehicleIdController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      // If we are in OTP flow, we don't necessarily need a password for Firebase Auth
      // but for consistency with the existing registerDriver service, we'll provide a dummy one if empty
      // or we can update the service. For now, let's use a default if not provided.
      final password = _passwordController.text.isNotEmpty 
          ? _passwordController.text 
          : "OTP_USER_${DateTime.now().millisecondsSinceEpoch}";

      final result = await _authService.registerDriver(
        driverId: _driverIdController.text.trim().toUpperCase(),
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: password,
        phoneNumber: _phoneController.text.trim(),
        vehicleId: _vehicleIdController.text.trim().toUpperCase(),
        licenseNumber: _licenseController.text.trim().toUpperCase(),
        zone: 'Default Zone', 
        ward: 'Default Ward',
      );

      if (!mounted) return;

      if (result['success']) {
        _showMessage(result['message'], isError: false);
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => LocationPermissionScreen(driver: result['driver'] as DriverModel),
          ),
          (route) => false,
        );
      } else {
        _showMessage(result['message'], isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Registration failed: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 15))),
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
    bool isViaOtp = widget.verifiedMobile != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isViaOtp ? 'Complete Profile' : 'Register New Driver'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  isViaOtp ? Icons.how_to_reg : Icons.person_add,
                  size: 60,
                  color: Colors.green[700],
                ),
                const SizedBox(height: 16),
                Text(
                  isViaOtp ? 'Almost there!' : 'Create Your Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isViaOtp ? 'Finish setting up your driver details' : 'Fill in your details to get started',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),
                
                _buildTextField(
                  controller: _driverIdController,
                  label: 'Driver ID',
                  hint: 'e.g., DRV001',
                  icon: Icons.badge,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Driver ID is required';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'John Doe',
                  icon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Name is required';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  hint: '10-digit number',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  enabled: !isViaOtp, // Disable if coming from OTP verification
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Phone number is required';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'driver@example.com',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Email is required';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                _buildTextField(
                  controller: _vehicleIdController,
                  label: 'Vehicle ID',
                  hint: 'VEH-001',
                  icon: Icons.local_shipping,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Vehicle ID is required';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                _buildTextField(
                  controller: _licenseController,
                  label: 'License Number',
                  hint: 'DL123456',
                  icon: Icons.credit_card,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'License number is required';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                if (!isViaOtp) ...[
                   _buildTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'At least 6 characters',
                    icon: Icons.lock,
                    isPassword: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Password is required';
                      if (value.length < 6) return 'At least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                ],
                
                ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isViaOtp ? 'COMPLETE REGISTRATION' : 'REGISTER',
                          style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool enabled = true,
    bool isPassword = false,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: isPassword,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: !enabled,
        fillColor: !enabled ? Colors.grey[100] : null,
      ),
    );
  }
}
