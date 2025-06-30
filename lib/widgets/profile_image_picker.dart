import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class ProfileImagePicker extends StatelessWidget {
  final String? initialImageUrl;
  final bool enabled;
  final Function(File) onImagePicked;

  const ProfileImagePicker({
    Key? key,
    this.initialImageUrl,
    this.enabled = true,
    required this.onImagePicked,
  }) : super(key: key);

  void _pickImage(BuildContext context) async {
    final pickedImage = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedImage == null) {
      return;
    }

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedImage.path,
      compressQuality: 50,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Photo',
          toolbarColor: Theme.of(context).primaryColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          cropStyle: CropStyle.circle,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
        IOSUiSettings(
          title: 'Crop Profile Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          minimumAspectRatio: 1.0,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      ],
    );

    if (croppedFile == null) {
      return;
    }

    onImagePicked(File(croppedFile.path));
  }

  @override
  Widget build(BuildContext context) {
    // Only allow picking if enabled
    return GestureDetector(
      onTap: enabled
          ? () async {
              _pickImage(context);
            }
          : null,
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.grey,
            foregroundImage: (initialImageUrl != null && initialImageUrl!.isNotEmpty)
                ? NetworkImage(initialImageUrl!)
                : null,
            child: (initialImageUrl == null || initialImageUrl!.isEmpty)
                ? const Icon(Icons.person, size: 40, color: Colors.white)
                : null,
          ),
          TextButton.icon(
            onPressed: enabled ? () => _pickImage(context) : null,
            icon: const Icon(Icons.image),
            label: const Text('Add/Change Photo'),
          ),
        ],
      ),
    );
  }
}