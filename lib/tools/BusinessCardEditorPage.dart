import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../global/Common.dart';

class BusinessCardEditorPage extends StatefulWidget {
  final String templateImagePath;

  const BusinessCardEditorPage({super.key, required this.templateImagePath});

  @override
  State<BusinessCardEditorPage> createState() => _BusinessCardEditorPageState();
}

class _BusinessCardEditorPageState extends State<BusinessCardEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final picker = ImagePicker();

  Uint8List? _logoBytes;

  final TextEditingController _businessName = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _website = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _address = TextEditingController();

  Future<void> _pickLogo() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _logoBytes = bytes);
    }
  }

  Future<void> _generatePDF() async {
    final doc = pw.Document();

    final templateBytes = await rootBundle.load(widget.templateImagePath);
    final templateImage = pw.MemoryImage(templateBytes.buffer.asUint8List());





    final logoImage = _logoBytes != null ? pw.MemoryImage(_logoBytes!) : null;

    if(widget.templateImagePath == 'assets/images/Card2_template.png'){
      final callIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/call.png')).buffer.asUint8List());
      final emailIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/globe.png')).buffer.asUint8List());
      final webIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/email.png')).buffer.asUint8List());
      final locationIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/map.png')).buffer.asUint8List());
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) {
            return pw.Stack(
              children: [
                pw.Positioned.fill(child: pw.Image(templateImage, fit: pw.BoxFit.cover)),

                // Info section on left
                pw.Positioned(
                  left: 40,
                  top: 100,
                  child: pw.Container(
                      width: PdfPageFormat.a4.landscape.width / 2 - 80,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            _businessName.text,
                            style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                          ),
                          pw.SizedBox(height: 24),
                          _buildInfoRowWithImage(callIcon, _phone.text),
                          pw.SizedBox(height: 12),
                          _buildInfoRowWithImage(webIcon, _website.text),
                          pw.SizedBox(height: 12),
                          _buildInfoRowWithImage(emailIcon, _email.text),
                          pw.SizedBox(height: 12),
                          _buildInfoRowWithImage(locationIcon, _address.text),
                        ],
                      )

                  ),

                ),

                // Logo on right
                if (logoImage != null)
                  pw.Positioned(
                    right: 50,
                    top: 170,
                    child: pw.Container(
                      width: 150,
                      height: 150,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        image: pw.DecorationImage(image: logoImage, fit: pw.BoxFit.cover),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    if(widget.templateImagePath == 'assets/images/Card1_template.png'){
      final callIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/callp.png')).buffer.asUint8List());
      final emailIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/globep.png')).buffer.asUint8List());
      final webIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/emailp.png')).buffer.asUint8List());
      final locationIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/mapp.png')).buffer.asUint8List());
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) {
            return pw.Stack(
              children: [
                pw.Positioned.fill(child: pw.Image(templateImage, fit: pw.BoxFit.cover)),

                // Info section on left
                pw.Positioned(
                  left: PdfPageFormat.a4.landscape.width / 2 - 10,
                  top: 100,
                  child: pw.Container(
                      width: PdfPageFormat.a4.landscape.width / 2 - 80,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(height: 24),
                          _buildInfoRowWithImage(callIcon, _phone.text),
                          pw.SizedBox(height: 12),
                          _buildInfoRowWithImage(webIcon, _website.text),
                          pw.SizedBox(height: 12),
                          _buildInfoRowWithImage(emailIcon, _email.text),
                          pw.SizedBox(height: 12),
                          _buildInfoRowWithImage(locationIcon, _address.text),
                        ],
                      )
                  ),
                ),

                pw.Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      _businessName.text,
                      style: pw.TextStyle(
                        fontSize: 32,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.pinkAccent,
                      ),
                    ),
                  ),
                ),


                // Logo on right
                if (logoImage != null)
                  pw.Positioned(
                    left: 60,
                    top: 150,
                    child: pw.Container(
                      width: 180,
                      height: 180,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        image: pw.DecorationImage(image: logoImage, fit: pw.BoxFit.cover),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    if(widget.templateImagePath == 'assets/images/Card3_template.png'){
      final callIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/call.png')).buffer.asUint8List());
      final emailIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/globe.png')).buffer.asUint8List());
      final webIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/email.png')).buffer.asUint8List());
      final locationIcon = pw.MemoryImage((await rootBundle.load('assets/Icons/map.png')).buffer.asUint8List());
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) {
            return pw.Stack(
              children: [
                pw.Positioned.fill(child: pw.Image(templateImage, fit: pw.BoxFit.cover)),

                // Info section on left
                pw.Positioned(
                  top: 100,
                  left: 0,
                  right: 0,
                  child: pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center, // Ensures inner items are centered
                      children: [
                        pw.SizedBox(height: 24),
                        _buildInfoRowWithImage(callIcon, _phone.text),
                        pw.SizedBox(height: 12),
                        _buildInfoRowWithImage(webIcon, _website.text),
                        pw.SizedBox(height: 12),
                        _buildInfoRowWithImage(emailIcon, _email.text),
                        pw.SizedBox(height: 12),
                        _buildInfoRowWithImage(locationIcon, _address.text),
                      ],
                    ),
                  ),
                ),


                pw.Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      _businessName.text,
                      style: pw.TextStyle(
                        fontSize: 32,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ),


                // Logo on right
                if (logoImage != null)
                  pw.Positioned(
                    left: 20,
                    top: 20,
                    child: pw.Container(
                      width: 180,
                      height: 180,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        image: pw.DecorationImage(image: logoImage, fit: pw.BoxFit.cover),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  pw.Widget _buildInfoRowWithImage(pw.ImageProvider icon, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.start, // Center the whole row
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisSize: pw.MainAxisSize.min, // Prevent unnecessary stretching
        children: [
          pw.Flexible(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 22, color: PdfColors.white),
              softWrap: true,
              textAlign: pw.TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }







  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Common.primary,
      appBar: AppBar(
        backgroundColor: Common.primary,
        toolbarHeight: 60,

        automaticallyImplyLeading: true,
        iconTheme: IconThemeData(
          color: Colors.black, // Change this to any color you want
        ),

        actions: [
          GestureDetector(
            onTap: () {},
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
          'Customize Template',
          style: TextStyle(
            fontSize: Common.title,
            color: Common.secondary,
            fontFamily: Common.family,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Text("Logo Image", style: TextStyle(fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: _pickLogo,
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _logoBytes != null
                      ? Image.memory(_logoBytes!, fit: BoxFit.contain)
                      : Icon(Icons.image, size: 50, color: Colors.teal),
                ),
              ),
              SizedBox(height: 12),
              _buildTextField("Business Name", _businessName),
              _buildTextField("Phone Number", _phone),
              _buildTextField("Website", _website),
              _buildTextField("Email", _email),
              _buildTextField("Address", _address),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.cancel),
                      label: Text("Cancel"),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _generatePDF,
                      icon: Icon(Icons.download),
                      label: Text("Download"),
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

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
        SizedBox(height: 4),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        SizedBox(height: 12),
      ],
    );
  }
}
