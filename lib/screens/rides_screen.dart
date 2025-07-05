import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
//import 'package:provider/provider.dart';
//import '../providers/auth_provider.dart'; // Assuming you have an AuthProvider or similar for user ID
//import '../utils/ui_utils.dart'; // For spacing and styles
import '../localization/locales.dart';
import 'ride_history_list_widget.dart';
import 'scheduled_rides_list_widget.dart';

class RidesScreen extends StatefulWidget {
  final String role;

  const RidesScreen({super.key, required this.role});

  @override
  State<RidesScreen> createState() => _RidesScreenState();
}

class _RidesScreenState extends State<RidesScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    if (widget.role == 'Customer') {
      _tabController = TabController(length: 2, vsync: this);
    } else if (widget.role == 'Driver') {
      _tabController = TabController(length: 1, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final authProvider = Provider.of<AuthService>(context, listen: false); // Assuming AuthService provides currentUserId
    // final String? userId = authProvider.currentUser?.uid;
    // For simplicity, let's assume userId is passed or fetched if needed by child widgets directly or via another provider

    if (_tabController == null) {
      // This case should ideally not be hit if role is always Customer or Driver
      return Scaffold(
        appBar: AppBar(title: Text(AppLocale.myRides.getString(context))),
        body: Center(child: Text(AppLocale.invalidRoleForRidesScreen.getString(context))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.myRides.getString(context)),
        centerTitle: true, // Add this line to center the title
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onSurface, //onPrimary, // From app_theme.dart
          unselectedLabelColor: theme.colorScheme.onPrimary.withOpacity(0.7),
          indicatorColor: theme.colorScheme.secondary, // From app_theme.dart (accentColor equivalent)
          tabs: widget.role == 'Customer'
              ? [
                  Tab(text: AppLocale.history.getString(context)),
                  Tab(text: AppLocale.scheduled.getString(context)),
                ]
              : [
                  Tab(text: AppLocale.history.getString(context)),
                ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: widget.role == 'Customer'
            ? [
                // TODO: Pass userId if RideHistoryListWidget needs it directly
                RideHistoryListWidget(role: widget.role),
                ScheduledRidesListWidget(),
              ]
            : [
                // TODO: Pass userId if RideHistoryListWidget needs it directly
                RideHistoryListWidget(role: widget.role),
              ],
      ),
    );
  }
}