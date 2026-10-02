import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

class QRImageUploadPage extends StatefulWidget {
  const QRImageUploadPage({super.key});

  @override
  State<QRImageUploadPage> createState() => _QRImageUploadPageState();
}

class _QRImageUploadPageState extends State<QRImageUploadPage> {
  File? _imageFile;
  String? _downloadUrl;
  bool _uploading = false;

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No image selected")),
      );
      return;
    }

    setState(() {
      _imageFile = File(pickedFile.path);
      _uploading = true;
    });

    try {
      final fileName = path.basename(pickedFile.path);
      final fileExtension = path.extension(fileName).toLowerCase();

      // Allow only jpg, jpeg, png
      if (!['.jpg', '.jpeg', '.png'].contains(fileExtension)) {
        throw Exception("Invalid file type: $fileExtension");
      }

      final ref = FirebaseStorage.instance.ref().child('shop-qr/$fileName');
      await ref.putFile(_imageFile!);

      final url = await ref.getDownloadURL();
      setState(() {
        _downloadUrl = url;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Image uploaded successfully")),
      );
    } catch (e) {
      print("Upload failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Upload failed: $e")),
      );
    } finally {
      setState(() {
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload QR Code")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_imageFile != null)
              Image.file(_imageFile!, height: 200),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _uploading ? null : _pickAndUploadImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800], // Background color
                foregroundColor: Colors.white,     // Text color
              ),
              child: Text(_uploading ? "Uploading..." : "Pick & Upload QR Code"),
            ),
            if (_downloadUrl != null) ...[
              const SizedBox(height: 16),
              const Text("Download URL:", style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(_downloadUrl!, style: const TextStyle(fontSize: 12)),
            ]
          ],
        ),
      ),
    );
  }
}
