import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../global/Common.dart';
import '../pages/AddEditProductPage.dart';
import '../utils/bottomSnackBar.dart';

class CataloguePage extends StatefulWidget {
  final String shopId;
  final List<dynamic> categories;

  const CataloguePage({
    super.key,
    required this.shopId,
    required this.categories,
  });

  @override
  State<CataloguePage> createState() => _CataloguePageState();
}

class _CataloguePageState extends State<CataloguePage> {
  late List<dynamic> _categories;
  List<dynamic> _products = [];

  bool _loading = true;
  String selectedStatus = 'Categories'; // default
  bool _isLoading = true;

  File? qrCodeImage;
  bool _uploading = false;
  String? qrCodeDownloadUrl;

  @override
  void initState() {
    super.initState();
    fetchCategories();

    _categories = widget.categories;
    print('catego');
    print(_categories);
  }

  Future<void> fetchCategories() async {
    final res = await http.post(
      Uri.parse('${Common.baseUrl}shop'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"shopId": widget.shopId}),
    );

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      setState(() {
        _categories = decoded['response']['categorys'] ?? [];
        _isLoading = false;
        _loading = false;
      });
    } else {
      debugPrint('Failed to load shop: ${res.body}');
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleCategoryVisibility(int index) async {
    final category = _categories[index];
    final updatedCategory = {
      ...category,
      'categoryVisibility': !(category['categoryVisibility'] ?? false),
    };

    final payload = {
      "shopId": widget.shopId,
      "category": updatedCategory,
    };

    final response = await http.post(
      Uri.parse('${Common.baseUrl}shop/updatecategory'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      setState(() {
        _categories[index] = updatedCategory;
      });

      final prefs = await SharedPreferences.getInstance();
      prefs.setString('shopCategory', jsonEncode(_categories));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category visibility updated')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: ${response.body}')),
      );
    }
  }

  Future<void> _toggleProductVisibility(int index) async {
    final product = _products[index];

    final updatedProduct = {
      ...product,
      'productVisibility': !(product['productVisibility'] ?? false),
    };

    final response = await http.post(
      Uri.parse('${Common.baseUrl}shop/updateproduct'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "shopId": widget.shopId,
        "product": updatedProduct,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 202) {
      setState(() {
        _products[index] = updatedProduct;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Product visibility updated")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update: ${response.body}")),
      );
    }
  }


  Future<void> deleteCategory(String id, String name) async {
    print('check');
    print(id);
    final response = await http.delete(
      Uri.parse(Common.baseUrl + 'shop/deletecategory'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "shopId": widget.shopId,
        "categoryId": id,
        "categoryName": name,
      }),
    );

    if (response.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Deleted $name")),
      );
      fetchCategories(); // refresh list
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete $name")),
      );
    }
  }

  Future<void> _showAddCategoryDialog({Map<String, dynamic>? categoryToEdit}) async {
    final TextEditingController nameController = TextEditingController(
      text: categoryToEdit != null ? categoryToEdit['categoryName'] : '',
    );

    String? selectedGstValue = categoryToEdit != null ? categoryToEdit['gst'].toString() : null;
    XFile? localImageFile;
    bool localUploading = false;
    String? localQrCodeUrl = categoryToEdit != null ? categoryToEdit['categoryImg'] : null;

    const gstOptions = ['0', '0.1', '0.25', '3', '5', '6', '7.5', '12', '18', '28'];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> pickImageAndUpload() async {
              final ImagePicker picker = ImagePicker();
              final picked = await picker.pickImage(source: ImageSource.gallery);
              if (picked != null) {
                setState(() => localUploading = true);
                try {
                  final storageRef = FirebaseStorage.instance
                      .ref()
                      .child("category_qrcodes/${DateTime.now().millisecondsSinceEpoch}.png");
                  await storageRef.putFile(File(picked.path));
                  final downloadUrl = await storageRef.getDownloadURL();

                  setState(() {
                    localImageFile = picked;
                    localQrCodeUrl = downloadUrl;
                  });
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Upload failed: $e")),
                  );
                } finally {
                  setState(() => localUploading = false);
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: Common.primary,
              title: Text(
                categoryToEdit == null ? "Add Category" : "Edit Category",
                style: TextStyle(color: Common.secondary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: localUploading ? null : pickImageAndUpload,
                          icon: const Icon(Icons.upload),
                          label: Text(localUploading ? "Uploading..." : "Upload Image"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Common.secondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (localQrCodeUrl != null)
                          const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Category Name',
                        labelStyle: TextStyle(color: Common.secondary),
                      ),
                      style: TextStyle(color: Common.secondary),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedGstValue,
                      items: gstOptions.map((value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text('GST @ $value%', style: TextStyle(color: Common.secondary)),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => selectedGstValue = value),
                      decoration: InputDecoration(
                        labelText: 'Select GST',
                        labelStyle: TextStyle(color: Common.secondary),
                      ),
                      dropdownColor: Colors.white,
                      style: const TextStyle(color: Colors.black),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel", style: TextStyle(color: Common.secondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();

                    if (name.isNotEmpty && selectedGstValue != null && localQrCodeUrl != null) {
                      final categoryData = {
                        "categoryImg": localQrCodeUrl,
                        "categoryName": name,
                        "gst": selectedGstValue,
                      };

                      final payload = {
                        "shopId": widget.shopId,
                        "category": categoryToEdit != null
                            ? {
                          ...categoryToEdit,
                          ...categoryData
                        }
                            : categoryData,
                      };

                      final url = categoryToEdit == null
                          ? "${Common.baseUrl}shop/addcategory"
                          : "${Common.baseUrl}shop/updatecategory";

                      try {
                        final response = await http.post(
                          Uri.parse(url),
                          headers: {"Content-Type": "application/json"},
                          body: jsonEncode(payload),
                        );

                        if (response.statusCode == 201 || response.statusCode == 200) {
                          Navigator.pop(context);
                          fetchCategories();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(categoryToEdit == null
                                  ? "Category added successfully"
                                  : "Category updated successfully"),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Failed: ${response.statusCode}")),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error: $e")),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("All fields are required")),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Common.secondary,
                  ),
                  child: Text(categoryToEdit == null ? "Add" : "Update"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> fetchProducts() async {
    final response = await http.post(
      Uri.parse('${Common.baseUrl}shop'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"shopId": widget.shopId}),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      setState(() {
        _products = decoded['response']['products'] ?? [];
      });
    } else {
      print("Failed to load products: ${response.body}");
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Common.primary,
      appBar: AppBar(
        backgroundColor: Common.primary,
        toolbarHeight: 60,
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
        actions: [
          GestureDetector(
            // onTap:
            //     () async => {
            //   setState(() {
            //     _isLoading = true;
            //   }),
            //   filterRides(),
            // },
            child: Padding(
              padding: const EdgeInsets.only(right: 15.0),
              child: Image.asset(
                'assets/Icons/info.png',
                width: 24,
                height: 24,
              ),
            ),
          ),
        ],
        title: Text(
          // widget.shopId+'.digistall.in',
          'Catalogue',
          style: TextStyle(
            fontSize: Common.title,
            color: Common.secondary,
            fontFamily: Common.family,
            // fontWeight: Common.weight,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 5,),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(width: 15,),
                buildStatusFilterButton('Categories'),
                buildStatusFilterButton('Products'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : selectedStatus == 'Categories'
                ? _buildCategoriesView()
                : selectedStatus == 'Products'
                ? _buildProductsView()
                : _buildBulkView(),
          ),
        ],
      )
    );
  }

  Widget _buildProductsView() {
    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.65,
          ),
          itemCount: _products.length + 1,
          itemBuilder: (context, index) {
            if (index == _products.length) {
              // Add Product Card
              return GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddEditProductPage(shopId: widget.shopId),
                    ),
                  );
                  if (result == true) fetchProducts();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Common.secondary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 40, color: Colors.white),
                        SizedBox(height: 8),
                        Text(
                          "Add a Product",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final product = _products[index];
            final isVisible = product['productVisibility'] ?? false;

            return Card(
              color: Common.light,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ClipOval(
                        child: (product['productImages'] != null &&
                            product['productImages'] is List &&
                            product['productImages'].isNotEmpty)
                            ? FadeInImage.assetNetwork(
                          placeholder: '', // transparent or empty asset
                          image: product['productImages'][0],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          placeholderErrorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            color: Common.secondary,
                          ),
                          imageErrorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            color: Common.secondary,
                          ),
                        )
                            : CircleAvatar(
                          radius: 40,
                          backgroundColor: Common.secondary,
                          child: const Icon(Icons.image_not_supported, size: 35),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product['productName'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Switch(
                          value: isVisible,
                          onChanged: (_) => _toggleProductVisibility(index),
                          activeColor: Common.secondary,
                        ),

                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "${product['productUnits']} ${product['productUnitType']}",
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          "In Stock",
                          style: TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          "₹${product['productdiscountPrice']}",
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          "₹${product['productPrice']}",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => deleteProduct(product),
                            icon: const Icon(Icons.delete, size: 16),
                            label: const Text("Delete", overflow: TextOverflow.ellipsis),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddEditProductPage(
                                    shopId: widget.shopId,
                                    productToEdit: product,
                                  ),
                                ),
                              );
                              if (result == true) fetchProducts();
                            },
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text("Edit", overflow: TextOverflow.ellipsis),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }


  Widget _buildBulkView() {
    return const Center(
      child: Text("Bulk Upload Coming Soon", style: TextStyle(color: Colors.white)),
    );
  }


  Widget _buildCategoriesView() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: _categories.length + 1, // +1 for the Add Card
      itemBuilder: (context, index) {
        if (index == _categories.length) {
          // Add Category Card
          return GestureDetector(
            onTap: () => _showAddCategoryDialog(),
            child: Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Common.secondary
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 36, color: Common.primary),
                    SizedBox(height: 8),
                    Text("Add a Category",
                        style: TextStyle(color: Common.primary, fontSize: 16)),
                  ],
                ),
              ),
            ),
          );
        }

        // Normal Category Card
        final category = _categories[index];
        final isVisible = category['categoryVisibility'] ?? false;

        return Card(
          color: Common.light,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Image.network(
                  category['categoryImg'],
                  height: 80,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 48),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        category['categoryName'] ?? 'Unnamed',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isVisible ? 'Visible' : 'Hidden',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),

                    Switch(
                      value: isVisible,
                      onChanged: (_) => _toggleCategoryVisibility(index),
                      activeColor: Common.secondary,
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showAddCategoryDialog(categoryToEdit: category),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text("Edit", overflow: TextOverflow.ellipsis),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => deleteCategory(
                          category['categoryId'],
                          category['categoryName'],
                        ),
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text("Delete", overflow: TextOverflow.ellipsis),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

              ],
            ),
          ),
        );
      },
    );
  }


  Widget buildStatusFilterButton(String status) {
    final isSelected = selectedStatus == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(status),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            selectedStatus = status;
            _isLoading = true;
          });

          if (status == 'Products') {
            fetchProducts().then((_) {
              setState(() => _isLoading = false);
            });
          } else if (status == 'Categories') {
            fetchCategories().then((_) {
              setState(() => _isLoading = false);
            });
          } else {
            // bulk: You can add logic for bulk here if needed
            setState(() => _isLoading = false);
          }
        },
        checkmarkColor: Common.secondary,
        selectedColor: Common.background,
        labelStyle: TextStyle(
          color: Common.secondary,
          fontFamily: Common.family,
          fontSize: Common.h3,
          fontWeight: Common.weight,
        ),
        backgroundColor: Common.light,
      ),
    );
  }

  Future<void> deleteProduct(Map<String, dynamic> product) async {
    // Show confirmation dialog first
    final bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Product'),
          content: Text('Are you sure you want to delete "${product['productName']}"? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    ) ?? false;
    
    if (!confirm) return;

    // Prepare the request payload
    final payload = {
      "shopId": widget.shopId,
      "productId": product['productId'],
      "_id": product['_id'],
    };

    try {
      final response = await http.delete(
        Uri.parse('${Common.baseUrl}shop/deleteproduct'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201) {
        // Remove from local list and update UI
        setState(() {
          _products.removeWhere((p) => p['_id'] == product['_id']);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${product['productName']} deleted successfully')),
        );
      } else {
        // Handle error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}


