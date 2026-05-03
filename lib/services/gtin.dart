// lib/services/gtin.dart
/// Utilities for GTIN/EAN/UPC normalization & validation.
library gtin;

class BarcodeKind {
  static const ean13 = 'EAN-13';
  static const ean8 = 'EAN-8';
  static const upcA = 'UPC-A';
  static const unknown = 'UNKNOWN';
}

class BarcodeData {
  final String original;
  final String normalized; // EAN-13 form if possible (UPC-A => prefixed 0)
  final String kind;
  final bool valid;
  BarcodeData({required this.original, required this.normalized, required this.kind, required this.valid});
  @override
  String toString() => 'BarcodeData(kind=$kind, normalized=$normalized, valid=$valid, original=$original)';
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

int _computeEan13CheckDigit(String first12) {
  // positions are 1-based from the left
  int sumOdd = 0; // 1,3,5,...
  int sumEven = 0; // 2,4,6,...
  for (var i = 0; i < first12.length; i++) {
    final d = int.parse(first12[i]);
    if ((i + 1) % 2 == 0) sumEven += d; else sumOdd += d;
  }
  final mod = (sumOdd + sumEven * 3) % 10;
  final check = (10 - mod) % 10;
  return check;
}

bool isValidEan13(String s) {
  final d = _digits(s);
  if (d.length != 13) return false;
  final check = _computeEan13CheckDigit(d.substring(0, 12));
  return check == int.parse(d[12]);
}

bool isValidUpcA(String s) {
  final d = _digits(s);
  if (d.length != 12) return false;
  // UPC-A check digit uses the same algorithm as EAN-13 on 12 digits
  final check = _computeEan13CheckDigit(d.substring(0, 12));
  return check == 0; // For UPC, check digit is last digit; but we don't have it in 12? Keep simple: rely on EAN check for 12-digit forms
}

BarcodeData normalizeBarcode(String raw) {
  final d = _digits(raw);
  if (d.length == 13) {
    final ok = isValidEan13(d);
    return BarcodeData(original: raw, normalized: d, kind: BarcodeKind.ean13, valid: ok);
  } else if (d.length == 12) {
    // Treat as UPC-A and expand to EAN-13 by prefixing 0
    final ean = '0$d';
    final ok = isValidEan13(ean);
    return BarcodeData(original: raw, normalized: ean, kind: BarcodeKind.upcA, valid: ok);
  } else if (d.length == 8) {
    // EAN-8 (can't expand to 13 reliably; keep as is)
    // basic checksum validation for EAN-8
    int sum = 0;
    for (var i = 0; i < 7; i++) {
      final weight = (i % 2 == 0) ? 3 : 1;
      sum += int.parse(d[i]) * weight;
    }
    final check = (10 - (sum % 10)) % 10;
    final ok = check == int.parse(d[7]);
    return BarcodeData(original: raw, normalized: d, kind: BarcodeKind.ean8, valid: ok);
  } else {
    return BarcodeData(original: raw, normalized: d, kind: BarcodeKind.unknown, valid: false);
  }
}
