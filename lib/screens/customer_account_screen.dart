import 'driver_registration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../utils/ui_utils.dart';
import 'saved_places_screen.dart';
import '../localization/locales.dart';
import '../utils/account_utils.dart';
import '../models/user_model.dart';
import '../widgets/shared_account_options.dart';
import '../widgets/account_option_widgets.dart';

class CustomerAccountScreen extends StatelessWidget {
  final UserModel userModel;

  const CustomerAccountScreen({super.key, required this.userModel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.myAccount.getString(context)),
        centerTitle: true,
        automaticallyImplyLeading: false, // No back button if it's a main tab
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          buildAccountSectionTitle(context, AppLocale.accountManagement.getString(context)),
          buildAccountOption(context, Icons.payment, AppLocale.paymentMethods.getString(context), () {
            // TODO: Navigate to Payment Methods
          }),
          buildAccountOption(context, Icons.place, AppLocale.savedPlaces.getString(context), () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SavedPlacesScreen(),
              ),
            );
          }),
          verticalSpaceMedium,
          const SharedAccountOptions(userRole: 'Customer'),
          verticalSpaceLarge,
          buildAccountSectionTitle(context, AppLocale.accountActions.getString(context)),
          _buildDriverSwitchOption(context),
          verticalSpaceSmall,
          buildAccountOption(context, Icons.delete_forever, AppLocale.deleteAccount.getString(context),
              () => AccountUtils.showDeleteAccountDialog(context), isDestructive: true),
          verticalSpaceSmall,
          buildAccountOption(context, Icons.exit_to_app, AppLocale.logout.getString(context),
              () => AccountUtils.showLogoutConfirmationDialog(context, userRole: 'Customer'), isDestructive: true),
        ],
      ),
    );
  }

  Widget _buildDriverSwitchOption(BuildContext context) {
    // Use the userModel passed from HomeScreen to avoid a new database read.
    final driverProfile = userModel.driverProfile;
    final bool hasCompletedDriverProfile = driverProfile?['kijiweId'] != null &&
        (driverProfile!['kijiweId'] as String).isNotEmpty;

    if (hasCompletedDriverProfile) {
      // User has a complete driver profile, allow switching
      return buildAccountOption(context, Icons.switch_account, AppLocale.switchToDriver.getString(context), () {
        // Add a null check for safety, even though uid should be non-nullable.
        final userId = userModel.uid;
        if (userId != null) {
          AccountUtils.showSwitchToDriverDialog(context);
        }
      });
    } else {
      // User does not have a complete profile, prompt to register
      return buildAccountOption(context, Icons.directions_bike, AppLocale.becomeADriver.getString(context), () {
        _navigateToDriverRegistration(context);
      });
    }
  }

  void _navigateToDriverRegistration(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DriverRegistrationScreen()),
    );
  }
}