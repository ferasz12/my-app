// lib/services/barcode_service.dart
//
// خدمة الباركود مع كاش Firestore +Fallback إلى OpenFoodFacts.
// هذه النسخة تستخدم المُنشئ: BarcodeService(this._db);
// وتحتوي دالة _fromCache "المُباتشة" (تحويل مرن + لوج واضح + منع الكراش).
//
// الميزات:
// • تطبيع وفحص GTIN (8/12/13/14) + تجربة أكواد بديلة (UPC/EAN/GTIN-14) تلقائيًا عند عدم العثور.
// • قراءة Firestore آمنة مع تحويل أرقام مرن ومنع أي كراش (ترجع null وتكمل لـ OFF).
// • استعلام OFF v2 مع تغطية: kcal/kJ (مع تحويل kJ → kcal)، لكل 100g/100ml/serving، وحساب السعرات من الماكروز عند الحاجة.
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

  /// حجم الحصة بالجرام (إن وُجد)
  final double? servingSizeG;

  /// حجم الحصة بالمل (إن وُجد) — مفيد للمشروبات
  final double? servingSizeMl;

  /// مصدر القيم: غالبًا تكون لكل 100 (100g/100ml) من OFF، وقد تكون "serving" لو المنتج يوفّرها فقط.
  /// قيم متوقعة: "100g" | "100ml" | "serving" | "custom"
  final String nutritionPer;

  /// السعرات (kcal) حسب nutritionPer
  final double caloriesKcal;

  /// الماكروز (g) حسب nutritionPer
  final double proteinG;
  final double carbsG;
  final double fatG;

  final String source; // 'cache' | 'openfoodfacts'

  const FoodMacro({
    required this.name,
    required this.caloriesKcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.source,
    this.brand,
    this.servingSizeG,
    this.servingSizeMl,
    this.nutritionPer = '100g',
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'brand': brand,
        'servingSizeG': servingSizeG,
        'servingSizeMl': servingSizeMl,
        'nutritionPer': nutritionPer,
        'caloriesKcal': caloriesKcal,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'source': source,
      };

  static FoodMacro fromMap(Map<String, dynamic> m, {String sourceHint = 'cache'}) {
    final np = _s(m['nutritionPer']).trim();
    return FoodMacro(
      name: _s(m['name']).isNotEmpty ? _s(m['name']) : _s(m['product_name']),
      brand: _s(m['brand']).trim().isEmpty ? null : _s(m['brand']),
      servingSizeG: m.containsKey('servingSizeG') ? _num(m['servingSizeG']) : null,
      servingSizeMl: m.containsKey('servingSizeMl') ? _num(m['servingSizeMl']) : null,
      nutritionPer: np.isEmpty ? '100g' : np,
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
          await _db.collection('barcodes').doc(code).set({
            'name': off.name,
            'brand': off.brand,
            'servingSizeG': off.servingSizeG,
            'caloriesKcal': off.caloriesKcal,
            'proteinG': off.proteinG,
            'carbsG': off.carbsG,
            'fatG': off.fatG,
            'source': off.source,
          });
        } catch (e) {
          debugPrint('[BARCODE] cache write failed: $e');
        }
        return off;
      }
    }

    return null;
  }

  // ---------------- Private helpers ----------------

  // ======= دالة الكاش (باتش) =======
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
      final name = _toStr(m['name']).isNotEmpty ? _toStr(m['name']) : _toStr(m['product_name']);
      final brand = _toStr(m['brand']).trim().isEmpty ? null : _toStr(m['brand']);
      final kcal = _toNum(m['caloriesKcal'] ?? m['kcal'] ?? m['energy_kcal']);
      final prot = _toNum(m['proteinG'] ?? m['proteins_100g'] ?? m['protein']);
      final carbs = _toNum(m['carbsG'] ?? m['carbohydrates_100g'] ?? m['carbs']);
      final fat = _toNum(m['fatG'] ?? m['fat_100g'] ?? m['fat']);

      final serveG = m.containsKey('servingSizeG') ? _toNum(m['servingSizeG']) : null;
      final serveMl = m.containsKey('servingSizeMl') ? _toNum(m['servingSizeMl']) : null;
      final per = _toStr(m['nutritionPer']).trim();

      // لوج مساعد لو كانت القيم صفر/ناقصة
      if (kcal == 0 && prot == 0 && carbs == 0 && fat == 0) {
        debugPrint('[BARCODE] cache doc has no nutriments for $code → m=$m');
        return null; // خلّنا نرجع null عشان نكمّل إلى OpenFoodFacts
      }

      return FoodMacro(
        name: name.isEmpty ? 'منتج غير معروف' : name,
        brand: brand,
        servingSizeG: (serveG ?? 0) == 0 ? null : serveG,
        servingSizeMl: (serveMl ?? 0) == 0 ? null : serveMl,
        nutritionPer: per.isEmpty ? '100g' : per,
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
  // ======= نهاية دالة الكاش =======

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

  // قراءة حجم الحصة: جرام
  double? _servingG(Map p) {
    final q = _num(p['serving_quantity']);
    final s = _s(p['serving_size']).toLowerCase();

    // لو لدينا كمية رقمية + وحدة واضحة في النص
    if (q > 0) {
      if (s.contains('kg')) return q * 1000;
      if (s.contains('mg')) return q / 1000;
      if (s.contains('g') && !s.contains('ml')) return q;
    }

    if (s.contains('kg')) {
      final n = _num(s);
      return n > 0 ? n * 1000 : null;
    }
    if (s.contains('mg')) {
      final n = _num(s);
      return n > 0 ? n / 1000 : null;
    }
    if (s.contains('g') && !s.contains('ml')) {
      final n = _num(s);
      return n > 0 ? n : null;
    }
    return null;
  }

  // قراءة حجم الحصة: مل
  double? _servingMl(Map p) {
    final q = _num(p['serving_quantity']);
    final s = _s(p['serving_size']).toLowerCase();

    if (q > 0) {
      if (s.contains('ml')) return q;
      if (s.contains('cl')) return q * 10;
      if (s.contains('dl')) return q * 100;
      if (s.contains(' l') || (s.endsWith('l') && !s.endsWith('ml')) || s.contains('lit')) return q * 1000;
    }

    if (s.contains('ml')) {
      final n = _num(s);
      return n > 0 ? n : null;
    }
    if (s.contains('cl')) {
      final n = _num(s);
      return n > 0 ? n * 10 : null;
    }
    if (s.contains('dl')) {
      final n = _num(s);
      return n > 0 ? n * 100 : null;
    }

    // 0.33 l أو 1l
    if (s.contains('l') && !s.contains('ml') && !s.contains('cl') && !s.contains('dl')) {
      final n = _num(s);
      return n > 0 ? n * 1000 : null;
    }

    return null;
  }

  Future<FoodMacro?> _fromOFF(String code) async {
    try {
      final uri = Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$code.json'
        '?fields=product_name,product_name_ar,product_name_en,brands,serving_size,serving_quantity,nutrition_data_per,'
        'nutriments.energy-kcal_100g,nutriments.energy-kcal_100ml,nutriments.energy-kcal_serving,'
        'nutriments.energy-kj_100g,nutriments.energy-kj_100ml,nutriments.energy-kj_serving,'
        'nutriments.energy-kcal,nutriments.energy-kj,'
        'nutriments.proteins_100g,nutriments.proteins_100ml,nutriments.proteins_serving,nutriments.proteins,'
        'nutriments.carbohydrates_100g,nutriments.carbohydrates_100ml,nutriments.carbohydrates_serving,nutriments.carbohydrates,'
        'nutriments.fat_100g,nutriments.fat_100ml,nutriments.fat_serving,nutriments.fat'
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

      // المقصود من OFF: nutrition_data_per قد يكون "100g" أو "100ml" أو "serving"
      final perRaw = _s(prod['nutrition_data_per']).toLowerCase().trim();
      final per = perRaw.isEmpty ? '100g' : perRaw;

      // حجم الحصة
      final serveG = _servingG(prod);
      final serveMl = _servingMl(prod);

      double pickEnergyKcalPer100(Map n, {required bool isMl}) {
        // OFF يقدّم energy-kcal_100ml للمشروبات أحيانًا
        double kcal100 = _num(n[isMl ? 'energy-kcal_100ml' : 'energy-kcal_100g']);
        if (kcal100 == 0) {
          final kj100 = _num(n[isMl ? 'energy-kj_100ml' : 'energy-kj_100g']);
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

      double pickN(Map n, {required bool isMl, required String k100g, required String k100ml, required String kServing, required String kGeneric}) {
        double v = _num(n[isMl ? k100ml : k100g]);
        if (v == 0) v = _num(n[kServing]);
        if (v == 0) v = _num(n[kGeneric]);
        return v;
      }

      final isMl = per == '100ml';

      final kcal100 = pickEnergyKcalPer100(nutr, isMl: isMl);
      final kcalServing = pickEnergyKcalPerServing(nutr);

      double p = pickN(nutr,
          isMl: isMl,
          k100g: 'proteins_100g',
          k100ml: 'proteins_100ml',
          kServing: 'proteins_serving',
          kGeneric: 'proteins');
      double c = pickN(nutr,
          isMl: isMl,
          k100g: 'carbohydrates_100g',
          k100ml: 'carbohydrates_100ml',
          kServing: 'carbohydrates_serving',
          kGeneric: 'carbohydrates');
      double f = pickN(nutr,
          isMl: isMl,
          k100g: 'fat_100g',
          k100ml: 'fat_100ml',
          kServing: 'fat_serving',
          kGeneric: 'fat');

      double kcalFinal;
      if ((kcal100 == 0 && kcalServing > 0) || per == 'serving') {
        kcalFinal = kcalServing;
        // إذا كانت البيانات لكل حصة، تأكد أننا نأخذ قيم الحصة إن وُجدت
        if (p == 0 && _num(nutr['proteins_serving']) > 0) p = _num(nutr['proteins_serving']);
        if (c == 0 && _num(nutr['carbohydrates_serving']) > 0) c = _num(nutr['carbohydrates_serving']);
        if (f == 0 && _num(nutr['fat_serving']) > 0) f = _num(nutr['fat_serving']);
      } else {
        kcalFinal = kcal100;
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
        servingSizeG: (serveG ?? 0) == 0 ? null : serveG,
        servingSizeMl: (serveMl ?? 0) == 0 ? null : serveMl,
        nutritionPer: per,
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
