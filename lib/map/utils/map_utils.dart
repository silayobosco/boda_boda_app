import 'package:google_maps_flutter/google_maps_flutter.dart';

List<LatLng> decodePolyline(String encoded) {
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

    shift = 0;
    result = 0;
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

LatLngBounds boundsFromLatLngList(List<LatLng> list) {
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

// Helper to find the index of the closest point in a list of LatLngs to a given point
// This is a simple implementation; more sophisticated ones exist (e.g., using perpendicular distance to segments)
int findClosestPointIndex(LatLng point, List<LatLng> pathPoints) {
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