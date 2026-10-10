// ignore_for_file: prefer_const_constructors

import 'dart:typed_data';
import '../utils/animal_labels.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PedigreePdfService {
  // ===============================
  // FONTS
  // ===============================
  static late pw.Font fontRegular;
  static late pw.Font fontItalic;

  static Future<void> _loadFonts() async {
    final reg = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Italic.ttf');

    fontRegular = pw.Font.ttf(reg.buffer.asByteData());
    fontItalic = pw.Font.ttf(bold.buffer.asByteData());
  }

  // ===============================
  // LOCKED MEASUREMENTS
  // ===============================
  static const double colW = 170;
  static const double boxH = 58;
  static const double lineH = 10;
  static const double gap = 6;

  // ===============================
  // PUBLIC GENERATOR
  // ===============================
  static Future<Uint8List> generate({
    required Map<String, dynamic> pedigree,
    Map<String, dynamic>? seller, // ← optional for now
  }) async {
    await _loadFonts();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, italic: fontItalic),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter.landscape.copyWith(
          marginLeft: 24,
          marginRight: 24,
          marginTop: 22,
          marginBottom: 22,
        ),
        build: (_) => _buildPage(pedigree, seller),
      ),
    );

    return pdf.save();
  }

  // ===============================
  // PAGE BODY
  // ===============================
  static pw.Widget _buildPage(
    Map<String, dynamic> p,
    Map<String, dynamic>? seller,
  ) {
    return pw.Stack(
      children: [
        // SOLD TO (TOP LEFT)
        pw.Positioned(left: 0, top: 0, child: _soldToBlock()),

        // TITLE
        pw.Positioned(
          top: 0,
          left: 300,
          child: pw.Text(
            p['animal']?['species'] == 'cavy'
                ? 'CAVY PEDIGREE'
                : 'RABBIT PEDIGREE',
            style: pw.TextStyle(font: fontItalic, fontSize: 18),
          ),
        ),

        // GRID
        pw.Positioned(
          top: 80,
          left: 0,
          right: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _col([
                pw.SizedBox(height: 230),
                _box(
                  p['animal'],
                  male: animalIsMale(p['animal']?['sex'] ?? ''),
                ),
              ]),
              _col([
                pw.SizedBox(height: 80),
                _box(p['sire'], male: true),
                pw.SizedBox(height: 200),
                _box(p['dam'], male: false),
              ]),
              _col([
                pw.SizedBox(height: 25),
                _box(p['sire_sire'], male: true),
                pw.SizedBox(height: 50),
                _box(p['sire_dam'], male: false),
                pw.SizedBox(height: 75),
                _box(p['dam_sire'], male: true),
                pw.SizedBox(height: 50),
                _box(p['dam_dam'], male: false),
              ]),
              _col([
                _box(p['gg1'], male: true),
                _box(p['gg2'], male: false),
                _box(p['gg3'], male: true),
                _box(p['gg4'], male: false),
                _box(p['gg5'], male: true),
                _box(p['gg6'], male: false),
                _box(p['gg7'], male: true),
                _box(p['gg8'], male: false),
              ]),
            ],
          ),
        ),

        // SELLER SIGNATURE (BOTTOM LEFT)
        if (seller != null)
          pw.Positioned(left: 0, bottom: 0, child: _sellerSignature(seller)),

        // Date Stamp and Created by Stamp (BOTTOM RIGHT)
        pw.Positioned(right: 0, bottom: 0, child: _exportWatermark()),
      ],
    );
  }

  // ===============================
  // SOLD TO BLOCK (BLANK)
  // ===============================
  static pw.Widget _soldToBlock() {
    pw.Widget line(String label) => pw.Row(
      children: [
        pw.SizedBox(
          width: 70,
          child: pw.Text(label, style: pw.TextStyle(fontSize: 8)),
        ),
        pw.Container(
          width: 180,
          height: 10,
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: .7)),
          ),
        ),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Sold To:', style: pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 4),
        line('Address:'),
        line('City:'),
        line('State:'),
        line('Zip:'),
        line('Date Sold:'),
      ],
    );
  }

  // ===============================
  // COLUMN
  // ===============================
  static pw.Widget _col(List<pw.Widget> boxes) {
    return pw.Container(
      width: colW,
      margin: pw.EdgeInsets.only(right: 10),
      child: pw.Column(
        children: [
          for (int i = 0; i < boxes.length; i++) ...[
            boxes[i],
            if (i < boxes.length - 1) pw.SizedBox(height: gap),
          ],
        ],
      ),
    );
  }

  // ===============================
  // BOX (LOCKED TEXT)
  // ===============================
  static pw.Widget _box(Map<String, dynamic>? a, {required bool male}) {
    final bg = male ? PdfColors.blue100 : PdfColors.pink100;
    String v(String k) => a == null ? '' : (a[k]?.toString() ?? '');

    return pw.Container(
      height: boxH,
      padding: pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(color: bg, border: pw.Border.all(width: 1)),
      child: pw.Stack(
        children: [
          _line(0, v('name'), bold: true),
          _line(1, 'Ear #: ${v('tattoo')}'),
          _line(2, 'Breed: ${v('breed')}'),
          _rightLine(2, 'Wt: ${v('weight')}  Legs: ${v('legs')}'),
          _line(3, 'Variety: ${v('variety')}'),
          _rightLine(3, 'Reg: ${v('registration_number')}'),
          _line(4, 'DOB: ${v('dob')}'),
          _rightLine(4, 'GC: ${v('grand_champion_number')}'),
        ],
      ),
    );
  }

  static pw.Widget _line(int i, String text, {bool bold = false}) {
    return pw.Positioned(
      top: i * lineH,
      left: 0,
      child: pw.Text(
        text,
        style: pw.TextStyle(font: bold ? fontItalic : fontRegular, fontSize: 8),
      ),
    );
  }

  static pw.Widget _rightLine(int i, String text) {
    return pw.Positioned(
      top: i * lineH,
      right: 0,
      child: pw.Text(text, style: pw.TextStyle(fontSize: 8)),
    );
  }

  // ===============================
  // Date Stamp and Created by Stamp
  // ===============================

  static pw.Widget _exportWatermark() {
    final now = DateTime.now();

    final exportDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    return pw.Text(
      "Exported $exportDate • Created by Ringmaster Breeder",
      style: pw.TextStyle(
        font: fontRegular,
        fontSize: 7,
        color: PdfColors.grey600,
      ),
    );
  }

  // ===============================
  // SELLER SIGNATURE
  // ===============================
  static pw.Widget _sellerSignature(Map<String, dynamic> seller) {
    pw.Widget sig(String v) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 200,
          height: 12,
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: .7)),
          ),
          child: pw.Text(v, style: pw.TextStyle(fontSize: 8)),
        ),
        pw.SizedBox(height: 2),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Seller:', style: pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 4),
        sig(seller['name'] ?? ''),
        sig(seller['address'] ?? ''),
        sig(
          '${seller['city'] ?? ''}, ${seller['state'] ?? ''} ${seller['zip'] ?? ''}',
        ),
        sig(seller['contact'] ?? ''),
      ],
    );
  }
}
