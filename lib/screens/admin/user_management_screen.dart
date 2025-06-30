 import 'package:flutter/material.dart';
 import 'package:cloud_firestore/cloud_firestore.dart';
 import '../../models/user_model.dart';
 //import '../../models/user_model.dart'; // Ensure UserModel is imported
 
 class UserManagementScreen extends StatelessWidget {
   const UserManagementScreen({super.key});
 
   @override
   Widget build(BuildContext context) {
     return Scaffold(
       body: StreamBuilder<QuerySnapshot>(
         stream: FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true).snapshots(),
         builder: (context, snapshot) {
           if (snapshot.connectionState == ConnectionState.waiting) {
             return const Center(child: CircularProgressIndicator());
           }
           if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
           }
           if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
             return const Center(child: Text('No users found.'));
           }
 
           final users = snapshot.data!.docs.map((doc) {
             return UserModel.fromJson(doc.data() as Map<String, dynamic>);
           }).toList();
 
           return ListView.builder(
             itemCount: users.length,
             itemBuilder: (context, index) {
               final user = users[index];
               final theme = Theme.of(context);
               return Card(
                 margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 child: ListTile(
                   leading: CircleAvatar(
                     backgroundImage: user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty
                         ? NetworkImage(user.profileImageUrl!)
                         : null,
                     child: user.profileImageUrl == null || user.profileImageUrl!.isEmpty
                         ? const Icon(Icons.person)
                         : null,
                   ),
                   title: Text(user.name ?? 'No Name'),
                   subtitle: Text('${user.role ?? 'No Role'} - ${user.email ?? 'No Email'}'),
                   trailing: Icon(Icons.arrow_forward_ios, size: 16, color: theme.hintColor),
                   onTap: () {
                     // TODO: Navigate to a user detail/edit screen
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('Tapped on ${user.name}')),
                     );
                   },
                 ),
               );
             },
           );
         },
       ),
     );
   }
 }

