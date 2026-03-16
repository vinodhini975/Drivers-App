import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/driver_model.dart';
import 'home_screen.dart';

class GoogleSignupCompleteScreen extends StatefulWidget {
  final String email;
  final String name;
  final String suggestedDriverId;

  const GoogleSignupCompleteScreen({
    super.key,
    required this.email,
    required this.name,
    required this.suggestedDriverId,
  });

  @override
  State<GoogleSignupCompleteScreen> createState() => _GoogleSignupCompleteScreenState();
}

class _GoogleSignupCompleteScreenState extends State<GoogleSignupCompleteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  
  late final TextEditingController _driverIdController;
  final _phoneController = TextEditingController();
  final _vehicleIdController = TextEditingController();
  final _licenseController = TextEditingController();
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _driverIdController = TextEditingController(text: widget.suggestedDriverId);
  }

  @override
  void dispose() {
    _driverIdController.dispose();
    _phoneController.dispose();
    _vehicleIdController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _completeRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final result = await _authService.completeGoogleSignUp(
        driverId: _driverIdController.text.trim().toUpperCase(),
        phoneNumber: _phoneController.text.trim(),
        vehicleId: _vehicleIdController.text.trim().toUpperCase(),
        licenseNumber: _licenseController.text.trim().toUpperCase(),
      );

      if (!mounted) return;

      if (result['success']) {
        _showMessage(result['message'], isError: false);
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(driver: result['driver'] as DriverModel),
          ),
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
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 15),
              ),
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
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
                  Icons.verified_user,
                  size: 60,
                  color: Colors.green[700],
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome, ${widget.name}!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Complete your driver profile to get started',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Email (read-only)
                TextFormField(
                  initialValue: widget.email,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Email (from Google)',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Driver ID
                _buildTextField(
                  controller: _driverIdController,
                  label: 'Driver ID',
                  hint: 'e.g., DRV001',
                  icon: Icons.badge,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Driver ID is required';
                    }
                    if (!RegExp(r'^[A-Z]{3}\d{3}$').hasMatch(value.toUpperCase())) {
                      return 'Format: 3 letters + 3 numbers (e.g., DRV001)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Phone Number
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  hint: '+1234567890',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Phone number is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Vehicle ID
                _buildTextField(
                  controller: _vehicleIdController,
                  label: 'Vehicle ID',
                  hint: 'VEH-001',
                  icon: Icons.local_shipping,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Vehicle ID is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // License Number
                _buildTextField(
                  controller: _licenseController,
                  label: 'License Number',
                  hint: 'DL123456',
                  icon: Icons.credit_card,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'License number is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                
                // Complete Registration Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _completeRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Complete Registration',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You signed in with Google. No password needed!',
                          style: TextStyle(
                            color: Colors.blue[800],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
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
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.words,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.green[700]!, width: 2),
        ),
      ),
    );
  }
}
