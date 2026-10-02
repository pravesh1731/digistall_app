import 'package:flutter/material.dart';
import '../global/Common.dart';

void getSnackBar(BuildContext context, String message, Color color, int status) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Common.primary, fontWeight: FontWeight.w500, fontFamily: 'bold', fontSize: Common.h3),
              softWrap: true,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            child: Icon(status==0 ? Icons.check_circle : status==1 ? Icons.cancel : Icons.info, color: Colors.white, size: 18,),
          )
        ],
      ),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      margin: EdgeInsets.fromLTRB(20, 20, 20, 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      duration: Duration(seconds: 2),
    ),
  );
}