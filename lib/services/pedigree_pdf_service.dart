import '../models/pedigree_layout.dart';
import '../models/pedigree_entry.dart';
import '../utils/color_details.dart';
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
  static const double boxH = 55;
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

    final layout = PedigreeLayout(pedigree);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(PedigreeLayout.width, layout.height).copyWith(
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
    final layout = PedigreeLayout(p);
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

        for (var slot = 0; slot < PedigreeEntry.snapshotSlots.length; slot++)
          pw.Positioned(
            left: layout.left(slot) - 24,
            top: layout.top(slot) - 22,
            child: pw.SizedBox(
              width: colW,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _box(
                    p[PedigreeEntry.snapshotSlots[slot]],
                    male: slot == 0
                        ? animalIsMale(p['animal']?['sex'] ?? '')
                        : slot.isOdd,
                  ),
                  if (layout.details[slot].isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    for (final line in layout.details[slot])
                      pw.SizedBox(
                        height: 10,
                        child: pw.Text(
                          line,
                          style: pw.TextStyle(font: fontRegular, fontSize: 7),
                        ),
                      ),
                  ],
                ],
              ),
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
  // ===============================
  // BOX (LOCKED TEXT)
  // ===============================
  static pw.Widget _box(Map<String, dynamic>? a, {required bool male}) {
    final bg = male ? PdfColors.blue100 : PdfColors.pink100;
    String v(String k) => a == null ? '' : (a[k]?.toString() ?? '');

    pw.Widget line(String text) => pw.Expanded(
      child: pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: text.trim().isEmpty
            ? pw.SizedBox()
            : pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  text,
                  style: pw.TextStyle(font: fontRegular, fontSize: 7),
                ),
              ),
      ),
    );
    return pw.Container(
      height: boxH,
      padding: pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(color: bg, border: pw.Border.all(width: 1)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          line(v('name')),
          line('Ear #: ${v('tattoo')}'),
          line('Breed: ${v('breed')} • Wt: ${v('weight')}'),
          line('Variety: ${a == null ? '' : varietyLabel(a)}'),
          line(
            'Reg: ${v('registration_number')} • GC: ${v('grand_champion_number')}',
          ),
          line('DOB: ${v('dob')} • Legs: ${v('legs')}'),
        ],
      ),
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
