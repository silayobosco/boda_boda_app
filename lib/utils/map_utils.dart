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
              // Assuming single leg for simplicity, common for direct origin-destination.
              // If multiple legs (due to waypoints), this might need adjustment.
              final leg = route['legs'][0]; 

              // Create a unique Polyline for this specific route alternative
              final Polyline polyline = Polyline(
                polylineId: PolylineId('route_alt_$i'), // Unique ID for each alternative
                // Color and width will be set in CustomerHome based on selection
                points: routePoints,
              );

              allRouteDetails.add({
                'polyline': polyline, // Store the Polyline object itself
                'points': routePoints, // Also store points for bounds calculation
                'distance': leg['distance']['text'] as String?,
                'duration': leg['duration']['text'] as String?,
                'summary': route['summary'] as String? ?? '', // e.g., "US-101 S"
              });
            }
            return allRouteDetails;
          }

        } else {
          debugPrint('Directions API error: ${data['status']} - ${data['error_message']}');
        }
      } else {
        debugPrint('Failed to load route, status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching route details: $e');
    }
    return null;
  }
}