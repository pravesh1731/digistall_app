import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/models.dart';

const _teal = PdfColor.fromInt(0xFF0E8A87);
const _ink = PdfColor.fromInt(0xFF06302F);
const _grey = PdfColor.fromInt(0xFF6B7280);

class InvoiceData {
  InvoiceData({
    required this.shop,
    required this.number,
    required this.date,
    required this.customerName,
    required this.items,
    required this.total,
    this.customerPhone = '',
    this.address = '',
    this.paymentLabel = '',
    this.transactionId = '',
    this.deliveryFee = 0,
    this.platformFee = 0,
  });

  factory InvoiceData.fromOrder(OrderGroup o, Shop shop) => InvoiceData(
        shop: shop,
        number: o.id.length > 6 ? o.id.substring(o.id.length - 6).toUpperCase() : o.id.toUpperCase(),
        date: o.date,
        customerName: o.customerName,
        customerPhone: o.customerPhone,
        address: o.address,
        items: o.items,
        paymentLabel: o.isUpi ? 'PREPAID (UPI)' : 'CASH ON DELIVERY',
        transactionId: o.transactionId.toUpperCase().startsWith('COD') ? '' : o.transactionId,
        deliveryFee: o.deliveryFee,
        platformFee: o.platformFee,
        total: o.total,
      );

  final Shop shop;
  final String number;
  final DateTime? date;
  final String customerName;
  final String customerPhone;
  final String address;
  final List<OrderItem> items;
  final String paymentLabel;
  final String transactionId;
  final num deliveryFee;
  final num platformFee;
  final num total;
}

Future<Uint8List> buildInvoicePdf(InvoiceData d) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Hind-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Hind-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold), title: 'Invoice ${d.number}');
  final shop = d.shop;
  final subtotal = d.items.fold<num>(0, (s, i) => s + i.lineTotal);

  pw.Widget label(String t) => pw.Text(t.toUpperCase(), style: pw.TextStyle(fontSize: 9, color: _grey, fontWeight: pw.FontWeight.bold));
  pw.Widget sumRow(String l, String v, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(l, style: pw.TextStyle(fontSize: strong ? 14 : 11, fontWeight: strong ? pw.FontWeight.bold : null)),
          pw.Text(v, style: pw.TextStyle(fontSize: strong ? 14 : 11, fontWeight: strong ? pw.FontWeight.bold : null)),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (ctx) => [
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 14),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _teal, width: 3))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(shop.name, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _teal)),
              if (shop.address.isNotEmpty) pw.Text(shop.address, style: const pw.TextStyle(fontSize: 10, color: _grey)),
              if (shop.phone.isNotEmpty) pw.Text('Ph: ${shop.phone}', style: const pw.TextStyle(fontSize: 10, color: _grey)),
              if (shop.gst.isNotEmpty) pw.Text('GSTIN: ${shop.gst}', style: const pw.TextStyle(fontSize: 10, color: _grey)),
              pw.Text(shop.url, style: const pw.TextStyle(fontSize: 10, color: _grey)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('INVOICE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.Text('#${d.number}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text(formatDateTime(d.date ?? DateTime.now()), style: const pw.TextStyle(fontSize: 10, color: _grey)),
          ]),
        ]),
      ),
      pw.SizedBox(height: 18),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF5F8F8), borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              label('Bill to'),
              pw.Text(d.customerName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              if (d.customerPhone.isNotEmpty) pw.Text('Ph: +91 ${d.customerPhone}', style: const pw.TextStyle(fontSize: 10)),
              if (d.address.isNotEmpty) pw.Text(d.address, style: const pw.TextStyle(fontSize: 10)),
            ]),
          ),
          if (d.paymentLabel.isNotEmpty)
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              label('Payment'),
              pw.Text(d.paymentLabel, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              if (d.transactionId.isNotEmpty) pw.Text('UTR / Txn: ${d.transactionId}', style: const pw.TextStyle(fontSize: 9.5, color: _grey)),
            ]),
        ]),
      ),
      pw.SizedBox(height: 18),
      pw.TableHelper.fromTextArray(
        headers: ['Item', 'Qty', 'Price', 'Total'],
        data: [
          for (final i in d.items)
            [i.variant.isEmpty ? i.name : '${i.name} (${i.variant})', _qty(i.qty), inr(i.price), inr(i.lineTotal)],
        ],
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10.5),
        headerDecoration: const pw.BoxDecoration(color: _ink),
        cellStyle: const pw.TextStyle(fontSize: 10.5),
        cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.center, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
        columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1.6), 3: const pw.FlexColumnWidth(1.6)},
        border: null,
        rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      pw.SizedBox(height: 14),
      pw.Row(children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 230,
          child: pw.Column(children: [
            sumRow('Subtotal', inr(subtotal)),
            if (d.deliveryFee > 0) sumRow('Delivery charges', '+${inr(d.deliveryFee)}'),
            if (d.platformFee > 0) sumRow('Platform fee', '+${inr(d.platformFee)}'),
            pw.Divider(color: _ink, thickness: 1.5),
            sumRow('Grand total', inr(d.total), strong: true),
          ]),
        ),
      ]),
      pw.SizedBox(height: 30),
      pw.Center(child: pw.Text('Thank you for shopping at ${shop.name}! Powered by DigiStall.in', style: const pw.TextStyle(fontSize: 9.5, color: _grey))),
    ],
  ));
  return doc.save();
}

String _qty(num q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// Builds the invoice and opens the share sheet (save, WhatsApp, print…).
Future<void> shareInvoice(InvoiceData d) async {
  final bytes = await buildInvoicePdf(d);
  await Printing.sharePdf(bytes: bytes, filename: 'Invoice_${d.number}.pdf');
}
