import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String? uid;
  final String? name;
  final String? phoneNumber;
  final DateTime? dob;
  final String? gender;
  final GeoPoint? location;
  final String? profileImageUrl;
  final String? email;
  final String? role;
  final String? fcmToken;
  final Map<String, dynamic>? driverDetails;

  UserModel({
    this.uid,
    this.name,
    this.phoneNumber,
    this.dob,
    this.gender,
    this.location,
    this.profileImageUrl,
    this.email,
    this.role,
    this.fcmToken,
    this.driverDetails,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    GeoPoint? location;
    if (json['location'] != null) {
      if (json['location'] is GeoPoint) {
        location = json['location'] as GeoPoint;
      } else if (json['location'] is String) {
        final parts = (json['location'] as String).split(',');
        if (parts.length == 2) {
          final latitude = double.tryParse(parts[0].trim());
          final longitude = double.tryParse(parts[1].trim());
          if (latitude != null && longitude != null) {
            location = GeoPoint(latitude, longitude);
          }
        }
      }
    }

    return UserModel(
      uid: json['uid'] as String?,
      name: json['name'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      dob: json['dob'] != null
          ? (json['dob'] is Timestamp
              ? (json['dob'] as Timestamp).toDate()
              : DateTime.tryParse(json['dob'] as String))
          : null,
      gender: json['gender'] as String?,
      location: location,
      profileImageUrl: json['profileImageUrl'] as String?,
      email: json['email'] as String?,
      role: json['role'] as String?,
      fcmToken: json['fcmToken'] as String?,
      driverDetails: json['driverDetails'] != null
          ? Map<String, dynamic>.from(json['driverDetails'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['uid'] = uid;
    data['name'] = name;
    data['phoneNumber'] = phoneNumber;
    if (dob != null) {
      data['dob'] = Timestamp.fromDate(dob!);
    }
    data['gender'] = gender;
    if (location != null) {
      data['location'] = location;
    }
    data['profileImageUrl'] = profileImageUrl;
    data['email'] = email;
    data['role'] = role;
    if (fcmToken != null) {
      data['fcmToken'] = fcmToken;
    }
    if (driverDetails != null) {
      data['driverDetails'] = driverDetails;
    }
    return data;
  }

  UserModel copyWith({
    String? uid,
    String? name,
    String? phoneNumber,
    DateTime? dob,
    String? gender,
    GeoPoint? location,
    String? profileImageUrl,
    String? email,
    String? role,
    String? fcmToken,
    Map<String, dynamic>? driverDetails,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      location: location ?? this.location,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      email: email ?? this.email,
      role: role ?? this.role,
      fcmToken: fcmToken ?? this.fcmToken,
      driverDetails: driverDetails ?? this.driverDetails,
    );
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, name: $name, phoneNumber: $phoneNumber, dob: $dob, '
        'gender: $gender, location: $location, profileImageUrl: $profileImageUrl, '
        'email: $email, role: $role, fcmToken: $fcmToken, driverDetails: $driverDetails)';
  }
}
