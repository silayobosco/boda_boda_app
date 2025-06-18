import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapUtils {
  // Decode the polyline from the Directions API
  static List<LatLng> decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;
      shift = 0; result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;
      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  // Calculate bounds from a list of LatLng
  static LatLngBounds boundsFromLatLngList(List<LatLng> list) {
    assert(list.isNotEmpty);
    double? x0, x1, y0, y1;
    for (LatLng latLng in list) {
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
    }
    return LatLngBounds(northeast: LatLng(x1!, y1!), southwest: LatLng(x0!, y0!));
  }

  // Fetches and draws a route between an origin and destination
  // Returns a map containing polylines, distance, and duration, or null on error.
  static Future<List<Map<String, dynamic>>?> getRouteDetails({
    required LatLng origin,
    required LatLng destination,
    required String apiKey,
    List<LatLng>? waypoints, // Optional waypoints
  }) async {
    final originStr = '${origin.latitude},${origin.longitude}';
    final destinationStr = '${destination.latitude},${destination.longitude}';
    String waypointsStr = '';
    if (waypoints != null && waypoints.isNotEmpty) {
      waypointsStr = waypoints.map((p) => '${p.latitude},${p.longitude}').join('|');
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?'
      'origin=$originStr&destination=$destinationStr'
      '${waypointsStr.isNotEmpty ? '&waypoints=$waypointsStr' : ''}'
      '&key=$apiKey&alternatives=true', // Request alternative routes
    );

    try {
      debugPrint('Requesting route from: $url'); // Add this line
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['routes'] != null) {
          final List<dynamic> routesData = data['routes'] as List<dynamic>;
          if (routesData.isNotEmpty) {
            List<Map<String, dynamic>> allRouteDetails = [];

            for (int i = 0; i < routesData.length; i++) {
              final route = routesData[i];
              final routePoints = decodePolyline(route['overview_polyline']['points'] as String);
              
              // Extract all legs for this route alternative
              final List<dynamic> legsData = route['legs'] as List<dynamic>;
              //final leg = legsData.isNotEmpty ? legsData[0] : null; // Still get the first leg for overall summary

              num totalDistanceValue = 0; // in meters
              num totalDurationValue = 0; // in seconds

              for (var legItem in legsData) {
                if (legItem is Map<String, dynamic>) {
                  if (legItem['distance'] is Map<String, dynamic> && legItem['distance']['value'] is num) {
                    totalDistanceValue += legItem['distance']['value'] as num;
                  }
                  if (legItem['duration'] is Map<String, dynamic> && legItem['duration']['value'] is num) {
                    totalDurationValue += legItem['duration']['value'] as num;
                  }
                }
              }

              // Format total distance and duration
              final String formattedTotalDistance = _formatDistance(totalDistanceValue.toDouble());
              final String formattedTotalDuration = _formatDuration(totalDurationValue.toInt());

              // Create a unique Polyline for this specific route alternative
              final Polyline polyline = Polyline(
                polylineId: PolylineId('route_alt_$i'), // Unique ID for each alternative
                // Color and width will be set in CustomerHome based on selection
                points: routePoints,
              );

              allRouteDetails.add({
                'polyline': polyline, // Store the Polyline object itself
                'points': routePoints, // Also store points for bounds calculation
                'distance': formattedTotalDistance, // Use formatted total distance
                'duration': formattedTotalDuration, // Use formatted total duration
                'summary': route['summary'] as String? ?? '', // e.g., "US-101 S"
                'legs': legsData, // Include the full legs array
              });
            }
            return allRouteDetails;
          }
        }
      }
      return null; // Return null if no routes or error
    } catch (e) {
      debugPrint('Error getting route details from Google: $e');
      return null;
    }
  }

  // Helper function to format distance (meters to km or m string)
  static String _formatDistance(double distanceInMeters) {
    if (distanceInMeters >= 1000) {
      double distanceInKm = distanceInMeters / 1000;
      return '${distanceInKm.toStringAsFixed(1)} km'; // e.g., "2.3 km"
    } else {
      return '${distanceInMeters.toStringAsFixed(0)} m'; // e.g., "500 m"
    }
  }

  // Helper function to format duration (seconds to hr/min string)
  static String _formatDuration(int durationInSeconds) {
    final Duration duration = Duration(seconds: durationInSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    // String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60)); // Usually not needed for display

    if (duration.inHours > 0) {
      return "${duration.inHours} hr $twoDigitMinutes min";
    } else {
      return "$twoDigitMinutes min";
    } 
  }

  // Helper to find the index of the closest point in a list of LatLngs to a given point
  // This is a simple implementation; more sophisticated ones exist (e.g., using perpendicular distance to segments)
  static int findClosestPointIndex(LatLng point, List<LatLng> pathPoints) {
    if (pathPoints.isEmpty) return -1;

    double minDistanceSq = -1;
    int closestIndex = -1;

    for (int i = 0; i < pathPoints.length; i++) {
      final pathPoint = pathPoints[i];
      final double dLat = pathPoint.latitude - point.latitude;
      final double dLng = pathPoint.longitude - point.longitude;
      final double distanceSq = dLat * dLat + dLng * dLng; // Using squared distance for comparison efficiency

      if (closestIndex == -1 || distanceSq < minDistanceSq) {
        minDistanceSq = distanceSq;
        closestIndex = i;
      }
    }
    return closestIndex;
  }
}