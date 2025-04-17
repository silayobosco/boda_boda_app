import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  _CustomerHomeState createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> with AutomaticKeepAliveClientMixin {
  // Map and Location Variables
  GoogleMapController? _mapController;
  ll.LatLng? _pickupLocation;
  ll.LatLng? _dropOffLocation;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  
  // Search and Suggestions
  List<Map<String, dynamic>> _destinationSuggestions = [];
  List<Map<String, dynamic>> _pickupSuggestions = [];
  final String _googlePlacesApiKey = 'AIzaSyCkKD8FP-r9bqi5O-sOjtuksT-0Dr9dgeg';
  
  // UI State Variables
  bool _selectingPickup = false;
  bool _editingPickup = false;
  final FocusNode _destinationFocusNode = FocusNode();
  final FocusNode _pickupFocusNode = FocusNode();
  
  // Sheet Control
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _currentSheetSize = 0.35;
  bool _isSheetExpanded = false;
  
  // Stops Management
  final List<Stop> _stops = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializePickupLocation();
    _setupFocusListeners();
    _sheetController.addListener(_onSheetChanged);
  }

  void _setupFocusListeners() {
    _destinationFocusNode.addListener(() {
      if (_destinationFocusNode.hasFocus) {
        _expandSheet();
        Future.delayed(const Duration(milliseconds: 300), () {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    });
    _pickupFocusNode.addListener(() {
      if (_pickupFocusNode.hasFocus) {
        _expandSheet();
        Future.delayed(const Duration(milliseconds: 300), () {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    });
  }

  void _onSheetChanged() {
    setState(() {
      _currentSheetSize = _sheetController.size;
      _isSheetExpanded = _sheetController.size > 0.6;
    });
  }

  void _collapseSheet() {
    _sheetController.animateTo(0.35,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _expandSheet() {
    _sheetController.animateTo(0.9,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _initializePickupLocation() async {
    final currentLocation = Provider.of<LocationProvider>(context, listen: false).currentLocation;
    if (currentLocation != null) {
      _pickupLocation = currentLocation;
      _updateGooglePickupMarker(LatLng(currentLocation.latitude, currentLocation.longitude));
      await _reverseGeocode(_pickupLocation!, _pickupController);
    }
  }

  Future<void> _reverseGeocode(ll.LatLng location, TextEditingController controller) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final Placemark place = placemarks.first;
        controller.text = '${place.street}, ${place.locality}, ${place.administrativeArea}';
      }
    } catch (e) {
      print('Error reverse geocoding: $e');
    }
  }

  void _updateGooglePickupMarker(LatLng location) {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId == const MarkerId('pickup'));
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: location,
          infoWindow: const InfoWindow(title: 'Pickup'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    });
  }

  void _updateGoogleDropOffMarker(LatLng? location) {
    if (location != null) {
      setState(() {
        _markers.removeWhere((marker) => marker.markerId == const MarkerId('dropoff'));
        _markers.add(
          Marker(
            markerId: const MarkerId('dropoff'),
            position: location,
            infoWindow: const InfoWindow(title: 'Drop-off'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      });
    }
  }

  void _handleMapTap(LatLng tappedLatLng) {
    final llTappedLatLng = ll.LatLng(tappedLatLng.latitude, tappedLatLng.longitude);
    if (_selectingPickup) {
      setState(() {
        _pickupLocation = llTappedLatLng;
        _updateGooglePickupMarker(tappedLatLng);
        _reverseGeocode(_pickupLocation!, _pickupController);
        _selectingPickup = false;
      });
    } else if (_dropOffLocation == null) {
      setState(() {
        _dropOffLocation = llTappedLatLng;
        _updateGoogleDropOffMarker(tappedLatLng);
        _reverseGeocode(_dropOffLocation!, _destinationController);
        _drawRoute();
        _collapseSheet();
      });
    }
  }

  void _drawRoute() {
    if (_pickupLocation != null && _dropOffLocation != null) {
      setState(() {
        _polylines.clear();
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          color: Colors.blue,
          width: 4,
          points: [
            LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
            LatLng(_dropOffLocation!.latitude, _dropOffLocation!.longitude),
          ],
        ));
        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(
            _boundsFromLatLngList([
              LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
              LatLng(_dropOffLocation!.latitude, _dropOffLocation!.longitude),
            ]),
            100,
          ),
        );
      });
    }
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
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
    return LatLngBounds(
      northeast: LatLng(x1!, y1!),
      southwest: LatLng(x0!, y0!),
    );
  }

  Future<List<Map<String, dynamic>>> _getGooglePlacesSuggestions(String query) async {
    if (query.isEmpty) return [];
    final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return (data['predictions'] as List).map((p) => {
            'place_id': p['place_id'],
            'description': p['description'],
          }).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching suggestions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    final url = 'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final geometry = data['result']['geometry']['location'];
          return {
            'latitude': geometry['lat'],
            'longitude': geometry['lng'],
          };
        }
      }
      return null;
    } catch (e) {
      print('Error fetching place details: $e');
      return null;
    }
  }

  Future<void> _handleDestinationSelected(Map<String, dynamic> suggestion) async {
    final placeDetails = await _getPlaceDetails(suggestion['place_id']);
    if (placeDetails != null) {
      final latLng = ll.LatLng(placeDetails['latitude'], placeDetails['longitude']);
      setState(() {
        _dropOffLocation = latLng;
        _updateGoogleDropOffMarker(LatLng(latLng.latitude, latLng.longitude));
        _destinationController.text = suggestion['description'] ?? '';
        _destinationSuggestions = [];
      });
      await _reverseGeocode(_dropOffLocation!, _destinationController);
      _drawRoute();
      _collapseSheet();
    }
  }

  void _swapLocations() {
    final temp = _pickupController.text;
    final tempLoc = _pickupLocation;
    setState(() {
      _pickupController.text = _destinationController.text;
      _destinationController.text = temp;
      _pickupLocation = _dropOffLocation;
      _dropOffLocation = tempLoc;
      _drawRoute();
    });
  }

  void _addStop() {
    setState(() {
      _stops.add(Stop(
        name: 'Stop ${_stops.length + 1}',
        address: 'Address details',
      ));
    });
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locationProvider = Provider.of<LocationProvider>(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: locationProvider.currentLocation != null
                  ? LatLng(
                      locationProvider.currentLocation!.latitude,
                      locationProvider.currentLocation!.longitude,
                    )
                  : const LatLng(0, 0),
              zoom: 15,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _handleMapTap,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
          ),
          _buildRouteSheet(),
        ],
      ),
    );
  }

  Widget _buildRouteSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.35,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.35, 0.7, 0.9],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                blurRadius: 10,
                color: Colors.black12,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildDragHandle(),
                    _buildRouteHeader(),
                    _buildPickupField(),
                    _buildDestinationField(),
                  ],
                ),
              ),
              if (_isSheetExpanded) ...[
                if (_destinationSuggestions.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildSuggestionItem(_destinationSuggestions[index]),
                      childCount: _destinationSuggestions.length,
                    ),
                  ),
                SliverToBoxAdapter(child: _buildStopsList()),
                SliverToBoxAdapter(child: _buildAddStopButton()),
              ],
              SliverToBoxAdapter(child: _buildConfirmButton()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildRouteHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        'Your route',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildPickupField() {
    return _buildLocationField(
      controller: _pickupController,
      icon: Icons.my_location,
      label: 'Pickup',
      isFirst: true,
      isCompleted: false,
      onTap: () {
        _selectingPickup = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tap on map to select pickup location')),
        );
      },
    );
  }

  Widget _buildDestinationField() {
    return _buildLocationField(
      controller: _destinationController,
      icon: Icons.flag,
      label: 'Destination',
      isFirst: false,
      isCompleted: _dropOffLocation != null,
      onTap: _expandSheet,
    );
  }

  Widget _buildLocationField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required bool isFirst,
    required bool isCompleted,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: isCompleted ? Colors.white : Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: isFirst ? _pickupFocusNode : _destinationFocusNode,
                decoration: InputDecoration(
                  hintText: label,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) async {
                  if (value.isNotEmpty && !isFirst) {
                    final suggestions = await _getGooglePlacesSuggestions(value);
                    setState(() => _destinationSuggestions = suggestions);
                  }
                },
              ),
            ),
            if (!isFirst && _dropOffLocation != null)
              IconButton(
                icon: const Icon(Icons.swap_vert, size: 20),
                onPressed: _swapLocations,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionItem(Map<String, dynamic> suggestion) {
    return ListTile(
      leading: const Icon(Icons.location_on),
      title: Text(suggestion['description'] ?? ''),
      onTap: () => _handleDestinationSelected(suggestion),
    );
  }

  Widget _buildStopsList() {
    return Column(
      children: _stops.asMap().entries.map((entry) {
        final index = entry.key;
        final stop = entry.value;
        return Dismissible(
          key: Key('stop_$index'),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red[100],
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.red),
          ),
          onDismissed: (direction) => _removeStop(index),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (stop.address != null)
                        Text(
                          stop.address!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddStopButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextButton.icon(
        onPressed: _addStop,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add stop'),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: _dropOffLocation != null ? () {} : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'Confirm Route',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _destinationFocusNode.dispose();
    _pickupFocusNode.dispose();
    super.dispose();
  }
}

class Stop {
  final String name;
  final String? address;
  LatLng? location;
  final TextEditingController controller = TextEditingController();

  Stop({
    required this.name,
    this.address,
    this.location,
  });
}