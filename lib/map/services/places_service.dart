import 'dart:convert';
import 'package:http/http.dart' as http;

class PlacesService {
  final String apiKey;

  PlacesService({required this.apiKey});

  Future<List<Map<String, dynamic>>> getSuggestions(String query) async {
    if (query.isEmpty) return [];
    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$apiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return (data['predictions'] as List)
              .map((p) => {
                    'place_id': p['place_id'],
                    'description': p['description'],
                  })
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching suggestions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$apiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['result'] != null && data['result']['geometry'] != null) {
          final geometry = data['result']['geometry']['location'];
          return {'latitude': geometry['lat'], 'longitude': geometry['lng']};
        }
      }
      return null;
    } catch (e) {
      print('Error fetching place details: $e');
      return null;
    }
  }
}