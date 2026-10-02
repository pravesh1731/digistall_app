import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:permission_handler/permission_handler.dart';
import '../global/Common.dart';
import 'package:image_picker/image_picker.dart';
// import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../pages/SignInAndUp.dart';
import 'PaymentPage.dart';

File? _storeImage;

class ProfilePage extends StatefulWidget {
  final String shopId;
  const ProfilePage({super.key, required this.shopId,});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = '';
  String category = '';
  String address = '';
  String phone = '';
  String email = '';
  String gst = '';

  ImageProvider? _profileImageProvider;

  Future<void> _pickImage() async {
    if (Platform.isAndroid) {
      if (await _requestPermissionAndroid()) {
        _openImagePicker();
      }
    } else {
      _openImagePicker();
    }
  }

  Future<bool> _requestPermissionAndroid() async {
    final statusPhotos = await Permission.photos.status;
    final statusStorage = await Permission.storage.status;

    if (statusPhotos.isDenied || statusStorage.isDenied) {
      final statuses = await [Permission.photos, Permission.storage].request();

      final grantedPhotos = statuses[Permission.photos]?.isGranted ?? false;
      final grantedStorage = statuses[Permission.storage]?.isGranted ?? false;

      return grantedPhotos || grantedStorage;
    }

    return true;
  }

  Future<void> _openImagePicker() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);

    if (pickedFile != null) {
      final imageFile = File(pickedFile.path);
      final appDir = await getApplicationDocumentsDirectory();
      final savedFile = await imageFile.copy('${appDir.path}/${path.basename(imageFile.path)}');

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('storeImagePath', savedFile.path);

      setState(() {
        _storeImage = savedFile;
      });

      // final imageUrl = await uploadImageToFirebase(pickedFile);
      // if (imageUrl != null) {
      //   await prefs.setString('uploadedImageUrl', imageUrl);
      //   setState(() {
      //     _profileImageProvider = NetworkImage(imageUrl);
      //   });
      // }
    }
  }

  // Future<String?> uploadImageToFirebase(XFile imageFile) async {
  //   try {
  //     final fileName = 'profilesofyhofy-logo-${const Uuid().v4()}';
  //     final ref = FirebaseStorage.instance.ref().child(fileName);
  //
  //     final metadata = SettableMetadata(contentType: 'image/png');
  //     final uploadTask = await ref.putFile(File(imageFile.path), metadata);
  //
  //     final downloadUrl = await uploadTask.ref.getDownloadURL();
  //     return downloadUrl;
  //   } catch (e) {
  //     print('❌ Upload to Firebase failed: $e');
  //     return null;
  //   }
  // }

  @override
  void initState() {
    super.initState();
    _loadStoreData();
  }

  Future<void> _loadStoreData() async {
    try {
      final response = await http.post(
        Uri.parse(Common.baseUrl + 'shop'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"shopId": widget.shopId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['response'];

        final header = data['settings']['header'];
        final footer = data['settings']['footer'];

        setState(() {
          name = header['shopName'] ?? '-';
          category = (data['categorys']?.isNotEmpty ?? false)
              ? data['categorys'][0]['categoryName'] ?? '- - None - -'
              : '- - None - -';
          address = footer['address'] ?? '-';
          phone = header['phoneNumber'] ?? '-';
          email = header['email'] ?? '-';
          gst = data['gstNumber'] ?? '- - None - -';

          final imageUrl = header['logo'] ?? '';
          if (imageUrl.isNotEmpty) {
            _profileImageProvider = NetworkImage(imageUrl);
          }
        });
      } else {
        print("Failed to fetch shop data: ${response.body}");
      }
    } catch (e) {
      print("Error loading store data: $e");
    }
  }


  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: TextStyle(fontSize: Common.h2, color: Common.secondary)),
          ),
          Expanded(
            flex: 5,
            child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontSize: Common.h2, color: Common.secondary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (){
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Common.primary,
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Container(
              child: Center(
                child: Image.asset(
                  'assets/Icons/logo.png',
                  width: 45,
                  height: 45,
                ),
              ),
            ),
          ),
          title: Text(
            'Profile',
            style: TextStyle(fontSize: Common.h1, fontFamily: Common.family, color: Common.secondary),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.logout, color: Common.secondary),
              tooltip: 'Logout',
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear(); // Clear all stored data

                // Navigate to SignInAndUp screen
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const SignInAndUp()),
                );
              },
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            color: Common.primary,
            elevation: 5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: MediaQuery.of(context).size.width / 8,
                      backgroundColor: Common.light,
                      backgroundImage: _profileImageProvider,
                      child: _profileImageProvider == null
                          ? Icon(Icons.camera_alt, color: Common.secondary)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow("Store Name", name),
                  _buildInfoRow("Store Category", category),
                  _buildInfoRow("Address", address),
                  _buildInfoRow("Mobile No", phone),
                  _buildInfoRow("Email", email),
                  _buildInfoRow("GST No", gst),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditStorePage(
                            name: name,
                            category: category,
                            address: address,
                            phone: phone,
                            gst: gst,
                            email: email,
                            shopId: widget.shopId,
                          ),
                        ),
                      ).then((value) {
                        if (value == true) _loadStoreData();
                      });
                    },
                    child: const Text("Edit"),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PaymentPage(shopId: widget.shopId),
                        ),
                      );
                    },
                    icon: Icon(Icons.currency_rupee),
                    label: const Text("Payment"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class EditStorePage extends StatefulWidget {
  final String name, category, address, phone, gst, email, shopId;

  const EditStorePage({
    super.key,
    required this.name,
    required this.category,
    required this.address,
    required this.phone,
    required this.gst,
    required this.email,
    required this.shopId,
  });

  @override
  State<EditStorePage> createState() => _EditStorePageState();
}

class _EditStorePageState extends State<EditStorePage> {
  late TextEditingController _nameController;
  late TextEditingController _categoryController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _gstController;

  bool _loading = false;
  final ImagePicker _picker = ImagePicker();
  File? _shopLogo;
  double progress = 0.0;

  Future<String> uploadImage(File file, String path) async {
    final storageRef = FirebaseStorage.instance.ref().child(path);
    final uploadTask = storageRef.putFile(file);

    uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
      setState(() {
        progress = snapshot.bytesTransferred / snapshot.totalBytes;
      });
    });

    await uploadTask;
    return await storageRef.getDownloadURL();
  }

  Future<void> pickAndUploadLogo() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final file = File(pickedFile.path);

      setState(() {
        _shopLogo = file;
      });

      final fileName = "${const Uuid().v4()}_${path.basename(file.path)}";
      final uploadPath = "logos/$fileName";


      try {
        String imageUrl = await uploadImage(file, uploadPath);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('uploadedImageUrl', imageUrl);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image uploaded successfully")),
        );
      } catch (e) {
        print("Upload error: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image upload failed")),
        );
      }
    }
  }


  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _categoryController = TextEditingController(text: widget.category);
    _addressController = TextEditingController(text: widget.address);
    _phoneController = TextEditingController(text: widget.phone);
    _emailController = TextEditingController(text: widget.email);
    _gstController = TextEditingController(text: widget.gst);
  }

  Future<void> _saveDataToServer() async {
    setState(() => _loading = true);

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? imageUrl = prefs.getString('uploadedImageUrl');

    try {
      // Step 1: Fetch current data
      final currentResponse = await http.post(
        Uri.parse(Common.baseUrl + 'shop'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"shopId": widget.shopId}),
      );

      if (currentResponse.statusCode != 200) throw Exception("Fetch failed");

      final currentData = jsonDecode(currentResponse.body)['response'];
      final currentSettings = currentData['settings'];

      // Step 2: Prepare updated payload while keeping the rest intact
      final updatedPayload = {
        "shopId": widget.shopId,
        "gstNumber": _gstController.text,
        "settings": {
          "header": {
            ...currentSettings['header'],
            "shopName": _nameController.text,
            "phoneNumber": _phoneController.text,
            "email": _emailController.text,
            "logo": imageUrl ?? currentSettings['header']['logo'],
          },
          "footer": {
            ...currentSettings['footer'],
            "address": _addressController.text,
          }
        },
      };

      // Step 3: Post the update
      final updateResponse = await http.post(
        Uri.parse(Common.baseUrl + "shop/updateshop"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(updatedPayload),
      );

      if (updateResponse.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Update failed")),
        );
      }
    } catch (e) {
      print("Error updating store data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        style: TextStyle(color: Common.secondary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Common.secondary),
          border: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Common.secondary),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (){
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Common.primary,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          iconTheme: IconThemeData(
            color: Colors.black, // Change this to any color you want
          ),
          title: Text(
            'Edit Store Details',
            style: TextStyle(fontSize: Common.h1, fontFamily: Common.family, color: Common.secondary),
          ),
          // actions: [
          //   IconButton(
          //     icon: Icon(Icons.logout, color: Common.secondary),
          //     tooltip: 'Logout',
          //     onPressed: () async {
          //       final prefs = await SharedPreferences.getInstance();
          //       await prefs.clear(); // Clear all stored data
          //
          //       // Navigate to SignInAndUp screen
          //       Navigator.pushReplacement(
          //         context,
          //         MaterialPageRoute(builder: (_) => const SignInAndUp()),
          //       );
          //     },
          //   ),
          // ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              GestureDetector(
                onTap: pickAndUploadLogo,
                child: CircleAvatar(
                  radius: MediaQuery.of(context).size.width / 8,
                  backgroundColor: Common.light,
                  backgroundImage: _shopLogo != null
                      ? FileImage(_shopLogo!)
                      : null,
                  child: _shopLogo == null
                      ? Icon(Icons.camera_alt, color: Common.secondary)
                      : null,
                ),
              ),
              SizedBox(height: 10),
              _buildTextField("Store Name", _nameController),
              _buildTextField("Store Category", _categoryController),
              _buildTextField("Address", _addressController),
              _buildTextField("Mobile No", _phoneController),
              _buildTextField("Email", _emailController),
              _buildTextField("GST Number", _gstController),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveDataToServer,
                child: const Text("Update"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
