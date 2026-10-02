import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../global/Common.dart';

class PaymentPage extends StatefulWidget {
  final String shopId;
  
  const PaymentPage({super.key, required this.shopId});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  // State variables
  String qrCodeUrl = '';
  String upiId = '';
  bool codEnabled = false;
  double deliveryPrice = 20.0;
  int defaultDeliveryDate = 0;
  File? selectedQrImage;
  
  // Loading states
  bool isLoading = false;
  bool isUploading = false;
  bool editMode = false;
  
  // Popup states
  bool showDeliveryPricePopup = false;
  bool showDeliveryDatePopup = false;
  
  // Controllers
  final TextEditingController upiController = TextEditingController();
  final TextEditingController deliveryPriceController = TextEditingController();
  final TextEditingController deliveryDateController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadPaymentData();
    _fetchDeliveryPrice();
  }

  @override
  void dispose() {
    upiController.dispose();
    deliveryPriceController.dispose();
    deliveryDateController.dispose();
    super.dispose();
  }

  // Load payment data from server
  Future<void> _loadPaymentData() async {
    try {
      final response = await http.post(
        Uri.parse("${Common.baseUrl}shop"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"shopId": widget.shopId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['response'];
        setState(() {
          qrCodeUrl = data['QRCode'] ?? '';
          upiId = data['upiId'] ?? '';
          codEnabled = data['cod'] ?? false;
          defaultDeliveryDate = data['defaultDeliveryDate'] ?? 0;
          
          upiController.text = upiId;
          deliveryDateController.text = defaultDeliveryDate.toString();
        });
      }
    } catch (e) {
      print("Error loading payment data: $e");
      _showSnackBar("Failed to load payment data");
    }
  }

  // Fetch delivery price
  Future<void> _fetchDeliveryPrice() async {
    try {
      final response = await http.post(
        Uri.parse("https://backend.digistall.in/user/checkpp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"shopId": widget.shopId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['pp'] != null) {
          setState(() {
            deliveryPrice = double.parse(data['pp'].toString());
            deliveryPriceController.text = deliveryPrice.toString();
          });
        }
      }
    } catch (e) {
      print("Error fetching delivery price: $e");
    }
  }

  // Pick and upload QR image
  Future<void> _pickAndUploadQrImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );

    if (pickedFile != null) {
      setState(() {
        selectedQrImage = File(pickedFile.path);
        isUploading = true;
      });

      try {
        final fileName = "${widget.shopId}-upi-${const Uuid().v4()}";
        final ref = FirebaseStorage.instance.ref().child("profile/$fileName");
        
        await ref.putFile(selectedQrImage!);
        final downloadUrl = await ref.getDownloadURL();
        
        setState(() {
          qrCodeUrl = downloadUrl;
          isUploading = false;
        });
        
        _showSnackBar("QR code uploaded successfully");
      } catch (e) {
        setState(() {
          isUploading = false;
        });
        print("Error uploading QR: $e");
        _showSnackBar("Failed to upload QR code");
      }
    }
  }

  // Save payment changes
  Future<void> _savePaymentChanges() async {
    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("${Common.baseUrl}shop/updatepayment"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "shopId": widget.shopId,
          "QRCode": qrCodeUrl,
          "upiId": upiController.text.toLowerCase(),
          "cod": codEnabled,
        }),
      );

      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");

      if (response.statusCode == 201 || response.statusCode == 200) {
        setState(() {
          upiId = upiController.text.toLowerCase();
          editMode = false;
        });
        _showSnackBar("Payment settings updated successfully");
        // Reload data to get latest from server
        _loadPaymentData();
      } else {
        print("Failed with status: ${response.statusCode}");
        _showSnackBar("Failed to update payment settings");
      }
    } catch (e) {
      print("Error updating payment: $e");
      _showSnackBar("Something went wrong: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Update delivery price
  Future<void> _updateDeliveryPrice() async {
    try {
      final response = await http.post(
        Uri.parse("https://backend.digistall.in/user/updatepp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "shopId": widget.shopId,
          "pp": double.parse(deliveryPriceController.text),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            deliveryPrice = double.parse(deliveryPriceController.text);
            showDeliveryPricePopup = false;
          });
          _showSnackBar("Delivery price updated successfully");
        } else {
          _showSnackBar("Failed to update delivery price");
        }
      }
    } catch (e) {
      print("Error updating delivery price: $e");
      _showSnackBar("Something went wrong");
    }
  }

  // Update default delivery date
  Future<void> _updateDefaultDeliveryDate() async {
    try {
      final response = await http.post(
        Uri.parse("https://backend.digistall.in/user/updatedefaultdeliverydate"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "shopId": widget.shopId,
          "defaultDeliveryDate": int.parse(deliveryDateController.text),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['message'] == 'Expected delivery date updated successfully') {
          setState(() {
            defaultDeliveryDate = int.parse(deliveryDateController.text);
            showDeliveryDatePopup = false;
          });
          _showSnackBar("Default delivery date updated successfully");
        } else {
          _showSnackBar("Failed to update delivery date");
        }
      }
    } catch (e) {
      print("Error updating delivery date: $e");
      _showSnackBar("Something went wrong");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: Common.primary,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          iconTheme: IconThemeData(
            color: Common.secondary,
          ),
          title: Text(
            'Payment Settings',
            style: TextStyle(
              fontSize: Common.h1,
              fontFamily: Common.family,
              color: Common.secondary,
            ),
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Make sure you add the right information',
                      style: TextStyle(
                        fontSize: Common.h1,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Payment Methods Section
                  if (editMode) _buildEditMode() else _buildViewMode(),
                  
                  const SizedBox(height: 20),
                  
                  // Delivery Cost Section
                  _buildDeliveryCostSection(),
                  
                  const SizedBox(height: 16),
                  
                  // Default Delivery Date Section
                  _buildDefaultDeliveryDateSection(),
                ],
              ),
            ),
            
            // Popup overlays
            if (showDeliveryPricePopup) _buildDeliveryPricePopup(),
            if (showDeliveryDatePopup) _buildDeliveryDatePopup(),
          ],
        ),
      ),
    );
  }

  Widget _buildEditMode() {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // QR Code Section
            _buildQrCodeEditSection(),
            
            const SizedBox(height: 20),
            
            // UPI ID Section
            _buildUpiEditSection(),
            
            const SizedBox(height: 20),
            
            // COD Section
            _buildCodEditSection(),
            
            const SizedBox(height: 20),
            
            // Action Buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildViewMode() {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // QR Code Display
            _buildQrCodeViewSection(),
            
            const SizedBox(height: 20),
            
            // COD Display
            _buildCodViewSection(),
            
            const SizedBox(height: 20),
            
            // Edit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    editMode = true;
                    upiController.text = upiId;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Edit Payment Methods',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCodeEditSection() {
    return Column(
      children: [
        Text(
          'QR Code',
          style: TextStyle(
            fontSize: Common.h2,
            fontWeight: FontWeight.bold,
            color: Common.secondary,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickAndUploadQrImage,
          child: Container(
            height: 200,
            width: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 2),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade50,
            ),
            child: isUploading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 10),
                        Text('Uploading...'),
                      ],
                    ),
                  )
                : (qrCodeUrl.isNotEmpty || selectedQrImage != null)
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: selectedQrImage != null
                            ? Image.file(selectedQrImage!, fit: BoxFit.cover)
                            : Image.network(qrCodeUrl, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            size: 40,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Update Your new QR code',
                            style: TextStyle(color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpiEditSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter your UPI ID',
          style: TextStyle(
            fontSize: Common.h2,
            fontWeight: FontWeight.bold,
            color: Common.secondary,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: upiController,
          decoration: InputDecoration(
            hintText: 'example@upi',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          onChanged: (value) {
            upiController.text = value.toLowerCase();
            upiController.selection = TextSelection.fromPosition(
              TextPosition(offset: upiController.text.length),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCodEditSection() {
    return Row(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.local_shipping,
            size: 40,
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cash on Delivery',
                style: TextStyle(
                  fontSize: Common.h2,
                  fontWeight: FontWeight.bold,
                  color: Common.secondary,
                ),
              ),
              const SizedBox(height: 10),
              Switch(
                value: codEnabled,
                onChanged: (value) {
                  setState(() {
                    codEnabled = value;
                  });
                },
                activeColor: Colors.blue,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                editMode = false;
                selectedQrImage = null;
                upiController.text = upiId;
                codEnabled = codEnabled; // Reset to original value
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade300,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: isLoading ? null : _savePaymentChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Save'),
          ),
        ),
      ],
    );
  }

  Widget _buildQrCodeViewSection() {
    return Column(
      children: [
        Container(
          height: 200,
          width: 200,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300, width: 2),
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey.shade50,
          ),
          child: qrCodeUrl.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(qrCodeUrl, fit: BoxFit.cover),
                )
              : Center(
                  child: Text(
                    'No QR code available',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
        ),
        const SizedBox(height: 10),
        Text(
          'UPI ID',
          style: TextStyle(
            fontSize: Common.h3,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          upiId.isNotEmpty ? upiId : 'Not set',
          style: TextStyle(
            fontSize: Common.h2,
            fontWeight: FontWeight.bold,
            color: Common.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCodViewSection() {
    return Row(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.local_shipping,
            size: 40,
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cash on Delivery',
                style: TextStyle(
                  fontSize: Common.h2,
                  fontWeight: FontWeight.bold,
                  color: Common.secondary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                codEnabled ? 'Available' : 'Not Available',
                style: TextStyle(
                  fontSize: Common.h3,
                  color: codEnabled ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveryCostSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.local_offer,
              color: Colors.blue.shade600,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Delivery Cost',
              style: TextStyle(
                fontSize: Common.h2,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '₹${deliveryPrice.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: Common.h2,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                showDeliveryPricePopup = true;
                deliveryPriceController.text = deliveryPrice.toString();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Icon(
                Icons.edit,
                size: 20,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultDeliveryDateSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.date_range,
              color: Colors.green.shade600,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Default Delivery Date',
              style: TextStyle(
                fontSize: Common.h2,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              defaultDeliveryDate > 0 ? '$defaultDeliveryDate days' : 'Not set',
              style: TextStyle(
                fontSize: Common.h2,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                showDeliveryDatePopup = true;
                deliveryDateController.text = defaultDeliveryDate.toString();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Icon(
                Icons.edit,
                size: 20,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryPricePopup() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter Delivery Cost per Order',
                style: TextStyle(
                  fontSize: Common.h1,
                  fontWeight: FontWeight.bold,
                  color: Common.secondary,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: deliveryPriceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: 'Enter amount',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          showDeliveryPricePopup = false;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.grey.shade800,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _updateDeliveryPrice,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryDatePopup() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Set Default Delivery Date',
                style: TextStyle(
                  fontSize: Common.h1,
                  fontWeight: FontWeight.bold,
                  color: Common.secondary,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: deliveryDateController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: 'Number of days after order',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          showDeliveryDatePopup = false;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.grey.shade800,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _updateDefaultDeliveryDate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}