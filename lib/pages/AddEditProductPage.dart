import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import '../../global/common.dart';

class AddEditProductPage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic>? productToEdit;

  const AddEditProductPage({Key? key, required this.shopId, this.productToEdit}) : super(key: key);

  @override
  State<AddEditProductPage> createState() => _AddEditProductPageState();
}

class _AddEditProductPageState extends State<AddEditProductPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _discountPriceController = TextEditingController();
  final TextEditingController _ribbonController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _unitTypeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String? _selectedCategory;
  List<String> _categories = [];
  final List<String> unitOptions = [
    "piece", "kg", "gm", "ml", "liter", "mm", "ft", "meter", "sq-ft",
    "km", "hours", "day", "month", "year", "packet", "minute",
    "ton", "capsule", "inch", "mg"
  ];
  String? _selectedUnitType;

  bool _isUploading = false;
  List<String> _imageUrls = [];
  bool _productVisibility = true;
  Map<String, dynamic>? _originalProduct; // snapshot for diff

  @override
  void initState() {
    super.initState();
    _fetchCategories();
    if (widget.productToEdit != null) {
      _nameController.text = widget.productToEdit!["productName"] ?? "";
      _priceController.text = widget.productToEdit!["productPrice"].toString();
      _discountPriceController.text =
          (widget.productToEdit!["productdiscountPrice"] ??
              widget.productToEdit!["productDiscountPrice"] ??
              0).toString();
      _ribbonController.text = widget.productToEdit!["productRibbon"] ?? "";
      _descController.text = widget.productToEdit!["productDescription"] ?? "";
      _stockController.text = widget.productToEdit!["productUnits"].toString();
      // _unitTypeController.text = widget.productToEdit!["productUnitType"] ?? "";
      _selectedUnitType = widget.productToEdit!["productUnitType"];
      _unitTypeController.text = _selectedUnitType ?? '';
      _selectedCategory = widget.productToEdit!["productCategory"];
      _imageUrls = List<String>.from(widget.productToEdit!["productImages"] ?? []);
      _productVisibility = widget.productToEdit!["productVisibility"] ?? true;
      _originalProduct = Map<String, dynamic>.from(widget.productToEdit!);
    }
  }

  Future<void> _fetchCategories() async {
    final url = "${Common.baseUrl}shop";
    final response = await http.post(
      Uri.parse(url),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"shopId": widget.shopId}),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> categories = data['response']['categorys'];

      setState(() {
        _categories = categories.map<String>((cat) => cat['categoryName'].toString()).toList();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to fetch categories")),
      );
    }
  }


  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _isUploading = true);
      try {
        final fileName = "products-${widget.shopId}-${DateTime.now().millisecondsSinceEpoch}.png";
        final storageRef = FirebaseStorage.instance.ref().child(fileName);
        await storageRef.putFile(File(picked.path));
        final downloadUrl = await storageRef.getDownloadURL();
        setState(() {
          _imageUrls.add(downloadUrl);
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator ??
          (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            return null;
          },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon) : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Common.secondary, width: 1.2),
        ),
      ),
    );
  }

  Widget _buildUnitDropdown() {
    return DropdownButtonFormField<String>(
      isExpanded: true, // prevents right-side pixel overflow
      value: _selectedUnitType,
      items: unitOptions
          .map((u) => DropdownMenuItem(
                value: u,
                child: Text(u, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (val) {
        setState(() {
          _selectedUnitType = val;
          _unitTypeController.text = val ?? '';
        });
      },
      decoration: InputDecoration(
        labelText: "Unit", // ensured label is exactly "Unit"
        prefixIcon: const Icon(Icons.widgets_outlined),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Common.secondary, width: 1.2),
        ),
      ),
      validator: (v) => v == null ? "Required" : null,
    );
  }

  void _generateDescription() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter product name first")),
      );
      return;
    }
    final name = _nameController.text.trim();
    final cat = _selectedCategory ?? "general";
    final ribbon = _ribbonController.text.trim();
    final price = _priceController.text.trim();
    final unit = _selectedUnitType ?? "";
    final stock = _stockController.text.trim();

    final generated = StringBuffer()
      ..write("$name")
      ..write(ribbon.isNotEmpty ? " • $ribbon." : ".")
      ..write(" A quality $cat product")
      ..write(price.isNotEmpty ? " priced at ₹$price" : "")
      ..write(unit.isNotEmpty ? " per $unit" : "")
      ..write(stock.isNotEmpty ? " (Stock: $stock)." : ".")
      ..write(" Carefully selected to meet your needs.");

    setState(() {
      _descController.text = generated.toString();
    });
  }

  Map<String, dynamic> _diffProduct(Map<String, dynamic> newData) {
    if (_originalProduct == null) return newData;
    final diff = <String, dynamic>{};
    newData.forEach((k, v) {
      final old = _originalProduct![k];
      if (old is List && v is List) {
        if (old.join('|') != v.join('|')) diff[k] = v;
      } else if (old != v) {
        diff[k] = v;
      }
    });
    return diff;
  }

  bool _isSuccess(int code) => code == 200 || code == 201 || code == 202;

  Future<void> _submitProduct() async {
    if (_isUploading) return;
    if (!_formKey.currentState!.validate() ||
        _selectedCategory == null ||
        _selectedUnitType == null ||
        _imageUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complete all fields & add at least one image")),
      );
      return;
    }

    setState(() => _isUploading = true);

    final discountVal = int.tryParse(_discountPriceController.text) ?? 0;

    final productData = {
      "productName": _nameController.text.trim(),
      "productPrice": int.tryParse(_priceController.text) ?? 0,
      "productdiscountPrice": discountVal,        // backend canonical key
      "productDiscountPrice": discountVal,        // alternate (kept for safety)
      "productRibbon": _ribbonController.text.trim(),
      "productDescription": _descController.text.trim(),
      "productUnits": int.tryParse(_stockController.text) ?? 0,
      "productUnitType": _selectedUnitType,
      "productCategory": _selectedCategory,
      "productImages": _imageUrls,
      "productVisibility": _productVisibility,
      "hasVariants": false,
      "productHSN": "",
    };

    // For edit include identifiers
    final productToSend = widget.productToEdit == null
        ? productData
        : {
            "_id": widget.productToEdit!["_id"],
            "productId": widget.productToEdit!["productId"],
            ...productData,
          };

    final bool isNew = widget.productToEdit == null;
    final String url = isNew
        ? "${Common.baseUrl}shop/addproduct"
        : "${Common.baseUrl}shop/updateproduct";

    final payload = {
      "shopId": widget.shopId,
      "product": productToSend,
    };

    debugPrint("Submitting (${isNew ? 'CREATE' : 'UPDATE'}) -> $url");
    debugPrint("Payload: ${jsonEncode(payload)}");

    http.Response? response;
    try {
      // Always use POST for both create and update
      response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      debugPrint("Response ${response.statusCode}: ${response.body}");
    } catch (e) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Network error: $e")));
      return;
    }

    setState(() => _isUploading = false);

    if ([200, 201, 202].contains(response.statusCode)) {
      if (!isNew) {
        _originalProduct = {
          ...?_originalProduct,
          ...productData,
        };
      }
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isNew ? "Product added" : "Product updated")),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Failed (${response.statusCode}): ${response.body}",
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom; // keyboard height
    return Scaffold(
      resizeToAvoidBottomInset: true, // allow body to resize with keyboard
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Common.primary.withOpacity(.95), Common.primary.withOpacity(.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar replacement (keeps original logic)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: Common.secondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.productToEdit == null ? "Add Product" : "Edit Product",
                      style: TextStyle(
                        color: Common.secondary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  // was EdgeInsets.fromLTRB(12, 0, 12, 150),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  child: Form(
                    key: _formKey,
                    child: Card(
                      elevation: 6,
                      shadowColor: Colors.black26,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        // ...existing padding...
                        padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Images
                            Text(
                              "Images",
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: Colors.grey[800]),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                ..._imageUrls.map(
                                  (url) => Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          width: 105,
                                          height: 105,
                                          color: Colors.grey[200],
                                          child: Image.network(
                                            url,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: -6,
                                        right: -6,
                                        child: Material(
                                          color: Colors.redAccent,
                                          shape: const CircleBorder(),
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: () {
                                              setState(() {
                                                _imageUrls.remove(url);
                                              });
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(Icons.close,
                                                  size: 16, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _isUploading ? null : _pickAndUploadImage,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    width: 105,
                                    height: 105,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                        width: 1.2,
                                      ),
                                      color: Colors.white,
                                    ),
                                    child: _isUploading
                                        ? const Center(
                                            child: SizedBox(
                                              width: 30,
                                              height: 30,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                              ),
                                            ),
                                          )
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: const [
                                              Icon(Icons.add_photo_alternate,
                                                  size: 32, color: Colors.grey),
                                              SizedBox(height: 6),
                                              Text("Add",
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey)),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            _buildTextField(
                              controller: _nameController,
                              label: "Product Name",
                              icon: Icons.inventory_2_outlined,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _priceController,
                                    label: "Price",
                                    icon: Icons.sell_outlined,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  // Replaced to allow smaller label text
                                  child: TextFormField(
                                    controller: _discountPriceController,
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) return 'Required';
                                      return null;
                                    },
                                    decoration: InputDecoration(
                                      labelText: "Discount price",
                                      labelStyle: const TextStyle(fontSize: 14), // smaller label
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Colors.transparent),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(color: Colors.transparent),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide(
                                          color: Common.secondary,
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _ribbonController,
                              label: "Ribbon (e.g. Best Seller)",
                              icon: Icons.flag_outlined,
                            ),
                            const SizedBox(height: 14),
                            _buildTextField(
                              controller: _descController,
                              label: "Description",
                              icon: Icons.description_outlined,
                              maxLines: 4,
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _isUploading ? null : _generateDescription,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.blue, // changed to red background
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.auto_awesome, size: 16),
                                label: const Text(
                                  "Generate Description",
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _stockController,
                                    label: "Stock",
                                    icon: Icons.storage_rounded,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // FIX: replaced inline DropdownButtonFormField with styled helper to remove pixel overflow
                                Expanded(child: _buildUnitDropdown()),
                              ],
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              value: _selectedCategory,
                              items: _categories
                                  .map((cat) => DropdownMenuItem(
                                      value: cat, child: Text(cat)))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedCategory = val),
                              decoration: InputDecoration(
                                labelText: "Category",
                                prefixIcon:
                                    const Icon(Icons.category_outlined),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (v) =>
                                  v == null ? "Select category" : null,
                            ),
                            const SizedBox(height: 10),
                            SwitchListTile(
                              // ...existing switch...
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                "Visible to Customers",
                                style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[800]),
                              ),
                              value: _productVisibility,
                              onChanged: (val) =>
                                  setState(() => _productVisibility = val),
                              activeColor: Common.secondary,
                              activeTrackColor:
                                  Common.secondary.withOpacity(0.35),
                            ),
                            const SizedBox(height: 24),
                            const Divider(height: 1),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isUploading ? null : _submitProduct,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Common.secondary,
                                  foregroundColor: Colors.white,
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(opacity: anim, child: child),
                                  child: _isUploading
                                      ? const SizedBox(
                                          key: ValueKey('loading'),
                                          height: 26,
                                          width: 26,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : Text(
                                          widget.productToEdit == null
                                              ? "Add Product"
                                              : "Update Product",
                                          key: ValueKey(widget.productToEdit == null
                                              ? 'add'
                                              : 'update'),
                                        ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: MediaQuery.of(context).viewInsets.bottom > 0
                                  ? 20
                                  : 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}