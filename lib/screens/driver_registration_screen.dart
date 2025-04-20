import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/driver_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriverRegistrationScreen extends StatefulWidget {
  @override
  _DriverRegistrationScreenState createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _vehicleTypeController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  String? _selectedKijiweId; // To store the selected Kijiwe ID
  List<String> _kijiweList = ['kijiwe1', 'kijiwe2', 'kijiwe3']; // Replace with your actual Kijiwe list fetching logic

  @override
  Widget build(BuildContext context) {
    final driverProvider = Provider.of<DriverProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text('Driver Registration')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _vehicleTypeController,
              decoration: InputDecoration(labelText: 'Vehicle Type (e.g., Motorcycle, Car)'),
            ),
            SizedBox(height: 16),
            TextFormField(
              controller: _licenseNumberController,
              decoration: InputDecoration(labelText: 'License Number'),
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(labelText: 'Select Your Kijiwe'),
              value: _selectedKijiweId,
              items: _kijiweList.map((kijiwe) {
                return DropdownMenuItem<String>(
                  value: kijiwe,
                  child: Text(kijiwe), // Display Kijiwe name if you have it
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedKijiweId = value;
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select your Kijiwe';
                }
                return null;
              },
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                if (_selectedKijiweId != null) {
                  String? userId = FirebaseAuth.instance.currentUser?.uid;
                  if (userId != null) {
                    await driverProvider.registerAsDriver(
                      context: context,
                      userId: userId,
                      vehicleType: _vehicleTypeController.text.trim(),
                      licenseNumber: _licenseNumberController.text.trim(),
                      kijiweId: _selectedKijiweId!,
                    );

                    // Optionally navigate to a success screen or home
                    Navigator.pop(context); // Go back after registration
                  } else {
                    // Handle the case where the user is not logged in
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('User not logged in.')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please select your Kijiwe.')),
                  );
                }
              },
              child: Text('Complete Driver Registration'),
            ),
          ],
        ),
      ),
    );
  }
}