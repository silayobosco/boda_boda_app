import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class RideRequestModel {
  final String? rideRequestId;
  final String? customerId;
  final String? driverId;
  final LatLng pickup;
  final LatLng dropoff;
  final List<Map<String, dynamic>> stops; 
  final String status;
  final DateTime timestamp;

  RideRequestModel({
    this.rideRequestId,
    required this.customerId,
    this.driverId,
    required this.pickup,
    required this.dropoff,
    required this.stops, 
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
      stops: (json['stops'] as List<dynamic>)
          .map((stop) => {
                'name': stop['name'],
                'address': stop['address'],
                'location': LatLng(
                  (stop['location']['latitude'] as num).toDouble(),
                  (stop['location']['longitude'] as num).toDouble(),
                ),
              })
          .toList(),
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
      'stops': stops
          .map((stop) => {
                'name': stop['name'],
                'address': stop['address'],
                'location': {
                  'latitude': stop['location'].latitude,
                  'longitude': stop['location'].longitude,
                },
              })
          .toList(),
      'status': status,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  RideRequestModel copyWith({
    String? rideRequestId,
    String? customerId,
    String? driverId,
    LatLng? pickup,
    LatLng? dropoff,
    List<Map<String, dynamic>>? stops,
    String? status,
    DateTime? timestamp,
  }) {
    return RideRequestModel(
      rideRequestId: rideRequestId ?? this.rideRequestId,
      customerId: customerId ?? this.customerId,
      driverId: driverId ?? this.driverId,
      pickup: pickup ?? this.pickup,
      dropoff: dropoff ?? this.dropoff,
      stops: stops ?? this.stops, 
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'RideRequestModel(rideRequestId: $rideRequestId, customerId: $customerId, '
        'driverId: $driverId, pickup: $pickup, dropoff: $dropoff, stops: $stops, status: $status, '
        'timestamp: $timestamp)';
  }
}

class RideHistoryModel {
  final String? rideHistoryId;
  final String customerId;
  final String driverId;
  final LatLng pickup;
  final LatLng dropoff;
  final List<Map<String, dynamic>> stops;
  final double distance;
  final double cost;
  final DateTime timestamp;

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
      stops: (json['stops'] as List<dynamic>)
          .map((stop) => {
                'name': stop['name'],
                'address': stop['address'],
                'location': LatLng(
                  (stop['location']['latitude'] as num).toDouble(),
                  (stop['location']['longitude'] as num).toDouble(),
                ),
              })
          .toList(),
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
      'stops': stops
          .map((stop) => {
                'name': stop['name'],
                'address': stop['address'],
                'location': {
                  'latitude': stop['location'].latitude,
                  'longitude': stop['location'].longitude,
                },
              })
          .toList(),
      'distance': distance,
      'cost': cost,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  RideHistoryModel copyWith({
    String? rideHistoryId,
    String? customerId,
    String? driverId,
    LatLng? pickup,
    LatLng? dropoff,
    List<Map<String, dynamic>>? stops,
    double? distance,
    double? cost,
    DateTime? timestamp,
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
    );
  }

  @override
  String toString() {
    return 'RideHistoryModel(rideHistoryId: $rideHistoryId, customerId: $customerId, '
        'driverId: $driverId, pickup: $pickup, dropoff: $dropoff, stops: $stops, '
        'distance: $distance, cost: $cost, timestamp: $timestamp)';
  }
  
}