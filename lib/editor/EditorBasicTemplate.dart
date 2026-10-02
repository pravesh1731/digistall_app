// ✅ Updated Flutter code to match API's required format for team
// Replaces: "image" => "imgUrl", "position" => "role", adds "memberVisibility"

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import '../global/Common.dart';

class EditorTemplateWithStyle extends StatefulWidget {
  final bool allowHeader;
  final String shopId;

  const EditorTemplateWithStyle({super.key, this.allowHeader = true, required this.shopId,});

  @override
  State<EditorTemplateWithStyle> createState() => _EditorTemplateWithStyleState();
}

class _EditorTemplateWithStyleState extends State<EditorTemplateWithStyle> {
  bool isLoading = false;
  double progress = 0.0;

  late TextEditingController emailController;
  late TextEditingController phoneController;
  late TextEditingController shopNameController;
  late TextEditingController aboutController;
  late TextEditingController addressController;
  late TextEditingController instagramController;
  late TextEditingController facebookController;
  late TextEditingController youtubeController;

  File? _shopLogo;
  String? shopLogoUrl;

  List<Map<String, dynamic>> teamMembers = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    emailController = TextEditingController();
    phoneController = TextEditingController();
    shopNameController = TextEditingController();
    aboutController = TextEditingController();
    addressController = TextEditingController();
    instagramController = TextEditingController();
    facebookController = TextEditingController();
    youtubeController = TextEditingController();

    fetchShopData();
  }

  Future<void> fetchShopData() async {
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse(Common.baseUrl + "shop"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"shopId": widget.shopId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final settings = data["response"]["settings"];

        shopNameController.text = settings["header"]["shopName"] ?? "";
        emailController.text = settings["header"]["email"] ?? "";
        phoneController.text = settings["header"]["phoneNumber"] ?? "";
        addressController.text = settings["footer"]["address"] ?? "";
        aboutController.text = settings["footer"]["about"] ?? "";
        instagramController.text = settings["footer"]["instgramUrl"] ?? "";
        facebookController.text = settings["footer"]["facebookUrl"] ?? "";
        youtubeController.text = settings["footer"]["youtubeUrl"] ?? "";

        shopLogoUrl = settings["header"]["logo"];
        teamMembers = List<Map<String, dynamic>>.from(settings["team"] ?? []);
      } else {
        print("Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Fetch error: $e");
    }
    setState(() => isLoading = false);
  }

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

  Future<void> pickShopLogo() async {
    final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _shopLogo = File(pickedFile.path);
      });
    }
  }

  Future<void> addTeamMember() async {
    TextEditingController name = TextEditingController();
    TextEditingController position = TextEditingController();
    File? imageFile;
    String? imageUrl;
    bool uploading = false;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Add Team Member"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
                  if (file != null) {
                    imageFile = File(file.path);
                    setState(() => uploading = true);
                    imageUrl = await uploadImage(
                      imageFile!,
                      'team/${DateTime.now().millisecondsSinceEpoch}.png',
                    );
                    setState(() => uploading = false);
                  }
                },
                child: CircleAvatar(
                  radius: 30,
                  backgroundImage: imageFile != null ? FileImage(imageFile!) : null,
                  child: imageFile == null ? const Icon(Icons.add_a_photo) : null,
                ),
              ),
              if (uploading)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text("Uploading image...", style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: position, decoration: const InputDecoration(labelText: 'Position')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                if (imageUrl != null && name.text.trim().isNotEmpty && position.text.trim().isNotEmpty) {
                  setState(() {
                    teamMembers.add({
                      "imgUrl": imageUrl, // updated key
                      "name": name.text.trim(),
                      "role": position.text.trim(), // updated key
                      "memberVisibility": true, // added
                    });
                  });
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please complete all fields and upload an image.")),
                  );
                }
              },
              child: const Text("Add"),
            ),
          ],
        ),
      ),
    );
  }

  void onSave() async {
    setState(() {
      isLoading = true;
      progress = 0.1;
    });

    if (_shopLogo != null) {
      shopLogoUrl = await uploadImage(
        _shopLogo!,
        'shop-logos/${DateTime.now().millisecondsSinceEpoch}.png',
      );
    }

    setState(() => progress = 0.9);

    final Map<String, dynamic> data = {
      "shopId": widget.shopId,
      "settings": {
        "header": {
          "logo": shopLogoUrl,
          "shopName": shopNameController.text,
          "email": emailController.text,
          "phoneNumber": phoneController.text,
          "isShopNameVisible": true,
          "tagline": "We Provide The Best Service",
          "isTaglineVisible": false,
        },
        "footer": {
          "address": addressController.text,
          "facebookUrl": facebookController.text,
          "instgramUrl": instagramController.text,
          "youtubeUrl": youtubeController.text,
          "about": aboutController.text,
          "isAddressVisible": true,
          "isSocialSitesVisible": true,
          "copyrightMessage": "(c) ALL RIGHTS RESERVED | HRI"
        },
        "team": teamMembers,
        "termsAndConditions": {
          "termsAndConditions": "NO Terms & Cunditions.",
          "msmeCertificate": "www.blankpage.com"
        },
        "welcomeBanner": {
          "welcomeTitle": "Welcome To Our Store",
          "bannerImages": [
            "https://res.cloudinary.com/aguruprasad/image/upload/v1670315929/woodline/product-images/Rectangle_35_f4ki6o.png"
          ]
        },
        "buttonsDiscription":
        "We are a small brand dedicated to get the quality you deserve. From Our Sustainable Supply Chain, To Your Sustainable Wardrobe, We will Create Your Environmental Designs With Care.",
        "buttons": []
      }
    };

    try {
      final response = await http.post(
        Uri.parse(Common.baseUrl + "shop/updateshop"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Shop data updated successfully!")),
        );
      } else {
        print("Update failed: ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${response.statusCode}")),
        );
      }
    } catch (e) {
      print("Update error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network error! Please try again.")),
      );
    }

    setState(() {
      isLoading = false;
      progress = 1.0;
    });
  }

  @override
  void dispose() {
    emailController.dispose();
    phoneController.dispose();
    shopNameController.dispose();
    aboutController.dispose();
    addressController.dispose();
    instagramController.dispose();
    facebookController.dispose();
    youtubeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Common.primary,
        elevation: 0,
        toolbarHeight: 60,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Center(
            child: Image.asset('assets/Icons/logo.png', width: 45, height: 45),
          ),
        ),
        title: Text(
          'Store Editor',
          style: TextStyle(
            fontSize: Common.title,
            color: Common.secondary,
            fontWeight: FontWeight.w600,
            fontFamily: Common.family,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(Icons.design_services, color: Common.secondary),
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Common.secondary),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading shop information...',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop Logo Card
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    decoration: BoxDecoration(
                      color: Common.primary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: pickShopLogo,
                            child: Container(
                              height: 120,
                              width: 120,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                                image: (_shopLogo != null || shopLogoUrl != null)
                                    ? DecorationImage(
                                        image: _shopLogo != null
                                            ? FileImage(_shopLogo!)
                                            : NetworkImage(shopLogoUrl!) as ImageProvider,
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: (_shopLogo == null && shopLogoUrl == null)
                                  ? Icon(
                                      Icons.add_a_photo,
                                      size: 40,
                                      color: Common.secondary.withOpacity(0.8),
                                    )
                                  : Stack(
                                      children: [
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Common.secondary,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.edit,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Shop Logo',
                            style: TextStyle(
                              fontSize: 16,
                              color: Common.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tap to change',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),

                  // Main content wrapped in Padding
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Shop Information Section
                        _buildSectionHeader('Shop Information'),
                        _buildCard([
                          _buildTextField(
                            controller: shopNameController,
                            label: "Shop Name",
                            icon: Icons.store,
                          ),
                          _buildTextField(
                            controller: aboutController,
                            label: "About",
                            icon: Icons.info_outline,
                            maxLines: 3,
                          ),
                          _buildTextField(
                            controller: addressController,
                            label: "Address",
                            icon: Icons.location_on_outlined,
                            maxLines: 2,
                          ),
                        ]),
                        
                        SizedBox(height: 24),
                        
                        // Contact Information Section
                        _buildSectionHeader('Contact Information'),
                        _buildCard([
                          _buildTextField(
                            controller: emailController,
                            label: "Email",
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          _buildTextField(
                            controller: phoneController,
                            label: "Phone",
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                        ]),
                        
                        SizedBox(height: 24),
                        
                        // Social Media Section
                        _buildSectionHeader('Social Media'),
                        _buildCard([
                          _buildTextField(
                            controller: instagramController,
                            label: "Instagram URL",
                            icon: Icons.camera_alt_outlined,
                          ),
                          _buildTextField(
                            controller: facebookController,
                            label: "Facebook URL",
                            icon: Icons.facebook_outlined,
                          ),
                          _buildTextField(
                            controller: youtubeController,
                            label: "YouTube URL",
                            icon: Icons.play_circle_outline,
                          ),
                        ]),
                        
                        SizedBox(height: 24),
                        
                        // Team Members Section
                        _buildSectionHeader('Team Members'),
                        
                        // Add team member button
                        Container(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: addTeamMember,
                            icon: Icon(Icons.person_add_alt),
                            label: Text("Add New Team Member"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Common.secondary,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                        
                        SizedBox(height: 16),
                        
                        // Team members grid
                        teamMembers.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Text(
                                    'No team members added yet',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ),
                              )
                            : GridView.builder(
                                physics: NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.8,
                                ),
                                itemCount: teamMembers.length,
                                itemBuilder: (context, index) {
                                  final member = teamMembers[index];
                                  return Card(
                                    elevation: 3,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: Stack(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            children: [
                                              CircleAvatar(
                                                radius: 40,
                                                backgroundImage: NetworkImage(member["imgUrl"]),
                                                backgroundColor: Colors.grey[200],
                                              ),
                                              SizedBox(height: 12),
                                              Text(
                                                member["name"],
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                member["role"],
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 14,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Delete button
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                teamMembers.removeAt(index);
                                              });
                                            },
                                            child: Container(
                                              padding: EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.red[50],
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: Colors.red[700],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: isLoading ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: Common.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: isLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text("Saving...", style: TextStyle(fontSize: 16)),
                      ],
                    )
                  : Text("Save Changes", style: TextStyle(fontSize: 16,color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Common.secondary,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: children
              .expand((widget) => [widget, SizedBox(height: 16)])
              .toList()
            ..removeLast(),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Common.secondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Common.secondary),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: maxLines > 1 ? 16 : 0,
        ),
      ),
    );
  }

  // ...existing methods like fetchShopData(), uploadImage(), etc...
}
