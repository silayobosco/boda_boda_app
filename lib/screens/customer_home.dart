import 'dart:async';
import 'package:boda_boda/providers/ride_request_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import '../providers/location_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/stop.dart';
import '../utils/ui_utils.dart';
import '../utils/map_utils.dart';
import '../services/firestore_service.dart';
import 'chat_screen.dart';
import 'kijiwe_profile_screen.dart';
import 'scheduled_rides_list_widget.dart';
import 'rides_screen.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import '../viewmodels/customer_home_viewmodel.dart';

class CustomerHome extends StatelessWidget {
  const CustomerHome({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CustomerHomeViewModel(
        rideRequestProvider: Provider.of<RideRequestProvider>(context, listen: false),
        firestoreService: Provider.of<FirestoreService>(context, listen: false),
        locationProvider: Provider.of<LocationProvider>(context, listen: false),
        context: context,
      ),
      child: const CustomerHomeView(),
    );
  }
}

class CustomerHomeView extends StatefulWidget {
  const CustomerHomeView({super.key});

  @override
  _CustomerHomeViewState createState() => _CustomerHomeViewState();
}

class _CustomerHomeViewState extends State<CustomerHomeView> with AutomaticKeepAliveClientMixin {
  // Map and Location Variables
  GoogleMapController? _mapController;

  // UI State Variables
  final FocusNode _destinationFocusNode = FocusNode();
  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _stopFocusNode = FocusNode();
  
  // Sheet Control
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _currentSheetSize = 0.35;
  bool _isSheetExpanded = false;

  late final CustomerHomeViewModel _viewModel;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _viewModel = Provider.of<CustomerHomeViewModel>(context, listen: false);
    _viewModel.onUiAction = _handleUiAction;

    _setupFocusListeners();
    _sheetController.addListener(_onSheetChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewModel.setupInitialMapState().then((_) {
        _adjustMapForExpandedSheet();
      });
    });
  }

  void _handleUiAction(UiAction action) {
    if (!mounted) return;

    if (action.message.startsWith('kijiwe_tap:')) {
      final parts = action.message.split(':');
      final kijiweId = parts[1];
      final kijiweName = parts[2];
      final lat = double.parse(parts[3]);
      final lng = double.parse(parts[4]);
      _showKijiweOptionsDialog(kijiweName, LatLng(lat, lng), kijiweId);
    } else if (action.message.startsWith('unfocus:')) {
      final field = action.message.split(':')[1];
      if (field == 'pickup') _pickupFocusNode.unfocus();
      if (field == 'destination') _destinationFocusNode.unfocus();
      if (field == 'stop') _stopFocusNode.unfocus();
      _collapseSheet();
    } else if (action.message.startsWith('show_rate_dialog:')) {
      final parts = action.message.split(':');
      _showRateDriverDialog(parts[1], parts[2]);
    } else if (action.message == 'show_post_schedule_dialog') {
      _showPostSchedulingDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action.message),
          backgroundColor: action.isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
    }
  }

  void _showKijiweOptionsDialog(String kijiweName, LatLng kijiweLocation, String kijiweId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(kijiweName),
          content: Text(AppLocale.kijiweOptions.getString(context)),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocale.viewKijiweProfile.getString(context)),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => KijiweProfileScreen(kijiweId: kijiweId),
                  ),
                );
              },
            ),
            TextButton(
              child: Text(AppLocale.setAsPickup.getString(context)),
              onPressed: () {
                Navigator.of(context).pop();
                _viewModel.setKijiweAsLocation(kijiweName, kijiweLocation, isPickup: true);
              },
            ),
            TextButton(
              child: Text(AppLocale.setAsDropoff.getString(context)),
              onPressed: () {
                Navigator.of(context).pop();
                _viewModel.setKijiweAsLocation(kijiweName, kijiweLocation, isPickup: false);
              },
            ),
          ],
        );
      },
    );
  }

  void _startEditing(String field) {
    _viewModel.startEditing(field);
    if (field == 'pickup') _pickupFocusNode.requestFocus();
    if (field == 'destination') _destinationFocusNode.requestFocus();
    if (field.startsWith('stop_')) _stopFocusNode.requestFocus();
    _expandSheet();
  }

  LatLngBounds _getVisibleMapArea() {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetTop = screenHeight * (1 - _currentSheetSize);
    final visibleHeightRatio = sheetTop / screenHeight;
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

    final points = <LatLng>[
      if (_viewModel.pickupLocation != null) LatLng(_viewModel.pickupLocation!.latitude, _viewModel.pickupLocation!.longitude),
      if (_viewModel.dropOffLocation != null) LatLng(_viewModel.dropOffLocation!.latitude, _viewModel.dropOffLocation!.longitude),
      ..._viewModel.stops.where((s) => s.location != null).map((s) => LatLng(s.location!.latitude, s.location!.longitude)),
    ];

    if (points.isEmpty) {
      return LatLngBounds(
        northeast: LatLng(locationProvider.currentLocation?.latitude ?? 0, locationProvider.currentLocation?.longitude ?? 0),
        southwest: LatLng(locationProvider.currentLocation?.latitude ?? 0, locationProvider.currentLocation?.longitude ?? 0),
      );
    }

    final bounds = MapUtils.boundsFromLatLngList(points);
    final latDelta = bounds.northeast.latitude - bounds.southwest.latitude;
    final lngDelta = bounds.northeast.longitude - bounds.southwest.longitude;

    return LatLngBounds(
      northeast: LatLng(bounds.northeast.latitude + (latDelta * 0.2), bounds.northeast.longitude + (lngDelta * 0.2)),
      southwest: LatLng(bounds.southwest.latitude - (latDelta * 0.2 * (1 - visibleHeightRatio)), bounds.southwest.longitude - (lngDelta * 0.2)),
    );
  }

  void _setupFocusListeners() {
    _destinationFocusNode.addListener(() { if (_destinationFocusNode.hasFocus) _startEditing('destination'); });
    _pickupFocusNode.addListener(() { if (_pickupFocusNode.hasFocus) _startEditing('pickup'); });
    _stopFocusNode.addListener(() { if (_stopFocusNode.hasFocus && _viewModel.editingStopIndex != null) _expandSheet(); });
  }

  void _adjustMapForExpandedSheet() {
    if (_mapController != null) {
      final bounds = _getVisibleMapArea();
      final padding = 50.0 + (100 * _currentSheetSize);
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
    }
  }

  void _onSheetChanged() {
    if (!mounted) return;
    setState(() {
      _currentSheetSize = _sheetController.size;
      _isSheetExpanded = _sheetController.size > 0.6;
    });
    _adjustMapForExpandedSheet();
  }

  void _collapseSheet() {
    _sheetController.animateTo(0.23, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  void _expandSheet() {
    _sheetController.animateTo(0.9, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _showAddNoteDialog(String rideId, String? currentNote) async {
    final noteController = TextEditingController(text: currentNote);

    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog( // The AlertDialog itself
        title: Text(AppLocale.addNote.getString(context)),
        content: TextField(
          controller: noteController,
          decoration: appInputDecoration(hintText: AppLocale.addNoteHint.getString(context)),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocale.cancel.getString(context))),
          ElevatedButton(onPressed: () async {
            Navigator.pop(dialogContext);
            await _viewModel.updateCustomerNote(rideId, noteController.text.trim());
          }, child:  Text(AppLocale.save.getString(context))),
        ],
      ),
    );
  }

  Future<void> _scheduleRide(
    BuildContext context
    ) async {
  final dropOffAddress = _viewModel.destinationController.text;
  final TextEditingController titleController = TextEditingController(
    text: AppLocale.scheduledRideTo.getString(context).replaceFirst('{destination}', dropOffAddress.isNotEmpty ? dropOffAddress : AppLocale.destination.getString(context))
  );
  DateTime? selectedDate = DateTime.now(); // Default to today
  TimeOfDay? selectedTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))); // Default to one hour from now
  // Recurrence state variables
  bool _isRecurring = false;
  String _recurrenceType = 'None'; // 'None', 'Daily', 'Weekly'
  List<bool> _selectedRecurrenceDays = List.filled(7, false); // For weekly: Mon, Tue, Wed, Thu, Fri, Sat, Sun
  DateTime? _recurrenceEndDate;
  final List<String> _dayAbbreviations = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final maxDays = _viewModel.maxSchedulingDaysAhead;
  final minMinutes = _viewModel.minSchedulingMinutesAhead;

  final theme = Theme.of(context); // Get theme for styling
 
   await showDialog(
      context: context,
      builder: (dialogContext) { // Renamed context to avoid conflict
        return StatefulBuilder( // Use StatefulBuilder to update dialog content
          builder: (stfContext, stfSetState) {
            return AlertDialog( // The AlertDialog itself
              title: Text(AppLocale.scheduleNewRide.getString(context)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: appInputDecoration(
                      labelText: AppLocale.title.getString(context),
                      hintText: AppLocale.rideTitleHint.getString(context),
                    ),
                  ),
                  verticalSpaceMedium,
                  Text(AppLocale.choseDateAndTime.getString(context), style: theme.textTheme.titleSmall),
                  verticalSpaceSmall,
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.calendar_today), // The Icon
                          label: Text(selectedDate != null ? "${selectedDate!.toLocal()}".split(' ')[0] : AppLocale.pickDate.getString(context)),
                          onPressed: () async {
                            final now = DateTime.now();
                            final DateTime? pickedDate = await showDatePicker(
                              context: stfContext, // Use StatefulBuilder context
                              initialDate: selectedDate ?? now,
                              firstDate: now,
                              lastDate: now.add(Duration(days: maxDays)),
                            );
                            if (pickedDate != null) {
                              stfSetState(() {
                                selectedDate = pickedDate;
                                // If date changed to today, ensure time is valid
                                if (selectedDate!.isAtSameMomentAs(DateTime(now.year, now.month, now.day))) {
                                  final minTimeToday = now.add(Duration(minutes: minMinutes));
                                  if (selectedTime != null) { // This seems to have a typo, should be minMinutes
                                    final currentSelectedDateTime = DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day, selectedTime!.hour, selectedTime!.minute);
                                    if (currentSelectedDateTime.isBefore(minTimeToday)) {
                                      selectedTime = TimeOfDay.fromDateTime(minTimeToday);
                                    }
                                  } else {
                                    selectedTime = TimeOfDay.fromDateTime(minTimeToday);
                                  }
                                }
                              });
                            }
                          },
                        ),
                      ),
                      horizontalSpaceSmall,
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.access_time), // The Icon
                          label: Text(selectedTime != null ? selectedTime!.format(stfContext) : AppLocale.pickTime.getString(context)),
                          onPressed: () async {
                            final now = DateTime.now();
                            TimeOfDay initialTime = selectedTime ?? TimeOfDay.fromDateTime(now.add(Duration(minutes: minMinutes + 5))); // Default with a small buffer

                            if (selectedDate != null && selectedDate!.year == now.year && selectedDate!.month == now.month && selectedDate!.day == now.day) {
                              final minTimeToday = now.add(Duration(minutes: minMinutes));
                              if (initialTime.hour < minTimeToday.hour || (initialTime.hour == minTimeToday.hour && initialTime.minute < minTimeToday.minute)) {
                                initialTime = TimeOfDay.fromDateTime(minTimeToday);
                              }
                            }

                            final TimeOfDay? pickedTime = await showTimePicker(
                              context: stfContext, // Use StatefulBuilder context
                              initialTime: initialTime,
                            );
                            if (pickedTime != null) {
                              stfSetState(() => selectedTime = pickedTime);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  verticalSpaceMedium,
                  // --- Recurrence Section ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppLocale.repeatThisRide.getString(context), style: theme.textTheme.titleSmall),
                      Switch(
                        value: _isRecurring,
                        onChanged: (value) {
                          stfSetState(() {
                            _isRecurring = value;
                            if (!_isRecurring) {
                              _recurrenceType = 'None';
                              _selectedRecurrenceDays = List.filled(7, false);
                              _recurrenceEndDate = null;
                            } else {
                              _recurrenceType = 'Daily'; // Default to Daily when enabled
                              _recurrenceEndDate = selectedDate?.add(const Duration(days: 30)); // Default end date
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (_isRecurring) ...[
                    verticalSpaceSmall,
                    DropdownButtonFormField<String>(
                      value: _recurrenceType,
                      decoration: appInputDecoration(labelText: AppLocale.frequency.getString(context)),
                      items: ['Daily', 'Weekly']
                          .map((label) => DropdownMenuItem(
                                value: label,
                                child: Text(label == 'Daily' ? AppLocale.daily.getString(context) : AppLocale.weekly.getString(context)),
                              ))
                          .toList(),
                      onChanged: (value) {
                       stfSetState(() {
                          _recurrenceType = value ?? 'Daily';
                          if (_recurrenceType != AppLocale.weekly.getString(context)) {
                            _selectedRecurrenceDays = List.filled(7, false);
                          }
                        });
                      },
                    ),
                    if (_recurrenceType == AppLocale.weekly.getString(context)) ...[
                      verticalSpaceSmall,
                      Text(AppLocale.repeatOn.getString(context), style: theme.textTheme.bodyMedium),
                      Wrap( // Using Wrap for days of the week
                        spacing: 6.0,
                        runSpacing: 0.0,
                        children: List<Widget>.generate(7, (index) {
                          return FilterChip(
                            label: Text(_dayAbbreviations[index]),
                            selected: _selectedRecurrenceDays[index],
                            onSelected: (bool selected) {
                              stfSetState(() {
                                _selectedRecurrenceDays[index] = selected;
                              });
                            },
                          );
                        }),
                      ),
                    ],
                    verticalSpaceSmall,
                    ElevatedButton.icon(
                      icon: const Icon(Icons.calendar_today), // The Icon
                      label: Text(_recurrenceEndDate != null ? "Repeat until: ${_recurrenceEndDate!.toLocal()}".split(' ')[0] : 'Set End Date'),
                      onPressed: () async {
                        final DateTime? pickedEndDate = await showDatePicker(
                          context: stfContext,
                          initialDate: _recurrenceEndDate ?? selectedDate!.add(const Duration(days: 30)),
                          firstDate: selectedDate!.add(const Duration(days: 1)), // End date must be after selectedDate
                          lastDate: DateTime.now().add(const Duration(days: 365 * 2)), // Max 2 years for recurrence
                        );
                        if (pickedEndDate != null) stfSetState(() => _recurrenceEndDate = pickedEndDate);
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(AppLocale.cancel.getString(context)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.isNotEmpty && selectedDate != null && selectedTime != null) {
                      final DateTime scheduledDateTime = DateTime(
                        selectedDate!.year, selectedDate!.month, selectedDate!.day,
                        selectedTime!.hour, selectedTime!.minute,
                      );
                      final DateTime now = DateTime.now();
                      final DateTime minValidDateTime = now.add(Duration(minutes: minMinutes));

                      if (_isRecurring && _recurrenceType == AppLocale.weekly.getString(context) && !_selectedRecurrenceDays.contains(true)) {
                        ScaffoldMessenger.of(stfContext).showSnackBar(
                          SnackBar(content: Text(AppLocale.pleaseSelectAtleastOneDayForWeeklyRecurrence.getString(context))),
                        );
                        return;
                      }
                      if (_isRecurring && _recurrenceEndDate == null) {
                        ScaffoldMessenger.of(stfContext).showSnackBar(
                          SnackBar(content: Text(AppLocale.pleaseSetAnEndDateForTheRecurringRide.getString(context))),
                        );
                        return;
                      }

                      if (scheduledDateTime.isBefore(minValidDateTime)) {
                        ScaffoldMessenger.of(stfContext).showSnackBar(
                          SnackBar(content: Text(AppLocale.scheduledTimeMustBeAtleast.getString(context).replaceFirst('{minutes}', minMinutes.toString()))),
                        );
                        return;
                      }
                      Navigator.of(dialogContext).pop(true); // Return true for save
                    } else {
                      ScaffoldMessenger.of(stfContext).showSnackBar(
                         SnackBar(content: Text(AppLocale.pleaseProvideATitleDateAndTime.getString(context))),
                      );
                    }
                  },
                  child: Text(AppLocale.save.getString(context)),
                ),
              ],
            );
          },
        );
      },
    ).then((saved) async { // Handle the result of the dialog
  if (saved == true && titleController.text.isNotEmpty && selectedDate != null && selectedTime != null) {
    final DateTime scheduledDateTime = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedTime!.hour,
      selectedTime!.minute,
    );

    await _viewModel.saveScheduledRide(
      title: titleController.text,
      scheduledDateTime: scheduledDateTime,
      isRecurring: _isRecurring,
      recurrenceType: _recurrenceType,
      selectedRecurrenceDays: _selectedRecurrenceDays,
      recurrenceEndDate: _recurrenceEndDate,
      dayAbbreviations: _dayAbbreviations,
    );
  }});
}
  void _showPostSchedulingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must choose an option
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(AppLocale.rideScheduled.getString(context)),
          content: Text(AppLocale.whatWouldYouLikeToDoNext.getString(context)),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocale.planAnotherRide.getString(context)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _viewModel.resetUIForNewTrip();
              },
            ),
            TextButton(
              child: Text(AppLocale.viewScheduledRides.getString(context)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ScheduledRidesListWidget()),
                );
                _viewModel.resetUIForNewTrip(); // Also clear form after navigating
              },
            ),
            TextButton(
              child: Text(AppLocale.continueEditing.getString(context)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // Do nothing, user stays on the current screen with the route
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocationField({
    required Key key, // Add key
    required TextEditingController controller,
    String? legDistance, // New parameter for leg-specific distance
    String? legDuration, // New parameter for leg-specific duration
    required String labelText,
    required String hintText,
    required IconData iconData,
    required Color iconColor,
    required bool isEditing,
    required FocusNode focusNode,
    required VoidCallback onTapWhenNotEditing, // For InkWell
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
    required VoidCallback onMapIconTap,
  }) {
    final theme = Theme.of(context);
    List<String> labelParts = [labelText];
    if (legDuration != null && legDistance != null && legDuration.isNotEmpty && legDistance.isNotEmpty) {
      labelParts.add('($legDuration · $legDistance)');
    }
    final String displayLabel = labelParts.join(' ');

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(displayLabel, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary.withOpacity(0.8))),
        verticalSpaceSmall,
        if (isEditing)
          TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: appInputDecoration( // Using appInputDecoration
                hintText: hintText,
                prefixIcon: Icon(iconData, color: iconColor),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.text.isNotEmpty) IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: onClear),
                    IconButton(icon: const Icon(Icons.map_outlined, size: 20), onPressed: onMapIconTap),
                  ],
                )),
            onChanged: onChanged,
            onTap: _expandSheet, // Expand sheet when text field is tapped
            onSubmitted: (_) => _collapseSheet(), // Collapse sheet on submit
          )
        else
          InkWell(onTap: onTapWhenNotEditing, child: _buildFieldContainer(Row(children: [Icon(iconData, color: iconColor), horizontalSpaceMedium, Expanded(child: controller.text.isEmpty ? Text(hintText, style: appTextStyle(color: theme.hintColor)) : Text(controller.text, style: theme.textTheme.bodyLarge))]))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final viewModel = Provider.of<CustomerHomeViewModel>(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          if (locationProvider.currentLocation == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  verticalSpaceMedium,
                  Text(AppLocale.fetchingLocation.getString(context)),
                ],
              ),
            )
          else
            GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  locationProvider.currentLocation!.latitude,
                  locationProvider.currentLocation!.longitude,
                ),
                zoom: 15, // Start with a more zoomed-in view
              ),
              onMapCreated: (controller) {
                _viewModel.mapController = controller;
                _mapController = controller; // Keep local reference for UI-only actions
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _adjustMapForExpandedSheet();
                });
              },
              onTap: viewModel.handleMapTap,
              markers: viewModel.markers,
              polylines: viewModel.polylines,
              zoomControlsEnabled: false,
              myLocationEnabled: true,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).size.height * _currentSheetSize,
              ),
            ),
          // The DraggableScrollableSheet is now built directly, using the viewModel state
          // which is updated by the logic within the ViewModel.
          _buildRouteSheet(key: const ValueKey('main_sheet'), viewModel: viewModel),

      // Custom Map Controls (Recenter and Zoom) - only show when not in an active ride
      if (viewModel.activeRideRequestDetails == null)
          Positioned(
            bottom: MediaQuery.of(context).size.height * _currentSheetSize + 20, // Position above the sheet
            right: 16,
            child: Column(
              children: [
                // Recenter Button
                FloatingActionButton.small(
                  heroTag: 'customer_recenter_button',
                  onPressed: viewModel.centerMapOnCurrentLocation,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 16),
                // Zoom Buttons
                FloatingActionButton.small(
                  heroTag: 'customer_zoom_in_button', // Unique heroTag
                  onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 2),
                FloatingActionButton.small(
                  heroTag: 'customer_zoom_out_button', // Unique heroTag
                  onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldContainer(Widget child) {
    return Container(
      height: 56, // Fixed height for all fields
      decoration: BoxDecoration(
        // Use theme color for background
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12), // Use horizontalSpaceMedium?
      child: child,
    );
  }

  Widget _buildRouteSheet({Key? key, required CustomerHomeViewModel viewModel}) {
    // If a driver is assigned, show driver info and ride progress
    final rideDetails = viewModel.activeRideRequestDetails;
    if (rideDetails != null) {
      final status = rideDetails.status;
      final driverId = rideDetails.driverId;

      // Active ride with an assigned driver
      if (driverId != null && ['pending_driver_acceptance', 'accepted', 'goingToPickup', 'arrivedAtPickup', 'onRide'].contains(status)) {
        debugPrint("CustomerHome: _buildRouteSheet -> Showing DriverAssignedSheet. Status: $status");
        return _buildDriverAssignedSheet(viewModel);
      }

      // Ride was declined or no drivers found
      if (status == 'declined_by_driver' || status == 'no_drivers_available') {
        debugPrint("CustomerHome: _buildRouteSheet -> Showing RideFailedSheet. Status: $status");
        return _buildRideFailedSheet(viewModel, status);
      }

      // Still finding a driver
      if (viewModel.isFindingDriver || status == 'pending_match' || status == 'pending_driver_acceptance') {
        debugPrint("CustomerHome: _buildRouteSheet -> Showing FindingDriverSheet. Status: $status");
        return _buildFindingDriverSheet(viewModel);
      }
    } else if (viewModel.isFindingDriver) { // Handle case where rideDetails is momentarily null but we are finding
      return _buildFindingDriverSheet(viewModel);
    }
    // Default: Show route planning sheet
    debugPrint("CustomerHome: _buildRouteSheet -> Showing default route planning sheet. Estimated Fare: ${viewModel.estimatedFare}");
    final bool showActionButtons = viewModel.pickupLocation != null && viewModel.dropOffLocation != null && !viewModel.isFindingDriver && viewModel.activeRideRequestId == null;
     // Revert to static sheet sizes
    const double initialSheetSize = 0.55;
    const List<double> snapSizes = [0.23, 0.35, 0.45, 0.55, 0.7, 0.8, 0.9]; // Added 0.23 as a snap point
    const double minSheetSize = 0.2;
 
    return DraggableScrollableSheet( // This is the route planning sheet
      key: key, // Apply the key here
      controller: _sheetController,
      initialChildSize: initialSheetSize, // Use the static initial size
      minChildSize: minSheetSize,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: snapSizes, // Use the dynamic snapSizes variable
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            // Use theme color for sheet background
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                blurRadius: 10, // Consider adjusting shadow based on theme
                color: Colors.black12,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      // Use theme color for handle
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              
              // Main Scrollable Content
              Expanded(
                child: CustomScrollView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title (Your Route)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Use spacing constants?
                            child: Row(
                              children: [
                                Text(
                                  AppLocale.yourRoute.getString(context),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),                                const Spacer(),
                                // Swap button (only show if both pickup and destination are set)
                                if (viewModel.pickupLocation != null && viewModel.dropOffLocation != null)
                                  IconButton( // The IconButton
                                    icon: const Icon(Icons.swap_vert, size: 24), // The Icon
                                    tooltip: AppLocale.swapLocations.getString(context),
                                    onPressed: viewModel.swapLocations,
                                  ),
                                // Add Stop button (only show if pickup and destination are set)
                                if (viewModel.pickupLocation != null && viewModel.dropOffLocation != null) 
                                  IconButton(
                                    icon: const Icon(Icons.add_location_alt_outlined),
                                    tooltip: AppLocale.addStop.getString(context),
                                    onPressed: viewModel.addStop,
                                  ),
                                // Expand/Collapse toggle
                                IconButton(
                                  icon: Icon(_isSheetExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up), // The Icon
                                  tooltip: _isSheetExpanded ? AppLocale.collapseSheet.getString(context) : AppLocale.expandSheet.getString(context),
                                  onPressed: () {
                                    if (_isSheetExpanded) {
                                      _collapseSheet();
                                    } else {
                                      _expandSheet();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          
                          // Route Info (Distance and Duration)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), // Use spacing constants?
                            child: Row(
                              children: [
                                Icon(Icons.access_time, size: 20, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7)),
                                horizontalSpaceSmall,
                                Expanded( // Allow text to take available space
                                  child: Text(
                                    viewModel.selectedRouteDistance != null && viewModel.selectedRouteDuration != null
                                        ? '${viewModel.selectedRouteDuration} · ${viewModel.selectedRouteDistance}' // This is correct
                                        : AppLocale.calculatingRoute.getString(context), // Placeholder if distance/duration not ready
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    overflow: TextOverflow.ellipsis, // Handle long text
                                  ),
                                ),
                                horizontalSpaceMedium, // Space before fare
                                  // Display Fare: Preferring final fare from active ride, then estimated fare, then a "calculating" message.
                                  StreamBuilder<DocumentSnapshot>(
                                    stream: viewModel.activeRideRequestId != null ? FirebaseFirestore.instance.collection('rideRequests').doc(viewModel.activeRideRequestId).snapshots() : null,
                                    builder: (context, snapshot) {
                                      // 1. Check for and display the final fare if available.
                                      if (snapshot.hasData && snapshot.data!.exists) {
                                        final rideData = snapshot.data!.data() as Map<String, dynamic>?;
                                        final fare = rideData?['fare'] as num?;
                                        if (fare != null) {
                                          return Text('${AppLocale.final_fare.getString(context)}: TZS ${fare.toStringAsFixed(0)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary));
                                        }
                                  }

                                      // 2. If no final fare, fall back to showing the estimated fare.
                                      final currentFare = viewModel.estimatedFare;
                                      if (currentFare != null && viewModel.selectedRouteDistance != null && viewModel.selectedRouteDuration != null) {
                                        return Text(
                                          '${AppLocale.fare.getString(context)}: TZS ${currentFare.toStringAsFixed(0)}',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                        );
                                      } else if (viewModel.selectedRouteDistance != null && viewModel.selectedRouteDuration != null) {
                                        return Text(
                                          '${AppLocale.fare.getString(context)}: ${AppLocale.calculatingFare.getString(context)}',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
                                        );
                                      }
                                    return const SizedBox.shrink(); // Show nothing if no active ride and no estimated fare.
                                    },
                                  ),
                                ],
                              ),
                            ),
                          
                          // Pickup Field (conditionally shown)
                          // Show if pickup is not set (needs input) OR if action buttons are visible (for review/edit)
                          if (viewModel.pickupLocation == null || showActionButtons)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
                              child: Row( // Wrap _buildLocationField and Add Stop button in a Row
                                children: [
                                  Expanded(
                                    child: _buildLocationField(
                                      key: const ValueKey('pickup_field'),
                                      controller: viewModel.pickupController, // This is correct
                                      labelText: AppLocale.pickup.getString(context),
                                      hintText: AppLocale.enterPickupLocation.getString(context),
                                      iconData: Icons.my_location,
                                      iconColor: successColor,
                                      isEditing: viewModel.editingPickup,
                                      focusNode: _pickupFocusNode,
                                      onTapWhenNotEditing: () => _startEditing('pickup'),
                                      onChanged: (value) => viewModel.getGooglePlacesSuggestions(value, 'pickup'),
                                      onClear: viewModel.clearPickup,
                                      onMapIconTap: () { viewModel.selectingPickup = true; viewModel.editingPickup = true; _collapseSheet(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocale.tapToSelectPickup.getString(context)))); },
                                    ),
                                  ),
                                // X button to clear pickup
                                IconButton(
                                  icon: const Icon(Icons.clear), // The Icon
                                  tooltip: AppLocale.clearPickup.getString(context),
                                  onPressed: () {
                                      viewModel.clearPickup();
                                      viewModel.editingPickup = true;
                                      _pickupFocusNode.requestFocus();
                                    },
                                  ),                                
                                ],
                              ),
                            ),
                          if (viewModel.editingPickup) // Suggestions list for pickup
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16), 
                              child: Column(
                                children: _buildSuggestionList(viewModel.pickupSuggestions, true, null),
                              ),
                            ),
                          
                          // Stops Section with + button for each stop
                          if (viewModel.stops.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), 
                              child: Column(
                                children: viewModel.stops.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final stop = entry.value;
                                  return _buildStopItem(index, stop); // _buildStopItem will now use _buildLocationField
                                }).toList(),
                              ),
                            ),
                          
                          // Destination Field
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildLocationField(
                                    key: const ValueKey('destination_field'),
                                    controller: viewModel.destinationController,
                                    labelText: AppLocale.destination.getString(context),
                                    legDistance: () { // Calculate leg distance for destination
                                      if (viewModel.allFetchedRoutes.isNotEmpty &&
                                          viewModel.selectedRouteIndex < viewModel.allFetchedRoutes.length &&
                                          viewModel.allFetchedRoutes[viewModel.selectedRouteIndex]['legs'] is List) {
                                        final legs = viewModel.allFetchedRoutes[viewModel.selectedRouteIndex]['legs'] as List<dynamic>;
                                        final destLegIndex = viewModel.stops.length; // The leg leading to destination
                                        if (destLegIndex < legs.length && legs[destLegIndex] is Map<String, dynamic>) {
                                          final legData = legs[destLegIndex] as Map<String, dynamic>;
                                          if (legData['distance'] is Map<String, dynamic>) {
                                            return (legData['distance'] as Map<String, dynamic>)['text'] as String?;
                                          } // Removed the direct cast fallback as it was causing the error
                                        }
                                      }
                                      return null;
                                    }(),
                                    legDuration: () { // Calculate leg duration for destination
                                       if (viewModel.allFetchedRoutes.isNotEmpty &&
                                          viewModel.selectedRouteIndex < viewModel.allFetchedRoutes.length &&
                                          viewModel.allFetchedRoutes[viewModel.selectedRouteIndex]['legs'] is List) {
                                        final legs = viewModel.allFetchedRoutes[viewModel.selectedRouteIndex]['legs'] as List<dynamic>;
                                        final destLegIndex = viewModel.stops.length; // The leg leading to destination
                                        if (destLegIndex < legs.length && legs[destLegIndex] is Map<String, dynamic>) {
                                          final legData = legs[destLegIndex] as Map<String, dynamic>;
                                          if (legData['duration'] is Map<String, dynamic>) {
                                            return (legData['duration'] as Map<String, dynamic>)['text'] as String?;
                                          }
                                        }
                                      }
                                      return null;
                                    }(),
                                    hintText: AppLocale.enterDestination.getString(context),
                                    iconData: Icons.flag_outlined,
                                    iconColor: Theme.of(context).colorScheme.error,
                                    isEditing: viewModel.editingDestination,
                                    focusNode: _destinationFocusNode,
                                    onTapWhenNotEditing: () => _startEditing('destination'),
                                    onChanged: (value) => viewModel.getGooglePlacesSuggestions(value, 'destination'),
                                    onClear: viewModel.clearDestination,
                                    onMapIconTap: () { viewModel.editingDestination = true; _collapseSheet(); ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text(AppLocale.tapOnMapToSelectDestination.getString(context)))); },
                                  ),
                                ),
                                if (viewModel.pickupLocation != null && viewModel.dropOffLocation != null) // Show swap button if both are set
                                  IconButton(
                                  icon: const Icon(Icons.clear), // The Icon
                                  tooltip: AppLocale.clearPickup.getString(context),
                                    onPressed: () {
                                        viewModel.clearDestination();
                                        viewModel.editingDestination = true;
                                        _destinationFocusNode.requestFocus();
                                      },                                 
                              ),
                              ],
                            ),
                          ),
                          
                          if (viewModel.editingDestination) // Suggestions list for destination
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                children: _buildSuggestionList(viewModel.destinationSuggestions, false, null),
                              ),
                            ),
                          
                          // "Add Note to Driver" field - moved here
                          if (showActionButtons)
                            Padding(
                              key: const ValueKey('customer_note_field_padding'), // Add key
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: TextField(
                                key: const ValueKey('customer_note_textfield'), // Add key
                                controller: viewModel.customerNoteController,
                                decoration: appInputDecoration( // Use appInputDecoration
                                  labelText: AppLocale.addNoteToDriver.getString(context),
                                  hintText: AppLocale.addNoteToDriverHint.getString(context),
                                  prefixIcon: Icon(Icons.note_add_outlined, color: Theme.of(context).hintColor),
                                ),
                                maxLines: 2,
                                onTap: () { // Ensure sheet expands when note field is tapped
                                  _expandSheet();
                                  _startEditing('note'); // A generic field name, or handle focus differently
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    SliverToBoxAdapter(
                      // Adjust spacing based on sheet expansion
                      child: SizedBox(height: _isSheetExpanded ? 120 : 80), 
                    ),
                  ],
                ),
              ),
              
              // Action Buttons (only shown when both pickup and destination are set)
              if (showActionButtons) // Use the boolean flag
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  // Use theme surface color to blend with sheet
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => _scheduleRide(context),
                          // Style comes from OutlinedButtonThemeData
                          style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
                                minimumSize: MaterialStateProperty.all(const Size(double.infinity, 50)),
                              ),
                          child:  Text(AppLocale.schedule.getString(context)),
                        ),
                      ),
                      horizontalSpaceMedium,
                      Expanded(
                        flex: 3, // Confirm Route button larger
                        child: ElevatedButton(
                          onPressed: viewModel.estimatedFare != null ? viewModel.confirmRideRequest : null, // Disable if no fare
                          style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                                minimumSize: MaterialStateProperty.all(const Size(double.infinity, 50)),
                              ),
                          child: Text(viewModel.estimatedFare != null ? AppLocale.confirmRoute.getString(context) : AppLocale.calculatingFare.getString(context), style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFindingDriverSheet(CustomerHomeViewModel viewModel) {
    final theme = Theme.of(context);
    return Positioned( // Use Positioned to overlay or place at bottom
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            verticalSpaceMedium,
            Text(
              AppLocale.findingADriverForYou.getString(context),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            verticalSpaceMedium,
            OutlinedButton( // Changed to OutlinedButton for better visibility
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              onPressed: viewModel.cancelRideRequest,
              child: Text('Cancel Search', style: TextStyle(color: theme.colorScheme.error)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRideFailedSheet(CustomerHomeViewModel viewModel, String status) {
    final theme = Theme.of(context);
    final message = status == 'declined_by_driver'
        ? 'The driver is unavailable. Would you like to find another?'
        : 'No drivers were found nearby. Please try again.';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('😪', style: TextStyle(fontSize: 40)), // Replaced icon with emoji
            verticalSpaceMedium,
            Text(message, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            verticalSpaceMedium,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () {
                      viewModel.activeRideRequestId = null;
                      viewModel.isFindingDriver = false;
                    }, child: Text(AppLocale.cancel.getString(context))),
                ),
                horizontalSpaceMedium,
                Expanded(
                  child: ElevatedButton(onPressed: viewModel.confirmRideRequest, child: Text(AppLocale.findAnotherDriver.getString(context))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverAssignedSheet(CustomerHomeViewModel viewModel) {
    return DraggableScrollableSheet(
      initialChildSize: 0.4, // Adjust initial size as needed
      minChildSize: 0.25,
      maxChildSize: 0.6, // Adjust max size
      builder: (BuildContext context, ScrollController scrollController) {
        final theme = Theme.of(context);
        final rideDetails = viewModel.activeRideRequestDetails;

        if (rideDetails == null) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
            ),
            child:  Center(child: Text(AppLocale.waitingForRideDetails.getString(context)))
          );
        }

        final rideStatus = rideDetails.status;

        // Loading/waiting state
        if (rideStatus == 'pending_driver_acceptance' || (rideDetails.driverId != null && rideDetails.driverName == null)) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Make column take minimum space
              mainAxisAlignment: MainAxisAlignment.center, // Center content
              children: [
                CircularProgressIndicator(color: theme.colorScheme.primary),
                verticalSpaceMedium,
                Text(
                  rideStatus == 'pending_driver_acceptance'
                      ? AppLocale.waitingForDriverToAccept.getString(context)
                      : AppLocale.driverAssignedLoadingDetails.getString(context),
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                verticalSpaceSmall,
                if (rideStatus == 'pending_driver_acceptance')
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error, side: BorderSide(color: theme.colorScheme.error)),
                    onPressed: viewModel.cancelRideRequest,
                    child:  Text(AppLocale.cancelRide.getString(context)),
                  ),
              ],
            ),
          );
        }

        // Main content for assigned driver
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
          ),
          child: ListView( // Changed to ListView for scrolling
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center( // Drag handle
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: theme.colorScheme.outline.withOpacity(0.5), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              if (rideDetails.driverProfileImageUrl != null && rideDetails.driverProfileImageUrl!.isNotEmpty)
                Center(child: CircleAvatar(radius: 30, backgroundImage: NetworkImage(rideDetails.driverProfileImageUrl!)))
              else
                Center(child: CircleAvatar(radius: 30, backgroundColor: theme.colorScheme.primaryContainer, child: Icon(Icons.drive_eta, size: 30, color: theme.colorScheme.onPrimaryContainer))),
              verticalSpaceSmall,
              Center(child: Text(rideDetails.driverName ?? AppLocale.driver.getString(context), style: theme.textTheme.titleLarge)),
              if (rideDetails.driverVehicleType != null && rideDetails.driverVehicleType != "N/A")
                Center(child: Text("${AppLocale.vehicle.getString(context)}: ${rideDetails.driverVehicleType}", style: theme.textTheme.bodySmall)),
              
              Builder(builder: (context) {
                final gender = rideDetails.driverGender;
                final ageGroup = rideDetails.driverAgeGroup;
                List<String> details = [];
                if (gender != null && gender.isNotEmpty && gender != "Unknown") details.add(gender); 
                if (ageGroup != null && ageGroup.isNotEmpty && ageGroup != "Unknown") details.add(ageGroup);
                if (details.isNotEmpty) {
                  return Center(child: Text(details.join(', '), style: theme.textTheme.bodySmall));
                }
                return const SizedBox.shrink();
              }),
              verticalSpaceSmall,
              if (rideDetails.driverAverageRating != null && rideDetails.driverAverageRating! > 0)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, color: accentColor, size: 16),
                      horizontalSpaceSmall,
                      Text(rideDetails.driverAverageRating!.toStringAsFixed(1), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      if (rideDetails.driverCompletedRidesCount != null && rideDetails.driverCompletedRidesCount! > 0)
                        Padding(padding: const EdgeInsets.only(left: 8.0), child: Text("(${rideDetails.driverCompletedRidesCount} rides)", style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))),
                    ],
                  ),
                ),
              // License number - now visible if content scrolls
              if (rideDetails.driverLicenseNumber != null && rideDetails.driverLicenseNumber!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Center(
                    child: Text(
                      '${AppLocale.licensePlate.getString(context)}: ${rideDetails.driverLicenseNumber}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ),
                ),
              verticalSpaceSmall,
              Center(
                child: Chip(
                  label: Text('${AppLocale.status.getString(context)} $rideStatus', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
                  backgroundColor: theme.colorScheme.secondaryContainer,
                ),
              ),
              verticalSpaceMedium,
              // Chat with Driver Button
              if (rideDetails.driverId != null && (rideStatus == 'accepted' || rideStatus == 'goingToPickup' || rideStatus == 'arrivedAtPickup' || rideStatus == 'onRide'))
                TextButton.icon(
                  icon: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary),
                  label: Text(AppLocale.chatWithDriver.getString(context), style: TextStyle(color: theme.colorScheme.primary)),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
                      rideRequestId: rideDetails.id!,
                      recipientId: rideDetails.driverId!,
                      recipientName: rideDetails.driverName ?? "Driver",
                    ),
                    ));
                  },
                ),
              // Add/Edit Note Button
              if (rideStatus == 'accepted' || rideStatus == 'goingToPickup')
                TextButton.icon(
                  icon: Icon(Icons.edit_note_outlined, color: theme.colorScheme.secondary),
                  label: Text(rideDetails.customerNoteToDriver != null && rideDetails.customerNoteToDriver!.isNotEmpty ? AppLocale.editNote.getString(context) : AppLocale.addNoteToDriver.getString(context), style: TextStyle(color: theme.colorScheme.secondary)),
                  onPressed: () => _showAddNoteDialog(rideDetails.id!, rideDetails.customerNoteToDriver),
                ),
              // Cancel Ride Button
              if (rideStatus != 'onRide' && rideStatus != 'completed' && !rideStatus.contains('cancelled'))
                Padding(
                  padding: const EdgeInsets.only(top: 8.0), // Add some space above
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error, side: BorderSide(color: theme.colorScheme.error)),
                    onPressed: viewModel.cancelRideRequest,
                    child:  Text(AppLocale.cancelRide.getString(context)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStopItem(int index, Stop stop) {
    final isEditing = _viewModel.editingStopIndex == index;
    final theme = Theme.of(context); // Get theme
    String? legDistanceText;
    String? legDurationText;

    // Safely access and parse leg data for this stop
    if (_viewModel.allFetchedRoutes.isNotEmpty &&
        _viewModel.selectedRouteIndex < _viewModel.allFetchedRoutes.length &&
        _viewModel.allFetchedRoutes[_viewModel.selectedRouteIndex]['legs'] is List) {
      final legs = _viewModel.allFetchedRoutes[_viewModel.selectedRouteIndex]['legs'] as List<dynamic>;
      // The leg at 'index' leads TO this stop 'index'.
      if (index < legs.length && legs[index] is Map<String, dynamic>) {
        final legData = legs[index] as Map<String, dynamic>;
        if (legData['distance'] is Map<String, dynamic>) {
          legDistanceText = (legData['distance'] as Map<String, dynamic>)['text'] as String?;
        }
        if (legData['duration'] is Map<String, dynamic>) {
          legDurationText = (legData['duration'] as Map<String, dynamic>)['text'] as String?;
        }
      }
    }
    
    return Padding( // Added Padding around the stop item
      key: ObjectKey(_viewModel.stops[index]), // Key for the Padding, helps with list updates
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start, // Align items to the top
            children: [
              Expanded(
                child: Dismissible(
                  key: ValueKey('stop_dismissible_$index'), // Unique key for Dismissible
                  direction: DismissDirection.endToStart,
                  background: Container(
                    decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(Icons.delete, color: theme.colorScheme.onErrorContainer),
                  ),
                  onDismissed: (direction) => _viewModel.removeStop(index),
                  child: _buildLocationField( // Use the new _buildLocationField
                    key: ValueKey('stop_field_$index'), // Key for the location field itself
                    controller: stop.controller,
                    labelText: 'Stop ${index + 1}',
                    legDistance: legDistanceText, // Pass calculated leg distance
                    legDuration: legDurationText, // Pass calculated leg duration
                    hintText: 'Add stop location',
                    iconData: Icons.location_on_outlined, // Or a numbered icon
                    iconColor: theme.primaryColor.withOpacity(0.7),
                    isEditing: isEditing,
                    focusNode: stop.focusNode, // Use stop's own focus node
                    onTapWhenNotEditing: () => _startEditing('stop_$index'),
                    onChanged: (value) => _viewModel.getGooglePlacesSuggestions(value, 'stop'),
                    onClear: () => _viewModel.clearStop(index),
                    onMapIconTap: () { 
                      _viewModel.editingStopIndex = index; 
                      _viewModel.startEditing('stop_$index');
                      _collapseSheet(); 
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${AppLocale.tapOnMapToSelectLocationOrStop.getString(context)} ${index + 1}'
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              horizontalSpaceSmall,
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 24),
                color: theme.colorScheme.secondary,
                onPressed: () => _viewModel.addStopAfter(index),
                tooltip: 'Add stop after this one',
              ),
            ],
          ),
          if (isEditing) // Suggestions list for the stop
            Padding(
              padding: const EdgeInsets.only(top: 0, left: 0, right: 40), // Adjust padding to align under text field
              child: Column(
                children: _buildSuggestionList(_viewModel.stopSuggestions, false, index),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSuggestionList(List<Map<String, dynamic>> suggestions, bool isPickup, int? stopIndex) {
    return [
      if (suggestions.isNotEmpty)
        ...suggestions.map((suggestion) => _buildSuggestionItem(suggestion, isPickup, stopIndex)).toList(),
      if (suggestions.isEmpty && _viewModel.searchHistory.isNotEmpty)
        ..._viewModel.searchHistory.map((history) => _buildHistoryItem(history)).toList(),
    ];
  }

  Widget _buildSuggestionItem(Map<String, dynamic> suggestion, bool isPickup, int? stopIndex) {
    final theme = Theme.of(context);
    return ListTile(
      // Use theme icon color
      leading: Icon(isPickup ? Icons.location_on : Icons.flag, color: theme.iconTheme.color),
    title: Text(suggestion['description'] ?? '', style: theme.textTheme.bodyMedium), // Use theme text style
      onTap: () {
        if (stopIndex != null) { // Check if editing a stop
          _viewModel.handleStopSelected(stopIndex, suggestion);
        } else if (isPickup) {
          _viewModel.handlePickupSelected(suggestion);
        } else {
          _viewModel.handleDestinationSelected(suggestion);
        }
      },
    );
  }

  Widget _buildHistoryItem(String historyItem) {
  final theme = Theme.of(context);
  return ListTile(
    // Use theme icon color
    leading: Icon(Icons.history, color: theme.iconTheme.color),
    title: Text(historyItem, style: theme.textTheme.bodyMedium), // Use theme text style
    onTap: () async {
      try {
        final List<Location> locations = await locationFromAddress(historyItem);
        if (locations.isNotEmpty) {
          final location = locations.first;
          final llLatLng = ll.LatLng(location.latitude, location.longitude);
          final suggestion = {'place_id': '', 'description': historyItem}; // Mock suggestion

          if (_pickupFocusNode.hasFocus || _viewModel.editingPickup) {
            _viewModel.pickupController.text = historyItem;
            _viewModel.pickupLocation = llLatLng;
            _viewModel.handlePickupSelected(suggestion);
          } else if (_destinationFocusNode.hasFocus || _viewModel.editingDestination) {
            _viewModel.destinationController.text = historyItem;
            _viewModel.dropOffLocation = llLatLng;
            _viewModel.handleDestinationSelected(suggestion);
          } else if (_stopFocusNode.hasFocus || _viewModel.editingStopIndex != null) {
            final index = _viewModel.editingStopIndex!;
            _viewModel.stops[index].controller.text = historyItem;
            _viewModel.stops[index].location = llLatLng;
            _viewModel.handleStopSelected(index, suggestion);
          }

          _viewModel.drawRoute();
          _collapseSheet();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocale.locationNotFound.getString(context))),
            );
          }
        }
      } catch (e) {
        print('Error geocoding history item: $e');
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(AppLocale.errorFindingLocation.getString(context))),
        );
      }
    },
  );
 }

  Future<void> _showRateDriverDialog(String rideId, String driverId) async {
    double ratingValue = 0;
    final theme = Theme.of(context);
    TextEditingController commentController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // User must explicitly submit or skip
      builder: (BuildContext dialogContext) {
        return StatefulBuilder( // To update stars in the dialog
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(AppLocale.rateYourDriver.getString(context), style: theme.textTheme.titleLarge),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Text(AppLocale.howWasYourRide.getString(context), style: theme.textTheme.bodyMedium),
                    verticalSpaceMedium,
                    // Display final fare, if available
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('rideRequests').doc(rideId).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final rideData = snapshot.data!.data() as Map<String, dynamic>?;
                          final fare = rideData?['fare'] as num?;
                          if (fare != null) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('${AppLocale.final_fare_prefix.getString(context)} TZS ${fare.toStringAsFixed(0)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                            );
                          }
                        }
                        return const SizedBox.shrink();
                      }
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(
                            index < ratingValue ? Icons.star : Icons.star_border,
                            color: accentColor, // From ui_utils
                            size: 30,
                          ),
                          onPressed: () {
                            setDialogState(() => ratingValue = index + 1.0);
                          },
                        );
                      }),
                    ),
                    verticalSpaceSmall,
                    TextField(
                      controller: commentController,
                      decoration: appInputDecoration(hintText: "Add a comment (optional)"),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(AppLocale.skip.getString(context), style: TextStyle(color: theme.hintColor)),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton(
                  child:  Text(AppLocale.submitRating.getString(context)),
                  onPressed: () async {
                    final navigator = Navigator.of(dialogContext);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);

                    if (ratingValue > 0) {
                      final comment = commentController.text.trim().isNotEmpty ? commentController.text.trim() : null;
                      
                      // Pop the dialog first
                      if (navigator.canPop()) {
                        navigator.pop();
                      }

                      // Then call the view model to do the work
                      await _viewModel.rateDriver(rideId, driverId, ratingValue, comment);

                    } else {
                      scaffoldMessenger.showSnackBar( SnackBar(content: Text(AppLocale.pleaseSelectAStarRating.getString(context))));
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    // This now runs after the dialog is popped, either by submitting or skipping.
    if (mounted) {
      _showPostRideCompletionDialog();
    }
  }
  
  void _showPostRideCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          actions: <Widget>[
            TextButton(
              child: Text(AppLocale.returnTrip.getString(context)),
              onPressed: () async { // Make onPressed async
                Navigator.of(dialogContext).pop();
                _viewModel.resetActiveRideStateOnly(); // Reset the ride state but keep locations
                if (_viewModel.stops.isNotEmpty) {
                  // Show another dialog to ask about stops
                  bool? clearStops = await showDialog<bool>(
                    context: context, // Use the main screen's context
                    builder: (BuildContext stopsDialogContext) {
                      return AlertDialog(
                        title: Text(AppLocale.keepStopsDialogTitle.getString(context)),
                        content: Text(AppLocale.keepStopsDialogContent.getString(context)),
                        actions: <Widget>[
                          TextButton(
                            child: Text(AppLocale.clearStops.getString(context)),
                            onPressed: () => Navigator.of(stopsDialogContext).pop(true),
                          ),
                          TextButton(
                            child: Text(AppLocale.keepStops.getString(context)),
                            onPressed: () => Navigator.of(stopsDialogContext).pop(false),
                          ),
                        ],
                      );
                    },
                  );
                  if (clearStops == true) {
                    _viewModel.stops.clear();
                    // Markers will be cleared in drawRoute
                  }
                }
                _viewModel.swapLocations(); // Swaps pickup and destination
                _viewModel.drawRoute(); // Redraw route after potential changes
              },
            ),
            TextButton(
              child: Text(AppLocale.viewRideHistory.getString(context)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _viewModel.resetUIForNewTrip(); // Reset the form before navigating
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RidesScreen(role: 'Customer')));
              },
            ),
            TextButton(
              child: Text(AppLocale.thanks.getString(context)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _viewModel.resetUIForNewTrip(); // Reset the form
              },
            ),
          ],
        );
      },
    );
  }

@override
  void dispose() {
    _mapController?.dispose();
    _sheetController.dispose();
    _destinationFocusNode.dispose();
    _pickupFocusNode.dispose();
    _stopFocusNode.dispose();
    _viewModel.onUiAction = null;
    // ViewModel is disposed by the provider
    super.dispose();
  }
}
