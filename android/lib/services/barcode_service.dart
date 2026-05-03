// lib/services/barcode_service.dart
//
// خدمة الباركود مع كاش Firestore +Fallback إلى OpenFoodFacts.
// هذه النسخة تستخدم المُنشئ: BarcodeService(this._db);
// وتحتوي دالة _fromCache "المُباتشة" كما طلبت (تحويل مرن + لوج واضح + منع الكراش).
//
// الميزات:
// • تطبيع وفحص GTIN (8/12/13/14) + تجربة أكواد بديلة (UPC/EAN/GTIN-14) تلقائيًا عند عدم العثور.
// • قراءة Firestore آمنة مع تحويل أرقام مرن ومنع أي كراش (ترجع null وتكمل لـ OFF).
// • استعلام OFF v2 مع تغطية: kcal/kJ (مع تحويل kJ → kcal)، لكل 100g/serving، وحساب السعرات من الماكروز عند الحاجة.
// • لوج واضح لتشخيص الأسباب.
//
// يلزم: cloud_firestore, http

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ---------------- Utilities ----------------

/// استخراج كل مرشّحات GTIN من أي نص (يدعم GTIN-8/12/13/14 وحتى أكواد داخل QR).
List<String> gtinCandidates(String raw) {
  final src = raw ?? '';
  final digitsOnly = src.replaceAll(RegExp(r'[^0-9]'), '');
  final set = <String>{};

  void addIfLen(String x) {
    if (x.length == 8 || x.length == 12 || x.length == 13 || x.length == 14) set.add(x);
  }

  // النسخة الرقمية الكاملة
  if (digitsOnly.isNotEmpty) addIfLen(digitsOnly);

  // أي مقطع داخلي بطول قياسي
  final re = RegExp(r'(\d{8}|\d{12}|\d{13}|\d{14})');
  for (final m in re.allMatches(src)) {
    set.add(m.group(0)!);
  }

  // التحويلات الشائعة لكل مرشح
  final out = <String>{};
  for (final c in set) {
    out.addAll(alternateCodesForOFF(c));
  }
  out.addAll(set);

  // طبّع لـ GTIN قياسي
  return out.map(normalizeGtin).toSet().toList();
}

String normalizeGtin(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '').trim();

bool isValidGtin(String s) {
  final d = normalizeGtin(s);
  return d.length == 8 || d.length == 12 || d.length == 13 || d.length == 14;
}

/// يُرجع أكواد بديلة لنفس المنتج لمحاولة OpenFoodFacts
List<String> alternateCodesForOFF(String code) {
  final variants = <String>{normalizeGtin(code)};
  final c = normalizeGtin(code);

  if (c.length == 12) {
    // UPC-A → EAN-13
    variants.add('0$c');
  }
  if (c.length == 14) {
    // GTIN-14 → EAN-13
    variants.add(c.substring(1));
  }
  if (c.length == 13 && c.startsWith('0')) {
    // EAN-13 تبدأ بـ 0 → UPC-A
    variants.add(c.substring(1));
  }
  return variants.toList();
}

// تحويل أرقام مرن من num/String (مثل "120 kcal" → 120.0)
double _num(dynamic v) {
  if (v == 0) return 0.0;
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0.0;
  return double.tryParse(s.replaceAll(RegExp(r'[^0-9\\.-]'), '')) ?? 0.0;
}

String _s(dynamic v) => (v ?? '').toString();

// ---------------- Model ----------------

class FoodMacro {
  final String name;
  final String? brand;
  final double? servingSizeG;   // بالجرام لو معروف
  final double caloriesKcal;    // عادة لكل 100g من OFF، لكن قد تكون per serving حسب البيانات
  final double proteinG;
  final double carbsG;
  final double fatG;
  final String source;          // 'cache' | 'openfoodfacts'

  const FoodMacro({
    required this.name,
    required this.caloriesKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.source,
    this.brand,
    this.servingSizeG,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'brand': brand,
        'servingSizeG': servingSizeG,
        'caloriesKcal': caloriesKcal,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'source': source,
      };

  static FoodMacro fromMap(Map<String, dynamic> m, {String sourceHint = 'cache'}) {
    return FoodMacro(
      name: _s(m['name']).isNotEmpty ? _s(m['name']) : _s(m['product_name']),
      brand: _s(m['brand']).trim().isEmpty ? null : _s(m['brand']),
      servingSizeG: m.containsKey('servingSizeG') ? _num(m['servingSizeG']) : null,
      caloriesKcal: _num(m['caloriesKcal'] ?? m['kcal'] ?? m['energy_kcal']),
      proteinG: _num(m['proteinG'] ?? m['proteins_100g'] ?? m['protein']),
      carbsG: _num(m['carbsG'] ?? m['carbohydrates_100g'] ?? m['carbs']),
      fatG: _num(m['fatG'] ?? m['fat_100g'] ?? m['fat']),
      source: _s(m['source']).isNotEmpty ? _s(m['source']) : sourceHint,
    );
  }
}

// ---------------- Service ----------------

class BarcodeService {
  final FirebaseFirestore _db;
  BarcodeService(this._db);

  /// ابحث عن منتج حسب الباركود
  Future<FoodMacro?> lookup(String rawCode) async {
    final candidates = gtinCandidates(rawCode);
    if (candidates.isEmpty) {
      debugPrint('[BARCODE] No GTIN candidates in "$rawCode"');
      return null;
    }

    // 1) الكاش لكل المرشحين
    for (final code in candidates) {
      if (!isValidGtin(code)) continue;
      final cached = await _fromCache(code);
      if (cached != null) return cached;
    }

    // 2) OpenFoodFacts لكل المرشحين (مع التحويلات)
    for (final code in candidates) {
      if (!isValidGtin(code)) continue;
      final off = await _fromOFFWithVariants(code);
      if (off != null) {
        try {
          await _db.collection('barcodes').doc(code).set(off.toMap());
        } catch (e) {
          debugPrint('[BARCODE] cache write failed: $e');
        }
        return off;
      }
    }

    return null;
  }

  // ---------------- Private helpers ----------------

  // ======= هذه هي الدالة المطلوبة (باتش) كما وعدتك =======
  Future<FoodMacro?> _fromCache(String code) async {
    try {
      final doc = await _db.collection('barcodes').doc(code).get(); // عدّل اسم المجموعة إن كان مختلف
      if (!doc.exists) {
        debugPrint('[BARCODE] cache miss: $code (doc not exists)');
        return null;
      }

      final data = doc.data();
      if (data == null) {
        debugPrint('[BARCODE] cache doc has null data for $code');
        return null;
      }

      // احذر: data قد تكون Map<Object,Object> → حوّلها بأمان
      final Map<String, dynamic> m = Map<String, dynamic>.from(data as Map);

      // util محلي للأرقام (يدعم "120 kcal" أو "12g")
      double _toNum(v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        final s = v.toString().trim();
        if (s.isEmpty) return 0.0;
        return double.tryParse(s.replaceAll(RegExp(r'[^0-9\\.-]'), '')) ?? 0.0;
      }

      String _toStr(v) => (v ?? '').toString();

      // جرّب أكثر من مفتاح لكل حقل لتفادي اختلاف الأسماء
      final name   = _toStr(m['name']).isNotEmpty ? _toStr(m['name']) : _toStr(m['product_name']);
      final brand  = _toStr(m['brand']).trim().isEmpty ? null : _toStr(m['brand']);
      final kcal   = _toNum(m['caloriesKcal'] ?? m['kcal'] ?? m['energy_kcal']);
      final prot   = _toNum(m['proteinG'] ?? m['proteins_100g'] ?? m['protein']);
      final carbs  = _toNum(m['carbsG']   ?? m['carbohydrates_100g'] ?? m['carbs']);
      final fat    = _toNum(m['fatG']     ?? m['fat_100g'] ?? m['fat']);
      final serveG = m.containsKey('servingSizeG') ? _toNum(m['servingSizeG']) : null;

      // لوج مساعد لو كانت القيم صفر/ناقصة
      if (kcal == 0 && prot == 0 && carbs == 0 && fat == 0) {
        debugPrint('[BARCODE] cache doc has no nutriments for $code → m=$m');
        return null; // خلّنا نرجع null عشان نكمّل إلى OpenFoodFacts
      }

      return FoodMacro(
        name: name.isEmpty ? 'منتج غير معروف' : name,
        brand: brand,
        servingSizeG: (serveG ?? 0) == 0 ? null : serveG,
        caloriesKcal: kcal,
        proteinG: prot,
        carbsG: carbs,
        fatG: fat,
        source: 'cache',
      );
    } catch (e, st) {
      // لا تخلّيها ترمي استثناء: اطبع وارجع null
      debugPrint('[BARCODE] cache read error for $code: $e\n$st');
      return null;
    }
  }
  // ======= نهاية الدالة المطلوبة =======

  Future<FoodMacro?> _fromOFFWithVariants(String code) async {
    final tried = <String>[];
    for (final c in alternateCodesForOFF(code)) {
      tried.add(c);
      final res = await _fromOFF(c);
      if (res != null) {
        if (c != code) {
          debugPrint('[OFF] found with alternate code: $c (original: $code)');
        }
        return res;
      }
    }
    debugPrint('[OFF] not found for $code (tried: ${tried.join(", ")})');
    return null;
  }

  Future<FoodMacro?> _fromOFF(String code) async {
    try {
      final uri = Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$code.json'
        '?fields=product_name,product_name_ar,product_name_en,brands,serving_size,serving_quantity,nutrition_data_per,'
        'nutriments.energy-kcal_100g,nutriments.energy-kcal_serving,'
        'nutriments.energy-kj_100g,nutriments.energy-kj_serving,'
        'nutriments.energy-kcal,nutriments.energy-kj,'
        'nutriments.proteins_100g,nutriments.carbohydrates_100g,nutriments.fat_100g,'
        'nutriments.proteins_serving,nutriments.carbohydrates_serving,nutriments.fat_serving,'
        'nutriments.proteins,nutriments.carbohydrates,nutriments.fat'
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 404) {
        debugPrint('[OFF] HTTP 404 for $code');
        return null;
      }
      if (resp.statusCode != 200) {
        debugPrint('[OFF] HTTP ${resp.statusCode}: ${resp.body}');
        return null;
      }

      final obj = jsonDecode(resp.body) as Map<String, dynamic>;
      if ((obj['status'] ?? 0) != 1) {
        debugPrint('[OFF] status=${obj['status']} for $code');
        return null;
      }

      final prod = Map<String, dynamic>.from(obj['product'] as Map);
      Map<String, dynamic> nutr = {};
      if (prod['nutriments'] is Map) {
        nutr = Map<String, dynamic>.from(prod['nutriments'] as Map);
      }

      String pickName(Map p) {
        final names = [
          p['product_name_ar'],
          p['product_name'],
          p['product_name_en'],
        ].map((e) => _s(e)).where((e) => e.trim().isNotEmpty).toList();
        return names.isNotEmpty ? names.first : 'منتج غير معروف';
      }

      String? pickBrand(Map p) {
        final b = _s(p['brands']).trim();
        if (b.isEmpty) return null;
        final first = b.split(',').first.trim();
        return first.isEmpty ? null : first;
      }

      double? servingG(Map p) {
        final q = _num(p['serving_quantity']);
        if (q > 0) return q;
        final s = _s(p['serving_size']).toLowerCase();
        if (s.contains('g')) {
          final n = _num(s);
          return n > 0 ? n : null;
        }
        return null;
      }

      double pickEnergyKcalPer100g(Map n) {
        double kcal100 = _num(n['energy-kcal_100g']);
        if (kcal100 == 0) {
          final kj100 = _num(n['energy-kj_100g']);
          if (kj100 > 0) kcal100 = kj100 * 0.239006; // kJ → kcal
        }
        if (kcal100 == 0) {
          kcal100 = _num(n['energy-kcal']);
          if (kcal100 == 0) {
            final kj = _num(n['energy-kj']);
            if (kj > 0) kcal100 = kj * 0.239006;
          }
        }
        return kcal100;
      }

      double pickEnergyKcalPerServing(Map n) {
        double kcalS = _num(n['energy-kcal_serving']);
        if (kcalS == 0) {
          final kjS = _num(n['energy-kj_serving']);
          if (kjS > 0) kcalS = kjS * 0.239006;
        }
        return kcalS;
      }

      double pickN(Map n, String k100, String kServing, String kGeneric) {
        double v = _num(n[k100]);
        if (v == 0) v = _num(n[kServing]);
        if (v == 0) v = _num(n[kGeneric]);
        return v;
      }

      final kcal100 = pickEnergyKcalPer100g(nutr);
      final kcalServing = pickEnergyKcalPerServing(nutr);

      double p = pickN(nutr, 'proteins_100g', 'proteins_serving', 'proteins');
      double c = pickN(nutr, 'carbohydrates_100g', 'carbohydrates_serving', 'carbohydrates');
      double f = pickN(nutr, 'fat_100g', 'fat_serving', 'fat');

      double kcalFinal = kcal100;
      final per = _s(prod['nutrition_data_per']).toLowerCase(); // "100g" أو "serving"
      if ((kcalFinal == 0 && kcalServing > 0) || per == 'serving') {
        kcalFinal = kcalServing;
        if (p == 0 && _num(nutr['proteins_serving']) > 0) p = _num(nutr['proteins_serving']);
        if (c == 0 && _num(nutr['carbohydrates_serving']) > 0) c = _num(nutr['carbohydrates_serving']);
        if (f == 0 && _num(nutr['fat_serving']) > 0) f = _num(nutr['fat_serving']);
      }

      if (kcalFinal == 0 && (p + c + f) > 0) {
        debugPrint('[OFF] kcal missing; infer from macros');
        kcalFinal = 4 * p + 4 * c + 9 * f;
      }

      if (kcalFinal == 0 && p == 0 && c == 0 && f == 0) {
        debugPrint('[OFF] no nutriments for $code');
        return null;
      }

      return FoodMacro(
        name: pickName(prod),
        brand: pickBrand(prod),
        servingSizeG: servingG(prod),
        caloriesKcal: kcalFinal,
        proteinG: p,
        carbsG: c,
        fatG: f,
        source: 'openfoodfacts',
      );
    } catch (e, st) {
      debugPrint('OFF error: $e\n$st');
      return null;
    }
  }
}
