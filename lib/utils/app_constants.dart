/// A collection of string constants used throughout the application,
/// especially for map keys in Firestore documents or API responses.
class AppConstants {
  // Ride Request/Ride Model Keys
  static const String rideRequestIdKey = 'rideRequestId';
  static const String customerIdKey = 'customerId';
  static const String pickupLocationKey = 'pickupLocation';
  static const String destinationLocationKey = 'destinationLocation';
  static const String pickupAddressKey = 'pickupAddress';
  static const String destinationAddressKey = 'destinationAddress';
  static const String customerNameKey = 'customerName';
  static const String customerPhoneNumberKey = 'customerPhoneNumber';
  static const String statusKey = 'status';

  // Driver/User Profile Keys
  static const String isOnlineKey = 'isOnline';
  static const String currentKijiweIdKey = 'currentKijiweId';
  static const String dailyEarningsKey = 'dailyEarnings';
  static const String positionKey = 'position';
  static const String geopointKey = 'geopoint';
  static const String nameKey = 'name';

  // Google Directions API Keys
  static const String routesKey = 'routes';
  static const String overviewPolylineKey = 'overview_polyline';
  static const String pointsKey = 'points';
  static const String legsKey = 'legs';
  static const String distanceKey = 'distance';
  static const String durationKey = 'duration';
  static const String textKey = 'text';
  static const String valueKey = 'value';

  // Ride Statuses
  static const String rideStatusPending = 'pending';
  static const String rideStatusAccepted = 'accepted';
  static const String rideStatusInProgress = 'in_progress';
  static const String rideStatusCompleted = 'completed';
  static const String rideStatusCancelled = 'cancelled';
  static const String rideStatusDeclined = 'declined';
}