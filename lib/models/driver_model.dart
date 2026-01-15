import 'package:cloud_firestore/cloud_firestore.dart';

class DriverModel {
  final String driverId;
  final String name;
  final String email;
  final String phoneNumber;
  final String vehicleId;
  final String licenseNumber;
  final String zone;
  final String ward;
  final bool isActive;
  final String? status;
  final String? deviceId;
  final DateTime? lastLogin;
  final DateTime createdAt;

  DriverModel({
    required this.driverId,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.vehicleId,
    required this.licenseNumber,
    required this.zone,
    required this.ward,
    this.isActive = false,
    this.status,
    this.deviceId,
    this.lastLogin,
    required this.createdAt,
  });

  factory DriverModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DriverModel(
      driverId: doc.id,
      name: data['name'] ?? 'Driver ${doc.id}',
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      vehicleId: data['vehicleId'] ?? '',
      licenseNumber: data['licenseNumber'] ?? '',
      zone: data['zone'] ?? '',
      ward: data['ward'] ?? '',
      isActive: data['isActive'] ?? (data['status'] == 'active'),
      status: data['status'] as String?,
      deviceId: data['deviceId'],
      lastLogin: data['lastLogin'] != null 
          ? (data['lastLogin'] as Timestamp).toDate() 
          : null,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'vehicleId': vehicleId,
      'licenseNumber': licenseNumber,
      'zone': zone,
      'ward': ward,
      'isActive': isActive,
      'status': status,
      'deviceId': deviceId,
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
