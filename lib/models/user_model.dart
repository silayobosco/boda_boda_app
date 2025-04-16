import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class UserModel {
  final String? uid;
  final String? name;
  final String? phoneNumber;
  final DateTime? dob;
  final String? gender;
  final dynamic location; // Can be GeoPoint or String
  final String? profileImageUrl;
  final String? email;
  final String? role;

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
  });

   // Create UserModel from Firestore data
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
    );
  }

  // Convert UserModel to Firestore data
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['uid'] = uid;
    data['name'] = name;
    data['phoneNumber'] = phoneNumber; // Correct field name
    if (dob != null) {
      data['dob'] = Timestamp.fromDate(dob!);
    }
    data['gender'] = gender;
    if (location != null) {
      data['location'] = location;
      print("Location: ${location?.latitude}, ${location?.longitude}");
    }
    data['profileImageUrl'] = profileImageUrl; // Correct field name
    data['email'] = email;
    data['role'] = role;
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
    );
  }
}
// Data Model for Ride Requests
class RideRequestModel {
  final String? rideRequestId;
  final String? customerId;
  final String? driverId;
  final LatLng pickup;
  final LatLng dropoff;
  final String status; // pending, accepted, completed, cancelled
  final DateTime timestamp;

  RideRequestModel({
    this.rideRequestId,
    required this.customerId,
    this.driverId,
    required this.pickup,
    required this.dropoff,
    required this.status,
    required this.timestamp,
  });

  factory RideRequestModel.fromJson(Map<String, dynamic> json, String rideRequestId) {
    return RideRequestModel(
      rideRequestId: rideRequestId,
      customerId: json['customerId'] as String,
      driverId: json['driverId'] as String?,
      pickup: LatLng(
        (json['pickup'] as GeoPoint).latitude,
        (json['pickup'] as GeoPoint).longitude,
      ),
      dropoff: LatLng(
        (json['dropoff'] as GeoPoint).latitude,
        (json['dropoff'] as GeoPoint).longitude,
      ),
      status: json['status'] as String,
      timestamp: (json['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerId': customerId,
      'driverId': driverId,
      'pickup': GeoPoint(pickup.latitude, pickup.longitude),
      'dropoff': GeoPoint(dropoff.latitude, dropoff.longitude),
      'status': status,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}

// Data Model for Ride History
class RideHistoryModel {
  final String? rideHistoryId;
  final String customerId;
  final String driverId;
  final LatLng pickup;
  final LatLng dropoff;
  final double distance;
  final double cost;
  final DateTime timestamp;

  RideHistoryModel({
    this.rideHistoryId,
    required this.customerId,
    required this.driverId,
    required this.pickup,
    required this.dropoff,
    required this.distance,
    required this.cost,
    required this.timestamp,
  });

  factory RideHistoryModel.fromJson(Map<String, dynamic> json, String rideHistoryId) {
    return RideHistoryModel(
      rideHistoryId: rideHistoryId,
      customerId: json['customerId'] as String,
      driverId: json['driverId'] as String,
      pickup: LatLng(
        (json['pickup'] as GeoPoint).latitude,
        (json['pickup'] as GeoPoint).longitude,
      ),
      dropoff: LatLng(
        (json['dropoff'] as GeoPoint).latitude,
        (json['dropoff'] as GeoPoint).longitude,
      ),
      distance: (json['distance'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      timestamp: (json['timestamp'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerId': customerId,
      'driverId': driverId,
      'pickup': GeoPoint(pickup.latitude, pickup.longitude),
      'dropoff': GeoPoint(dropoff.latitude, dropoff.longitude),
      'distance': distance,
      'cost': cost,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}