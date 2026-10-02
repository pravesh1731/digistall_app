import 'package:flutter/material.dart';

import '../global/Common.dart';
import 'BusinessCardEditorPage.dart';

class ToolsPage extends StatefulWidget {

  final String shopId;

  const ToolsPage({super.key, required this.shopId,});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
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
          "Tools",
          style: TextStyle(
            fontSize: Common.title,
            color: Common.secondary,
            fontFamily: Common.family,
            // fontWeight: Common.weight,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            Align(alignment: Alignment.centerLeft, child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text('3 Templates', style: TextStyle(color: Common.secondary, fontSize: 20)),
            )),
            SizedBox(height: 10,),
            CardImage(imagePath: 'assets/images/card1.png',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BusinessCardEditorPage(
                      templateImagePath: 'assets/images/Card1_template.png',
                    ),
                  ),
                );
              },),
            SizedBox(height: 20),
            CardImage(imagePath: 'assets/images/card2.png',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BusinessCardEditorPage(
                      templateImagePath: 'assets/images/Card2_template.png',
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: 20),
            CardImage(imagePath: 'assets/images/card3.png',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BusinessCardEditorPage(
                      templateImagePath: 'assets/images/Card3_template.png',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CardImage extends StatelessWidget {
  final String imagePath;
  final VoidCallback? onTap;

  const CardImage({required this.imagePath, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              spreadRadius: 2,
              offset: Offset(2, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            imagePath,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
