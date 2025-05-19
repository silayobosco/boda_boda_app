import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ApiService {
  static const String _baseUrl = 'https://your-api-domain.com/api/v1';
  final String _authToken;

  ApiService(this._authToken);

  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String endpoint,
    Map<String, dynamic>? body,
  ) async {
    final url = Uri.parse('$_baseUrl/$endpoint');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_authToken',
    };

    http.Response response;
    switch (method) {
      case 'POST':
        response = await http.post(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
        break;
      case 'PUT':
        response = await http.put(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
        break;
      case 'GET':
        response = await http.get(url, headers: headers);
        break;
      default:
        throw Exception('Unsupported HTTP method');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception('API request failed: ${response.statusCode}');
    }
  }

  // Driver Position Update
  Future<void> updateDriverPosition(LatLng position) async {
    await _makeRequest('PUT', 'driver/position', {
      'latitude': position.latitude,
      'longitude': position.longitude,
    });
  }

  // Driver Status Update
  Future<void> updateDriverStatus(bool isOnline) async {
    await _makeRequest('PUT', 'driver/status', {'isOnline': isOnline});
  }

  // Ride Management
  Future<Map<String, dynamic>> acceptRide(String rideId) async {
    return await _makeRequest('POST', 'rides/$rideId/accept', null);
  }

  Future<void> declineRide(String rideId) async {
    await _makeRequest('POST', 'rides/$rideId/decline', null);
  }

  Future<void> confirmArrival(String rideId) async {
    await _makeRequest('POST', 'rides/$rideId/arrived', null);
  }

  Future<void> startRide(String rideId) async {
    await _makeRequest('POST', 'rides/$rideId/start', null);
  }

  Future<void> completeRide(String rideId) async {
    await _makeRequest('POST', 'rides/$rideId/complete', null);
  }

  Future<void> cancelRide(String rideId) async {
    await _makeRequest('POST', 'rides/$rideId/cancel', null);
  }

  // Get current ride details
  Future<Map<String, dynamic>> getCurrentRide() async {
    return await _makeRequest('GET', 'driver/current-ride', null);
  }
  // cloud messaging
}