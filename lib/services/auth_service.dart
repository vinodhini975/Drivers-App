import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;


    
    try {
    } catch (e) {
    }
  }

  Future<Map<String, dynamic>> signInWithDriverId({
    required String driverId,
    required String password,
  }) async {
    try {

        email: email,
        password: password,
      );

      if (user == null) {
      }

        final prefs = await SharedPreferences.getInstance();
        
        return {
          'success': true,
        };
      }
    } catch (e) {
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
