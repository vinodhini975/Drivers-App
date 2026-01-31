import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/driver_model.dart';

class AuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _userMobileKey = 'user_mobile';

  /* ================= OTP MECHANISM (UNCHANGED) ================= */
  Future<bool> verifyOtp(String otp) async {
    return RegExp(r'^[0-9]{4,6}$').hasMatch(otp);
  }

  /* ================= SESSION PERSISTENCE ================= */
  Future<void> saveSession(String mobile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_userMobileKey, mobile);
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  /// Returns the stored mobile number (Driver ID) directly
  Future<String?> getCurrentDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userMobileKey);
  }

  Future<String?> getSavedMobile() async {
    return getCurrentDriverId();
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /* ================= DATA FETCHING ================= */
  Future<DriverModel?> getDriverByMobile(String mobile) async {
    final query = await _firestore
        .collection('drivers')
        .where('phoneNumber', isEqualTo: mobile)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return DriverModel.fromFirestore(query.docs.first);
  }

  Future<DriverModel?> getCurrentDriver() async {
    final mobile = await getCurrentDriverId();
    if (mobile == null) return null;
    return await getDriverByMobile(mobile);
  }
}
