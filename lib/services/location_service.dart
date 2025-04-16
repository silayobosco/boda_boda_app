import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart'; // Import latlong2

class LocationService {
  Future<LatLng> getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      // Check for location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'Location permissions are permanently denied, we cannot request permissions.');
      }

      // Get the current position
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // Convert to LatLng
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print('Error getting location: $e');
      rethrow; // Rethrow the error for handling in the UI
    }
  }

  Stream<LatLng> getPositionStream() {
    return Geolocator.getPositionStream().map((Position position) => LatLng(position.latitude, position.longitude));
  }
}