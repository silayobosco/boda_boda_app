import 'package:flutter/material.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  _DriverHomeState createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {

 @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text("Driver Home"),
      ),
    );
  }
}