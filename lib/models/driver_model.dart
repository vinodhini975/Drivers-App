import 'package:cloud_firestore/cloud_firestore.dart';

class DriverModel {
  /// Firestore document ID
  final String id;

  /// Driver details
  final String name;
  final String phoneNumber; // used for OTP login
  final String vehicleId;
  final String licenseNumber;
  final String zone;
  final String ward;

  /// Auth & system fields
  final String? firebaseUid; // 🔑 linked after OTP
  final bool isActive;
  final String? status;
  final String? deviceId;

  /// Metadata
  final DateTime? lastLogin;
  final DateTime createdAt;

  DriverModel({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.vehicleId,
    required this.licenseNumber,
    required this.zone,
    required this.ward,
    this.firebaseUid,
    this.isActive = false,
    this.status,
    this.deviceId,
    this.lastLogin,
    required this.createdAt,
  });

  /* ================= FIRESTORE → MODEL ================= */

  factory DriverModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw Exception('Driver document is empty');
    }

    return DriverModel(
      id: doc.id,
      name: data['name'] ?? 'Driver',
      phoneNumber: data['phoneNumber'] ?? '', // ✅ consistent
      vehicleId: data['vehicleId'] ?? '',
      licenseNumber: data['licenseNumber'] ?? '',
      zone: data['zone'] ?? '',
      ward: data['ward'] ?? '',
      firebaseUid: data['firebaseUid'],
      isActive: data['isActive'] ?? (data['status'] == 'active'),
      status: data['status'],
      deviceId: data['deviceId'],
      lastLogin: data['lastLogin'] != null
          ? (data['lastLogin'] as Timestamp).toDate()
          : null,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /* ================= MODEL → FIRESTORE ================= */

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'vehicleId': vehicleId,
      'licenseNumber': licenseNumber,
      'zone': zone,
      'ward': ward,
      'firebaseUid': firebaseUid,
      'isActive': isActive,
      'status': status,
      'deviceId': deviceId,
      'lastLogin':
      lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
