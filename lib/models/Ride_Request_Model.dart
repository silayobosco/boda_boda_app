import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;

class RideRequestModel {
  final String? id; // Renamed from rideRequestId
  final String customerId; // Made non-nullable
  final String? driverId;
  final gmf.LatLng pickup;
  final gmf.LatLng dropoff;
  final List<Map<String, dynamic>> stops; // Each map: {'name': String, 'location': gmf.LatLng, 'addressName': String?}
  final String status;
  final DateTime? requestTime; // Renamed from timestamp and made nullable
  final String? kijiweId; // Added
  final double? fare; // Added
  final DateTime? acceptedTime; // Added
  final DateTime? completedTime; // Added
  // Denormalized fields for easier display and FCM payloads
  final String? customerName;
  final String? customerProfileImageUrl;
  final String? driverName;
  final String? driverProfileImageUrl;
  final String? pickupAddressName;
  final String? dropoffAddressName;
  // Fields to store ratings given for this specific ride
  final double? customerRatingToDriver;
  final String? customerCommentToDriver;
  final double? driverRatingToCustomer;
  final String? driverCommentToCustomer;


  RideRequestModel({
    this.id,
    required this.customerId,
    this.driverId,
    required this.pickup,
    required this.dropoff,
    required this.stops, 
    required this.status,
    this.requestTime,
    this.kijiweId,
    this.fare,
    this.acceptedTime,
    this.completedTime,
    this.customerName,
    this.customerProfileImageUrl,
    this.driverName,
    this.driverProfileImageUrl,
    this.pickupAddressName,
    this.dropoffAddressName,
    this.customerRatingToDriver,
    this.customerCommentToDriver,
    this.driverRatingToCustomer,
    this.driverCommentToCustomer,
  });

  factory RideRequestModel.fromJson(Map<String, dynamic> json, String rideRequestId) {
    return RideRequestModel(
      id: rideRequestId,
      customerId: json['customerId'] as String,
      driverId: json['driverId'] as String?,
      pickup: gmf.LatLng(
        (json['pickup'] as GeoPoint).latitude,
        (json['pickup'] as GeoPoint).longitude,
      ),
      dropoff: gmf.LatLng(
        (json['dropoff'] as GeoPoint).latitude,
        (json['dropoff'] as GeoPoint).longitude,
      ),
      stops: (json['stops'] as List<dynamic>?)
              ?.map((stopData) {
                final stopMap = stopData as Map<String, dynamic>;
                final locationData = stopMap['location'];
                gmf.LatLng stopLocation;
                if (locationData is GeoPoint) {
                  stopLocation = gmf.LatLng(locationData.latitude, locationData.longitude);
                } else if (locationData is Map) {
                  // Fallback if location is stored as a map {latitude: ..., longitude: ...}
                  stopLocation = gmf.LatLng(
                      (locationData['latitude'] as num).toDouble(),
                      (locationData['longitude'] as num).toDouble());
                } else {
                  // Handle unexpected format or throw error
                  stopLocation = gmf.LatLng(0,0); // Default or error
                }
                return {
                  'name': stopMap['name'] as String,
                  'location': stopLocation,
                  'addressName': stopMap['addressName'] as String?, // Parse addressName
                };
              }).toList() ??
          [],
      status: json['status'] as String,
      requestTime: (json['requestTime'] as Timestamp?)?.toDate(),
      kijiweId: json['kijiweId'] as String?,
      fare: (json['fare'] as num?)?.toDouble(),
      acceptedTime: (json['acceptedTime'] as Timestamp?)?.toDate(),
      completedTime: (json['completedTime'] as Timestamp?)?.toDate(),
      customerName: json['customerName'] as String?,
      customerProfileImageUrl: json['customerProfileImageUrl'] as String?,
      driverName: json['driverName'] as String?,
      driverProfileImageUrl: json['driverProfileImageUrl'] as String?,
      pickupAddressName: json['pickupAddressName'] as String?,
      dropoffAddressName: json['dropoffAddressName'] as String?,
      customerRatingToDriver: (json['customerRatingToDriver'] as num?)?.toDouble(),
      customerCommentToDriver: json['customerCommentToDriver'] as String?,
      driverRatingToCustomer: (json['driverRatingToCustomer'] as num?)?.toDouble(),
      driverCommentToCustomer: json['driverCommentToCustomer'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerId': customerId,
      'driverId': driverId,
      'kijiweId': kijiweId,
      'pickup': GeoPoint(pickup.latitude, pickup.longitude),
      'dropoff': GeoPoint(dropoff.latitude, dropoff.longitude),
      'stops': stops
          .map((stop) => {
                'name': stop['name'],
                'location': GeoPoint((stop['location'] as gmf.LatLng).latitude, (stop['location'] as gmf.LatLng).longitude),
                'addressName': stop['addressName'], // Include addressName
              })
          .toList(),
      'status': status,
      'requestTime': requestTime != null ? Timestamp.fromDate(requestTime!) : FieldValue.serverTimestamp(),
      'fare': fare,
      'acceptedTime': acceptedTime != null ? Timestamp.fromDate(acceptedTime!) : null,
      'completedTime': completedTime != null ? Timestamp.fromDate(completedTime!) : null,
      'customerName': customerName,
      'customerProfileImageUrl': customerProfileImageUrl,
      'driverName': driverName,
      'driverProfileImageUrl': driverProfileImageUrl,
      'pickupAddressName': pickupAddressName,
      'dropoffAddressName': dropoffAddressName,
      'customerRatingToDriver': customerRatingToDriver,
      'customerCommentToDriver': customerCommentToDriver,
      'driverRatingToCustomer': driverRatingToCustomer,
      'driverCommentToCustomer': driverCommentToCustomer,
    };
  }

  RideRequestModel copyWith({
    String? id, // Renamed parameter for clarity and consistency
    String? customerId,
    String? driverId,
    gmf.LatLng? pickup,
    gmf.LatLng? dropoff,
    List<Map<String, dynamic>>? stops,
    String? status,
    DateTime? requestTime,
    String? kijiweId,
    double? fare,
    DateTime? acceptedTime,
    DateTime? completedTime,
    String? customerName,
    String? customerProfileImageUrl,
    String? driverName,
    String? driverProfileImageUrl,
    String? pickupAddressName,
    String? dropoffAddressName,
    double? customerRatingToDriver,
    String? customerCommentToDriver,
    double? driverRatingToCustomer,
    String? driverCommentToCustomer,
  }) {
    return RideRequestModel(
      // Corrected logic: use the provided 'id' parameter if not null, otherwise use current instance's 'id'.
      id: id ?? this.id, 
      customerId: customerId ?? this.customerId,
      driverId: driverId ?? this.driverId,
      pickup: pickup ?? this.pickup,
      dropoff: dropoff ?? this.dropoff,
      stops: stops ?? this.stops,
      status: status ?? this.status,
      requestTime: requestTime ?? this.requestTime,
      kijiweId: kijiweId ?? this.kijiweId,
      fare: fare ?? this.fare,
      acceptedTime: acceptedTime ?? this.acceptedTime,
      completedTime: completedTime ?? this.completedTime,
      customerName: customerName ?? this.customerName,
      customerProfileImageUrl: customerProfileImageUrl ?? this.customerProfileImageUrl,
      driverName: driverName ?? this.driverName,
      driverProfileImageUrl: driverProfileImageUrl ?? this.driverProfileImageUrl,
      pickupAddressName: pickupAddressName ?? this.pickupAddressName,
      dropoffAddressName: dropoffAddressName ?? this.dropoffAddressName,
      customerRatingToDriver: customerRatingToDriver ?? this.customerRatingToDriver,
      customerCommentToDriver: customerCommentToDriver ?? this.customerCommentToDriver,
      driverRatingToCustomer: driverRatingToCustomer ?? this.driverRatingToCustomer,
      driverCommentToCustomer: driverCommentToCustomer ?? this.driverCommentToCustomer,
    );
  }

  @override
  String toString() {
    return 'RideRequestModel(id: $id, customerId: $customerId, driverId: $driverId, '
        'kijiweId: $kijiweId, pickup: $pickup, dropoff: $dropoff, stops: $stops, '
        'status: $status, requestTime: $requestTime, fare: $fare, '
        'acceptedTime: $acceptedTime, completedTime: $completedTime, '
        'customerName: $customerName, pickupAddressName: $pickupAddressName, driverName: $driverName)';
  }
}

class RideHistoryModel {
  final String? rideHistoryId;
  final String customerId;
  final String driverId;
  final gmf.LatLng pickup;
  final gmf.LatLng dropoff;
  final List<Map<String, dynamic>> stops; // Each map: {'name': String, 'location': gmf.LatLng, 'addressName': String?}
  final double distance;
  final double cost;
  final DateTime timestamp;
  final String? kijiweId; // to do
  final double? fare; // to do
  final DateTime? acceptedTime; // to do
  final DateTime? completedTime; // to do
  final String? status; // to do

  RideHistoryModel({
    this.rideHistoryId,
    required this.customerId,
    required this.driverId,
    required this.pickup,
    required this.dropoff,
    required this.stops,
    required this.distance,
    required this.cost,
    required this.timestamp,
    this.kijiweId,
    this.fare,
    this.acceptedTime,
    this.completedTime,
    this.status,
  });

  factory RideHistoryModel.fromJson(Map<String, dynamic> json, String rideHistoryId) {
    return RideHistoryModel(
      rideHistoryId: rideHistoryId,
      customerId: json['customerId'] as String,
      driverId: json['driverId'] as String,
      pickup: gmf.LatLng(
        (json['pickup'] as GeoPoint).latitude,
        (json['pickup'] as GeoPoint).longitude,
      ),
      dropoff: gmf.LatLng(
        (json['dropoff'] as GeoPoint).latitude,
        (json['dropoff'] as GeoPoint).longitude,
      ),
      stops: (json['stops'] as List<dynamic>?)
              ?.map((stopData) {
                final stopMap = stopData as Map<String, dynamic>;
                final locationData = stopMap['location'];
                gmf.LatLng stopLocation;
                 if (locationData is GeoPoint) {
                  stopLocation = gmf.LatLng(locationData.latitude, locationData.longitude);
                } else if (locationData is Map) {
                  stopLocation = gmf.LatLng(
                      (locationData['latitude'] as num).toDouble(),
                      (locationData['longitude'] as num).toDouble());
                } else {
                  stopLocation = gmf.LatLng(0,0); 
                }
                return {
                  'name': stopMap['name'] as String,
                  'location': stopLocation,
                  'addressName': stopMap['addressName'] as String?, // Parse addressName
                };
              }).toList() ?? [],
      distance: (json['distance'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      timestamp: (json['timestamp'] as Timestamp).toDate(),
      kijiweId: json['kijiweId'] as String?,
      fare: (json['fare'] as num?)?.toDouble(),
      acceptedTime: (json['acceptedTime'] as Timestamp?)?.toDate(),
      completedTime: (json['completedTime'] as Timestamp?)?.toDate(),
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerId': customerId,
      'driverId': driverId,
      'pickup': GeoPoint(pickup.latitude, pickup.longitude),
      'dropoff': GeoPoint(dropoff.latitude, dropoff.longitude),
      'stops': stops
          .map((stop) => {
                'name': stop['name'],
                'location': GeoPoint((stop['location'] as gmf.LatLng).latitude, (stop['location'] as gmf.LatLng).longitude),
                'addressName': stop['addressName'], // Include addressName
              })
          .toList(),
      'distance': distance,
      'cost': cost,
      'timestamp': Timestamp.fromDate(timestamp),
      'kijiweId': kijiweId,
      'fare': fare,
      'acceptedTime': acceptedTime != null ? Timestamp.fromDate(acceptedTime!) : null,
      'completedTime': completedTime != null ? Timestamp.fromDate(completedTime!) : null,
      'status': status,
    };
  }

  RideHistoryModel copyWith({
    String? rideHistoryId,
    String? customerId,
    String? driverId,
    gmf.LatLng? pickup,
    gmf.LatLng? dropoff,
    List<Map<String, dynamic>>? stops,
    double? distance,
    double? cost,
    DateTime? timestamp,
    String? kijiweId,
    double? fare,
    DateTime? acceptedTime,
    DateTime? completedTime,
    String? status,
  }) {
    return RideHistoryModel(
      rideHistoryId: rideHistoryId ?? this.rideHistoryId,
      customerId: customerId ?? this.customerId,
      driverId: driverId ?? this.driverId,
      pickup: pickup ?? this.pickup,
      dropoff: dropoff ?? this.dropoff,
      stops: stops ?? this.stops,
      distance: distance ?? this.distance,
      cost: cost ?? this.cost,
      timestamp: timestamp ?? this.timestamp,
      kijiweId: kijiweId ?? this.kijiweId,
      fare: fare ?? this.fare,
      acceptedTime: acceptedTime ?? this.acceptedTime,
      completedTime: completedTime ?? this.completedTime,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'RideHistoryModel(rideHistoryId: $rideHistoryId, customerId: $customerId, '
        'driverId: $driverId, pickup: $pickup, dropoff: $dropoff, stops: $stops, '
        'distance: $distance, cost: $cost, timestamp: $timestamp, '
        'kijiweId: $kijiweId, fare: $fare, acceptedTime: $acceptedTime, '
        'completedTime: $completedTime, status: $status)';
  
  }
  
}