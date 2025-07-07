import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import '../utils/ui_utils.dart';
import '../localization/locales.dart';
import '../utils/account_utils.dart';
import '../providers/driver_provider.dart';
import 'kijiwe_profile_screen.dart';
import '../widgets/shared_account_options.dart';
import '../widgets/account_option_widgets.dart';

class DriverAccountScreen extends StatelessWidget {
  const DriverAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DriverProvider>(
      builder: (context, driverProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(AppLocale.myAccount.getString(context)),
            centerTitle: true,
            automaticallyImplyLeading: false, // No back button if it's a main tab
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              buildAccountSectionTitle(context, AppLocale.driverOperations.getString(context)),
              buildAccountOption(context, Icons.account_balance_wallet, AppLocale.earningsWallet.getString(context), () {
                // TODO: Navigate to Earnings
              }),
              buildAccountOption(context, Icons.motorcycle, AppLocale.vehicleManagement.getString(context), () {
                // TODO: Navigate to Vehicle Management
              }),
              buildAccountOption(context, Icons.description, AppLocale.documentManagement.getString(context), () {
                // TODO: Navigate to Document Management
              }),
              buildAccountOption(context, Icons.group_work, AppLocale.kijiweProfile.getString(context), () {
                final kijiweId = driverProvider.currentKijiweId;
                if (kijiweId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => KijiweProfileScreen(kijiweId: kijiweId)),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You are not currently associated with a Kijiwe.')),
                  );
                }
              }),
              buildAccountOption(context, Icons.bar_chart, AppLocale.performance.getString(context), () {
                // TODO: Navigate to Performance
              }),
              verticalSpaceMedium,
              const SharedAccountOptions(userRole: 'Driver'),
              verticalSpaceLarge,
              buildAccountSectionTitle(context, AppLocale.accountActions.getString(context)),
              buildAccountOption(context, Icons.switch_account, AppLocale.switchToCustomer.getString(context), () {
                AccountUtils.showSwitchRoleDialog(context);
              }),
              verticalSpaceSmall,
              buildAccountOption(context, Icons.delete_forever, AppLocale.deleteAccount.getString(context),
                  () => AccountUtils.showDeleteAccountDialog(context), isDestructive: true),
              verticalSpaceSmall,
              buildAccountOption(context, Icons.exit_to_app, AppLocale.logout.getString(context),
                  () => AccountUtils.showLogoutConfirmationDialog(context, userRole: 'Driver'), isDestructive: true),
            ],
          ),
        );
      },
    );
  }
}