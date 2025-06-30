import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class ProfileImagePicker extends StatefulWidget {
  final void Function(File pickedImage) onImagePicked;
  final String? initialImageUrl;

  const ProfileImagePicker({
    super.key,
    required this.onImagePicked,
    this.initialImageUrl,
  });

  @override
  State<ProfileImagePicker> createState() => _ProfileImagePickerState();
}

class _ProfileImagePickerState extends State<ProfileImagePicker> {
  File? _pickedImageFile;

  void _pickImage() async {
    final pickedImage = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80, // A bit higher quality for cropping
    );

    if (pickedImage == null) {
      return;
    }

    if (!mounted) return;

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
            // For this version of image_cropper, these go inside uiSettings
            cropStyle: CropStyle.circle,
            aspectRatioPresets: [CropAspectRatioPreset.square]),
        IOSUiSettings(
          title: 'Crop Profile Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          minimumAspectRatio: 1.0,
          // For this version of image_cropper, aspectRatioPresets goes here.
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
      ],
    );

    if (croppedFile == null) {
      return;
    }

    setState(() {
      _pickedImageFile = File(croppedFile.path);
    });

    widget.onImagePicked(_pickedImageFile!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: Colors.grey,
          foregroundImage: _pickedImageFile != null
              ? FileImage(_pickedImageFile!)
              : (widget.initialImageUrl != null && widget.initialImageUrl!.isNotEmpty
                  ? NetworkImage(widget.initialImageUrl!)
                  : null) as ImageProvider?,
          child: _pickedImageFile == null && (widget.initialImageUrl == null || widget.initialImageUrl!.isEmpty)
              ? const Icon(Icons.person, size: 40, color: Colors.white)
              : null,
        ),
        TextButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.image),
          label: const Text('Add/Change Photo'),
        ),
      ],
    );
  }
}