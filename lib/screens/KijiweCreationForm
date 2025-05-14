import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateKijiweScreen extends StatefulWidget {
  const CreateKijiweScreen({super.key});

  @override
  State<CreateKijiweScreen> createState() => _CreateKijiweScreenState();
}

class _CreateKijiweScreenState extends State<CreateKijiweScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _unionIdController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isLoading = false;

  Future<void> _createKijiwe() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User not logged in")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final kijiweRef = firestore.collection('kijiwe').doc();

      // Create the Kijiwe document
      await kijiweRef.set({
        'name': _nameController.text.trim(),
        'unionId': _unionIdController.text.trim(),
        'location': _locationController.text.trim(), // Optional: convert to GeoPoint
        'adminId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'permanentMembers': [uid],
      });

      // Add admin (creator) to queue
      await kijiweRef.collection('queue').doc(uid).set({
        'driverId': uid,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Optional: update driver profile if needed
      await firestore.collection('driver').doc(uid).update({
        'kijiweId': kijiweRef.id,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kijiwe created successfully!")),
      );

      Navigator.pop(context); // Return to previous screen
    } catch (e) {
      debugPrint("Error creating kijiwe: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to create Kijiwe: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Kijiwe")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Kijiwe Name'),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unionIdController,
                decoration: const InputDecoration(labelText: 'Union ID'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location Description',
                  hintText: 'e.g. Near Ubungo Terminal',
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _createKijiwe,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text("Create Kijiwe"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
