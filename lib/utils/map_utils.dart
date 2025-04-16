import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math'; 

class MapUtils {
  // Convert GeoPoint to LatLng
  static LatLng geoPointToLatLng(GeoPoint geoPoint) {
    return LatLng(geoPoint.latitude, geoPoint.longitude);
  }

  // Convert address to LatLng
  static Future<LatLng?> addressToLatLng(String address) async {
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return LatLng(locations.first.latitude, locations.first.longitude);
      }
      return null;
    } catch (e) {
      print('Error converting address to LatLng: $e');
      return null;
    }
  }

  // Calculate distance between two LatLng points (basic)
  static double calculateDistance(LatLng point1, LatLng point2) {
    // Basic distance calculation (you can use a more accurate method)
    double lat1 = point1.latitude;
    double lon1 = point1.longitude;
    double lat2 = point2.latitude;
    double lon2 = point2.longitude;

    double p = 0.017453292519943295; // Math.PI / 180
    double a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R * asin(...), R = 6371 km
  }

  // Get route between two LatLng points (basic implementation)
  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    // Basic route implementation (replace with a proper routing service)
    return [start, end]; // Placeholder: replace with actual route data
  }
}