// lib/screens/regimen_screen.dart
// صفحة "رجيمي" + DietBus محدث:
// - منع تفعيل أكثر من رجيم في نفس الوقت (BottomSheet عند محاولة فتح رجيم آخر)
// - تحذير ناعم عند أكل عالي الكارب في الكيتو
// - منع إضافة الوجبة إذا ستتجاوز حد الكارب اليومي في الكيتو
// - الحفاظ على منع الإضافة أثناء نافذة الصيام
// - ✅ مزامنة "active_regimen" مع الحالة الفعلية للكيتو/الصيام (ويكتشف النشاط حتى لو المفتاح مفقود)

import 'dart:convert';
import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'regimen_lowfat_screen.dart';
import 'regimen_lowcarb_screen.dart';
import '../services/tracker_store.dart';
import '../regimens/lowfat_guard.dart';
import '../regimens/lowcarb_guard.dart';
import '../regimens/high_protein_guard.dart';
import '../regimens/mediterranean_guard.dart';
import 'regimen_high_protein_screen.dart';
import 'regimen_mediterranean_screen.dart';

// للصيام المتقطع
import 'package:provider/provider.dart';
import '../fasting/fasting_service.dart';
import 'regimen_if16_screen.dart';

// للكيتو
import '../regimens/keto_guard.dart';
import 'keto_regimen_screen.dart';

// =====================
// نموذج الرجيم
// =====================
class RegimenModel {
  final String id;
  final String title;
  final String goal; // تصنيف/مجموعة
  final List<String> benefits;
  final List<String> risks;
  final List<String> popularFoods;
  final double? dailyCalorieCap; // اختياري (للاستخدام لاحقًا)

  RegimenModel({
    required this.id,
    required this.title,
    required this.goal,
    required this.benefits,
    required this.risks,
    required this.popularFoods,
    this.dailyCalorieCap,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'goal': goal,
        'benefits': benefits,
        'risks': risks,
        'popularFoods': popularFoods,
        'dailyCalorieCap': dailyCalorieCap,
      };

  factory RegimenModel.fromJson(Map<String, dynamic> m) => RegimenModel(
        id: m['id']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        goal: m['goal']?.toString() ?? '',
        benefits: (m['benefits'] as List?)?.map((e) => '$e').toList() ?? const [],
        risks: (m['risks'] as List?)?.map((e) => '$e').toList() ?? const [],
        popularFoods:
            (m['popularFoods'] as List?)?.map((e) => '$e').toList() ?? const [],
        dailyCalorieCap: (m['dailyCalorieCap'] is num)
            ? (m['dailyCalorieCap'] as num).toDouble()
            : null,
      );
}

// =====================
// البيانات: نظامان (الصيام المتقطع 16/8 + الكيتو)
// =====================

final List<RegimenModel> kAllRegimens = [
  RegimenModel(
    id: 'if-16-8',
    title: 'الصيام المتقطع',
    goal: 'تنظيم أوقات الأكل',
    benefits: ['مؤقت واضح', 'سجل أسبوعي', 'تنبيهات بداية ونهاية الصيام'],
    risks: ['ابدأ تدريجيًا', 'أوقف الصيام عند الدوخة أو التعب الشديد'],
    popularFoods: ['وجبة افتتاح متوازنة', 'ماء وقهوة/شاي بدون سكر'],
  ),
  RegimenModel(
    id: 'high-protein',
    title: 'رجيم عالي البروتين',
    goal: 'بناء العضلات والشبع',
    benefits: ['متابعة هدف البروتين', 'تنبيهات توزيع البروتين', 'تنبيه للوجبات قليلة البروتين'],
    risks: ['لا تبالغ إذا لديك مشكلة كلى أو توجيه طبي خاص'],
    popularFoods: ['دجاج/تونة/بيض', 'لبن يوناني', 'بقوليات ومصادر بروتين'],
  ),
  RegimenModel(
    id: 'mediterranean',
    title: 'رجيم البحر المتوسط',
    goal: 'نظام صحي مرن',
    benefits: ['تذكيرات طبق متوازن', 'تركيز على الخضار والبروتين', 'تنبيه للدهون العالية'],
    risks: ['الدهون الصحية ما زالت تحتاج كمية محسوبة'],
    popularFoods: ['زيت زيتون', 'سمك/دجاج', 'خضار وفواكه وحبوب كاملة'],
  ),
  RegimenModel(
    id: 'keto',
    title: 'رجيم الكيتو',
    goal: 'خفض الكارب',
    benefits: ['استقرار السكر', 'تقليل الشهية', 'اختيارات كاملة الدسم'],
    risks: ['كيتو فلو مؤقت', 'غير مناسب لبعض الحالات'],
    popularFoods: ['بيض/لحوم/أسماك', 'أفوكادو/زيوت صحية', 'خضار قليلة الكارب'],
  ),
  RegimenModel(
    id: 'low-carb',
    title: 'رجيم لو كارب',
    goal: 'خفض الكارب المعتدل',
    benefits: ['تحكم أفضل بالسكر', 'مرونة أعلى من الكيتو'],
    risks: ['هبوط طاقة مؤقت', 'تحتاج توزيع كارب حكيم'],
    popularFoods: ['لحوم/بيض', 'خضار ورقية', 'مكسرات/ألبان قليلة السكر'],
  ),
  RegimenModel(
    id: 'low-fat',
    title: 'رجيم قليل الدهون',
    goal: 'خفض الدهون الغذائية',
    benefits: ['تقليل السعرات من الدهون', 'دعم صحة القلب'],
    risks: ['قد ينخفض امتصاص الفيتامينات ADEK لو الحد شديد'],
    popularFoods: ['مشوي/هوائي', 'ألبان قليلة الدسم', 'لحوم بدون جلد'],
  ),
];

// =====================
// قناة تواصل مع الهوم: DietBus (مُحدّث)
// =====================
class DietBus {
  static const String _kActiveKey = 'active_regimen';

  // يُفعِّل نظامًا واحدًا حصريًا ويُوقف بقية الأنظمة.
  // ملاحظة مهمة: عند تفعيل الصيام المتقطع لا نوقف FastingService هنا،
  // لأن شاشة الصيام هي التي تبدأ الجلسة بعد اختيار الوقت.
  static Future<void> activateExclusive(String id) async {
    try {
      if (id != 'keto') await KetoGuard.endRegimen();
      if (id != 'low-carb') await LowCarbGuard.setActive(false);
      if (id != 'low-fat') await LowFatGuard.setActive(false);
      if (id != 'high-protein') await HighProteinGuard.setActive(false);
      if (id != 'mediterranean') await MediterraneanGuard.setActive(false);

      if (id != 'if-16-8') {
        final fs = await FastingService.load();
        await fs.stopFasting();
      }

      if (id == 'keto') {
        await KetoGuard.startRegimen();
      } else if (id == 'low-carb') {
        await LowCarbGuard.setActive(true);
      } else if (id == 'low-fat') {
        await LowFatGuard.setActive(true);
      } else if (id == 'high-protein') {
        await HighProteinGuard.setActive(true);
      } else if (id == 'mediterranean') {
        await MediterraneanGuard.setActive(true);
      }

      if (id == 'if-16-8' || id == 'keto' || id == 'low-carb' || id == 'low-fat' || id == 'high-protein' || id == 'mediterranean') {
        await setActiveById(id);
      } else {
        await setActive(null);
      }
    } catch (_) {}
  }

  // يثبّت حالة النظام النشط بدون إطفاء أي خدمة.
  // نستخدمه بعد بدء الصيام مباشرة حتى تقفل بطاقات الأنظمة الأخرى فورًا.
  static Future<void> setActiveById(String id) async {
    await setActive(_findById(id));
  }

  // يضمن أن نظامًا واحدًا فقط فعّال عبر إطفاء البقية (يُستخدم داخل getActive)
  static Future<void> _ensureExclusive(String id) async {
    try {
      if (id != 'keto') await KetoGuard.endRegimen();
      if (id != 'low-carb') await LowCarbGuard.setActive(false);
      if (id != 'low-fat') await LowFatGuard.setActive(false);
      if (id != 'high-protein') await HighProteinGuard.setActive(false);
      if (id != 'mediterranean') await MediterraneanGuard.setActive(false);
      if (id != 'if-16-8') {
        final fs = await FastingService.load();
        await fs.stopFasting();
      }
    } catch (_) {}
  }

  static RegimenModel? _cached;

  // مساعد بسيط للعثور على نموذج النظام بحسب id
  static RegimenModel? _findById(String id) {
    for (final m in kAllRegimens) {
      if (m.id == id) return m;
    }
    return null;
  }


  static Future<RegimenModel?> _detectActualActive() async {
    try {
      final fs = await FastingService.load();
      if (fs.isActive) return _findById('if-16-8');
    } catch (_) {}
    try {
      if (await KetoGuard.isActive()) return _findById('keto');
    } catch (_) {}
    try {
      if (await LowCarbGuard.isActive()) return _findById('low-carb');
    } catch (_) {}
    try {
      if (await LowFatGuard.isActive()) return _findById('low-fat');
    } catch (_) {}
    try {
      if (await HighProteinGuard.isActive()) return _findById('high-protein');
    } catch (_) {}
    try {
      if (await MediterraneanGuard.isActive()) return _findById('mediterranean');
    } catch (_) {}
    return null;
  }

  /// ✅ قراءة حالة النظام النشط مع مزامنة تلقائية:
  /// - تطابق المفتاح المخزن مع الواقع (كيتو/صيام).
  /// - لو ما فيه مفتاح لكنه وجد نظام فعليًا شغّال → يضبطه كمفتاح نشط ويعيده.
    static Future<RegimenModel?> getActive() async {
  // تحقق من الكاش مقابل الواقع
  if (_cached != null) {
    final id = _cached!.id;
    if (id == 'keto') {
      if (await KetoGuard.isActive()) return _cached;
    } else if (id == 'low-carb') {
      if (await LowCarbGuard.isActive()) return _cached;
    } else if (id == 'low-fat') {
      if (await LowFatGuard.isActive()) return _cached;
    } else if (id == 'high-protein') {
      if (await HighProteinGuard.isActive()) return _cached;
    } else if (id == 'mediterranean') {
      if (await MediterraneanGuard.isActive()) return _cached;
    } else if (id == 'if-16-8') {
      final fs = await FastingService.load();
      if (fs.isActive) return _cached;
    }
    // الكاش قديم
    _cached = null;
  }

  // اقرأ المؤشر من التخزين
  final prefs = await SharedPreferences.getInstance();
  // المفتاح قد يكون id بسيط أو JSON ل model — جرّب الاثنين
  final raw = prefs.getString('active_regimen');
  if (raw == null) {
    // بعض الشاشات القديمة كانت تشغّل النظام بدون تحديث active_regimen.
    // لذلك نقرأ الحالة الحقيقية من الحراس ونثبتها هنا.
    final detected = await _detectActualActive();
    if (detected != null) {
      await _ensureExclusive(detected.id);
      await setActive(detected);
      _cached = detected;
      return detected;
    }
    _cached = null;
    return null;
  }

  RegimenModel? parsed;
  try {
    if (raw.trim().startsWith("{")) {
      final map = json.decode(raw) as Map<String, dynamic>;
      parsed = RegimenModel.fromJson(map);
    } else {
      parsed = _findById(raw);
    }
  } catch (_) {
    parsed = _findById(raw); // fallback
  }

  if (parsed == null) {
    // تنظيف المفتاح المعطوب ثم محاولة اكتشاف الواقع الفعلي.
    await setActive(null);
    final detected = await _detectActualActive();
    if (detected != null) {
      await _ensureExclusive(detected.id);
      await setActive(detected);
      _cached = detected;
      return detected;
    }
    _cached = null;
    return null;
  }

  // طابق حالة الحُرّاس للنظام
  if (parsed.id == 'keto') {
    final on = await KetoGuard.isActive();
    if (!on) {
      await setActive(null);
      _cached = null;
      return null;
    }
    await _ensureExclusive('keto');
    _cached = parsed;
    return parsed;
  } else if (parsed.id == 'if-16-8') {
    final fs = await FastingService.load();
    if (!fs.isActive) {
      await setActive(null);
      _cached = null;
      return null;
    }
    await _ensureExclusive('if-16-8');
    _cached = parsed;
    return parsed;
  } else if (parsed.id == 'low-carb') {
    final on = await LowCarbGuard.isActive();
    if (!on) {
      await setActive(null);
      _cached = null;
      return null;
    }
    await _ensureExclusive('low-carb');
    _cached = parsed;
    return parsed;
  } else if (parsed.id == 'low-fat') {
    final on = await LowFatGuard.isActive();
    if (!on) {
      await setActive(null);
      _cached = null;
      return null;
    }
    await _ensureExclusive('low-fat');
    _cached = parsed;
    return parsed;
  } else if (parsed.id == 'high-protein') {
    final on = await HighProteinGuard.isActive();
    if (!on) {
      await setActive(null);
      _cached = null;
      return null;
    }
    await _ensureExclusive('high-protein');
    _cached = parsed;
    return parsed;
  } else if (parsed.id == 'mediterranean') {
    final on = await MediterraneanGuard.isActive();
    if (!on) {
      await setActive(null);
      _cached = null;
      return null;
    }
    await _ensureExclusive('mediterranean');
    _cached = parsed;
    return parsed;
  }

  // غير معروف → نظّف
  await setActive(null);
  _cached = null;
  return null;
}


    static Future<void> setActive(RegimenModel? m) async {
    _cached = m;
    final prefs = await SharedPreferences.getInstance();
    if (m == null) {
      await prefs.remove('active_regimen');
    } else {
      await prefs.setString('active_regimen', json.encode(m.toJson()));
    }
  }

  static void invalidate() {
    _cached = null;
  }

  /// تُنادى من الهوم عند إضافة وجبة.
  /// 1) الصيام: المنع أثناء نافذة الصيام دائمًا إذا كان IF نشطًا (حتى لو enforce = false).
  ///    وإن كان IF غير نشط لكن المستخدم فعّل enforce يدويًا → برضه نمنع.
  /// 2) الكيتو:
  ///    - تحذير ناعم لو الوجبة عالية الكارب (>= 20غ).
  ///    - منع إذا (كارب اليوم الحالي + كارب الإضافة) > الحد.
  static Future<bool> addMeal({
    required double calories,
    required double proteinGrams,
    required double carbsGrams,
    required double fatGrams,
    required DateTime at,
    required BuildContext context,
  }) async {
    // 1) الصيام المتقطع — المنع أثناء نافذة الصيام حسب الحالة النشطة أو enforce
    try {
      final fs = await FastingService.load();
      final active = await DietBus.getActive(); // يلتقط النظام الفعلي حتى لو المفتاح مفقود
      final bool isIFActive = (active?.id == 'if-16-8');

      // نمنع إذا داخل نافذة الصيام وكان IF نشطاً،
      // أو إذا المستخدم فعّل enforce يدوياً (حالة أشدّ صرامة)
      final bool fastingShouldBlock =
          fs.isWithinFasting(at) && (isIFActive || fs.enforce);

      if (fastingShouldBlock) {
        await _showFastingBlockerSheet(context);
        return false;
      }
    } catch (_) {}

    // 2) الكيتو — نفس منطقك السابق
    try {
      final ketoOn = await KetoGuard.isActive();
      if (ketoOn) {
        final limit = await KetoGuard.carbLimit();          // حد اليوم
        final today = await KetoGuard.todayCarbs();         // كارب اليوم الحالي
        final nextTotal = today + carbsGrams;

        // تحذير ناعم High-Carb meal (يُسمح إن كان تحت الحد)
        if (carbsGrams >= 20) {
          _showKetoHighCarbNotice(context, carbsGrams);
        }

        // منع الإضافة إذا سنكسر الحد
        if (nextTotal > limit) {
          await _showKetoLimitBlockerSheet(context, today, carbsGrams, limit);
          return false;
        }
      }
    } catch (_) {}

    // مسموح
    
    // 2.7) قليل الدهون — حد الدهون بالجرام
    try {
      final lfOn = await LowFatGuard.isActive();
      if (lfOn) {
        final limit = await LowFatGuard.fatLimit(); // افتراضي 60غ
        final today = await TrackerStore.getDay(DateTime.now());
        final todayFat = (today['fat'] as num?)?.toDouble() ?? 0.0;
        // تنبيه ناعم لو الوجبة عالية الدهون >= 20غ
        if (fatGrams >= 20) {
          await _showHighFatNudge(context, fatGrams.toInt(), limit.toInt());
        }
        if (todayFat + fatGrams > limit) {
          final ok = await _confirmExceedFat(context, (todayFat + fatGrams).toInt(), limit.toInt(), title: 'تجاوز حد الدهون (لو فات)');
          if (!ok) return false;
        }
      }
    } catch (_) {}

    // 2.6) لو كارب — حد الكارب
    try {
      final lcOn = await LowCarbGuard.isActive();
      if (lcOn) {
        final limit = await LowCarbGuard.carbLimit(); // افتراضي 100غ
        final today = await TrackerStore.getDay(at);
        final todayCarbs = (today['carb'] as num?)?.toDouble() ?? 0.0;
        if (carbsGrams >= 40) {
          await _showHighCarbNudge(context, carbsGrams.toInt(), limit.toInt(), isKeto: false);
        }
        if (todayCarbs + carbsGrams > limit) {
          final ok = await _confirmExceedCarb(context, (todayCarbs + carbsGrams).toInt(), limit.toInt(), title: 'تجاوز حد الكارب (لو كارب)');
          if (!ok) return false;
        }
      }
    } catch (_) {}
    // 2.8) عالي البروتين — تنبيه ناعم إذا الوجبة لا تساعد الهدف
    try {
      final hpOn = await HighProteinGuard.isActive();
      if (hpOn) {
        final mealMin = await HighProteinGuard.mealMinProtein();
        final target = await HighProteinGuard.targetProtein();
        final today = await TrackerStore.getDay(at);
        final todayProtein = (today['protein'] as num?)?.toDouble() ?? 0.0;
        if (calories >= 120 && proteinGrams < mealMin) {
          await _showLowProteinNudge(context, proteinGrams.toInt(), mealMin.toInt());
        }
        if (todayProtein + proteinGrams < target * 0.45 && DateTime.now().hour >= 17) {
          await _showProteinBehindNudge(context, (target - todayProtein - proteinGrams).clamp(0, 999).toInt());
        }
      }
    } catch (_) {}

    // 2.9) البحر المتوسط — تنبيه جودة الطبق إذا الدهون عالية أو الوجبة غير متوازنة
    try {
      final medOn = await MediterraneanGuard.isActive();
      if (medOn) {
        final fatLimit = await MediterraneanGuard.fatNudgeLimit();
        if (fatGrams >= fatLimit) {
          await _showMediterraneanFatNudge(context, fatGrams.toInt(), fatLimit.toInt());
        } else if (calories >= 450 && proteinGrams < 15 && carbsGrams > 60) {
          await _showMediterraneanPlateNudge(context);
        }
      }
    } catch (_) {}

    return true;
  }

  // ====== واجهات أنيقة للرسائل ======

  static Future<void> _showFastingBlockerSheet(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 44, height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant, borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.no_food_rounded, color: cs.error, size: 28),
                  const SizedBox(width: 10),
                  Text('وضع الصيام مفعّل',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.error.withOpacity(0.25)),
                ),
                child: Text('لا يمكنك تسجيل وجبة الآن أثناء نافذة الصيام.',
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text('تلميح: يمكنك إنهاء الصيام من صفحة الصيام.',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: ()=> Navigator.pop(ctx),
                child: const Text('فهمت'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  static void _showKetoHighCarbNotice(BuildContext context, double addCarbs) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.secondaryContainer,
        content: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            'تنبيه كيتو: هذه الوجبة مرتفعة بالكارب (${addCarbs.toStringAsFixed(0)}غ). '
            'حاول اختيار بدائل أقل كاربًا 👍',
            style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  static Future<void> _showKetoLimitBlockerSheet(
      BuildContext context, double today, double addCarbs, double limit) async {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 44, height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant, borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.block, color: cs.error, size: 28),
                  const SizedBox(width: 10),
                  Text('تجاوز حد الكارب',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.error.withOpacity(0.25)),
                ),
                child: Text(
                  'كارب اليوم الحالي: ${today.toStringAsFixed(0)}غ\n'
                  'إضافة هذه الوجبة: ${addCarbs.toStringAsFixed(0)}غ\n'
                  'الحد اليومي: ${limit.toStringAsFixed(0)}غ\n\n'
                  'لا يمكن إضافة هذه الوجبة لأنها ستتجاوز الحد.',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text('نصيحة: اختر بدائل قليلة الكارب (≤ 5غ).',
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: ()=> Navigator.pop(ctx),
                child: const Text('تمام'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================
// واجهة الصفحة
// =====================
class RegimenScreen extends StatefulWidget {
  const RegimenScreen({super.key});

  @override
  State<RegimenScreen> createState() => _RegimenScreenState();
}

class _RegimenScreenState extends State<RegimenScreen> {
  RegimenModel? _active;

  @override
  void initState() {
    super.initState();
    _refreshActive();
  }

  Future<void> _refreshActive() async {
    DietBus.invalidate();
    final m = await DietBus.getActive(); // يقرأ الحالة الفعلية ويقفل الأنظمة الأخرى تلقائيًا
    if (!mounted) return;
    setState(() => _active = m);
  }

  Future<void> _handleOpen(RegimenModel m) async {
  // افتح شاشة النظام
  if (m.id == 'if-16-8') {
    final fs = await FastingService.load();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: fs,
          child: const RegimenIF16Screen(),
        ),
      ),
    );
  } else if (m.id == 'keto') {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const KetoRegimenScreen()),
    );
  } else if (m.id == 'low-carb') {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegimenLowCarbScreen()),
    );
  } else if (m.id == 'low-fat') {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegimenLowFatScreen()),
    );
  } else if (m.id == 'high-protein') {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegimenHighProteinScreen()),
    );
  } else if (m.id == 'mediterranean') {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegimenMediterraneanScreen()),
    );
  }

  // بعد العودة، حدّث حالة "النشط"
  await _refreshActive();
}

  Future<void> _showExclusiveSheet(String wanted, String activeTitle) async {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 44, height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant, borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.lock, color: cs.primary, size: 28),
                  const SizedBox(width: 10),
                  Text('لا يمكن تفعيل نظامين',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withOpacity(0.25)),
                ),
                child: Text(
                  'النظام النشط حاليًا: $activeTitle\n'
                  'لا يمكنك فتح/تفعيل "$wanted" حتى تنهي النظام الحالي.',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: ()=> Navigator.pop(ctx),
                child: const Text('تمام'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final width = mq.size.width;

    // تخطيط شبكي: 1 عمود على الشاشات الضيقة، 2 أعمدة على الأوسع
    final isWide = width >= 520;
    final crossAxisCount = isWide ? 2 : 1;
    final tileHeight = 180.0;

    return PremiumGate(
      feature: PremiumFeature.regimens,
      child: Scaffold(
      appBar: AppBar(title: const Text('رجيمي')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshActive,
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + mq.padding.bottom),
            children: [
              // تلميح أعلى الصفحة عند وجود نظام مفعّل
              if (_active != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.primary.withOpacity(0.20)),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        Icon(Icons.info, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'النظام النشط: ${_active!.title}. لا يمكنك تفعيل نظامين معًا — أنهِ النظام الحالي أولًا.',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // شبكة البطاقات
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: tileHeight,
                ),
                itemCount: kAllRegimens.length,
                itemBuilder: (_, i) {
                  final m = kAllRegimens[i];
                  final isActive = _active?.id == m.id;
                  final blockedByOther = _active != null && !isActive; // يوجد نظام آخر مفعّل

                  return _RegimenCard(
                    model: m,
                    isActive: isActive,
                    blocked: blockedByOther,
                    onTap: blockedByOther
                        ? () => _showExclusiveSheet(m.title, _active!.title)
                        : () => _handleOpen(m),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

// =====================
// بطاقة رجيم فخمة
// =====================

class _RegimenCard extends StatelessWidget {
  final RegimenModel model;
  final bool isActive;
  final bool blocked;
  final VoidCallback onTap;

  const _RegimenCard({
    required this.model,
    required this.isActive,
    required this.blocked,
    required this.onTap,
  });

  Color _accentFor(ColorScheme cs) {
    switch (model.id) {
      case 'if-16-8':
        return cs.primary;
      case 'high-protein':
        return const Color(0xFF3B82F6);
      case 'mediterranean':
        return const Color(0xFF22C55E);
      case 'keto':
        return const Color(0xFF8B5CF6);
      case 'low-carb':
        return const Color(0xFFF97316);
      case 'low-fat':
        return const Color(0xFF06B6D4);
      default:
        return cs.primary;
    }
  }

  IconData _iconFor() {
    switch (model.id) {
      case 'if-16-8':
        return Icons.schedule_rounded;
      case 'high-protein':
        return Icons.fitness_center_rounded;
      case 'mediterranean':
        return Icons.spa_rounded;
      case 'keto':
        return Icons.local_fire_department_rounded;
      case 'low-carb':
        return Icons.grain_rounded;
      case 'low-fat':
        return Icons.favorite_rounded;
      default:
        return Icons.health_and_safety_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rawAccent = _accentFor(cs);
    final accent = isDark ? const Color(0xFFB8C2BA) : rawAccent;
    final cardBg = isDark ? const Color(0xFF242526) : Colors.white;

    return Stack(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              height: 176,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isActive
                      ? accent.withOpacity(isDark ? 0.32 : 0.44)
                      : cs.outlineVariant.withOpacity(isDark ? 0.34 : 0.65),
                  width: isActive ? 1.3 : 1,
                ),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.045),
                          blurRadius: 18,
                          offset: const Offset(0, 9),
                        ),
                      ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      model.title,
                                      style: txt.titleMedium?.copyWith(
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.w900,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF303234) : rawAccent.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: isDark ? Colors.white.withOpacity(0.08) : rawAccent.withOpacity(.25),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle,
                                            size: 15,
                                            color: isDark ? const Color(0xFFD7DED7) : rawAccent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'مفعل',
                                            style: TextStyle(
                                              color: isDark ? const Color(0xFFD7DED7) : rawAccent,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                model.goal,
                                style: txt.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: isDark ? const Color(0xFF2D2F31) : rawAccent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showRegimenInfoSheet(context, model),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? Colors.white.withOpacity(0.07) : rawAccent.withOpacity(0.14),
                                ),
                              ),
                              child: Icon(
                                Icons.info_outline_rounded,
                                color: isDark ? const Color(0xFFD0D5D1) : rawAccent,
                                size: 19,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      children: model.benefits.take(3).map((b) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2C2D2F)
                                : rawAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.065)
                                  : rawAccent.withOpacity(0.14),
                            ),
                          ),
                          child: Text(
                            b,
                            style: TextStyle(
                              color: isDark ? cs.onSurfaceVariant : cs.onSurface,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        if (blocked)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(isDark ? 0.54 : 0.38),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? cs.surfaceVariant : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, color: cs.onSurfaceVariant, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'هناك نظام آخر مُفعَّل',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _showRegimenInfoSheet(BuildContext context, RegimenModel m) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;

  String usage;
  switch (m.id) {
    case 'if-16-8':
      usage = 'اختَر نافذة أكل 8 ساعات وصُم 16 ساعة. ابدأ تدريجيًا وزِد مدّة الصيام على راحتك.';
      break;
    case 'keto':
      usage = 'اخفض الكارب لأقل من ~20–30غ يوميًا، وزد الدهون الصحية، ووزّع البروتين بشكل معتدل.';
      break;
    case 'low-carb':
      usage = 'خفّض الكارب تدريجيًا إلى ~50–130غ يوميًا حسب هدفك، وركّز على مصادر عالية الألياف.';
      break;
    case 'low-fat':
      usage = 'قلّل الدهون المشبعة، واستخدم طرق طهي خفيفة (هوائي/شوي)، ووزّع الدهون الصحية ضمن الحد.';
      break;
    case 'high-protein':
      usage = 'اضبط هدف البروتين اليومي والحد الأدنى لكل وجبة. وازن سينبهك إذا كانت وجبتك قليلة البروتين أو تأخرت عن هدف اليوم.';
      break;
    case 'mediterranean':
      usage = 'ركّز على طبق متوازن: خضار + بروتين + كارب كامل + دهون صحية بكمية محسوبة. وازن يرسل تذكيرات وينبه للدهون العالية.';
      break;
    default:
      usage = 'اتبع الإرشادات العامة حسب هدفك الغذائي.';
  }

  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.help_outline, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.title,
                      style: txt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(m.goal, style: txt.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.7))),

              const SizedBox(height: 16),
              _InfoSection(
                title: 'كيف أستخدمه؟',
                bullets: [usage],
              ),
              const SizedBox(height: 12),
              if (m.benefits.isNotEmpty) _InfoSection(title: 'الفوائد', bullets: m.benefits),
              if (m.risks.isNotEmpty) const SizedBox(height: 12),
              if (m.risks.isNotEmpty) _InfoSection(title: 'المخاطر/التحفظات', bullets: m.risks),
              if (m.popularFoods.isNotEmpty) const SizedBox(height: 12),
              if (m.popularFoods.isNotEmpty) _InfoSection(title: 'أطعمة مناسبة', bullets: m.popularFoods),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                  label: const Text('إغلاق'),
                ),
              ),
              SizedBox(height: MediaQuery.of(ctx).padding.bottom),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoSection extends StatelessWidget {
  final String title;
  final List<String> bullets;
  const _InfoSection({required this.title, required this.bullets});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: txt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...bullets.map((b) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 6),
                    Container(
                      width: 6, height: 6,
                      margin: const EdgeInsets.only(top: 7, left: 8, right: 8),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(child: Text(b, style: txt.bodyMedium)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// =======================
// Helpers (top-level) للتنبيه/التأكيد
// =======================

Future<void> _showLowProteinNudge(BuildContext context, int grams, int min) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.fitness_center_rounded, color: cs.primary, size: 48),
            const SizedBox(height: 8),
            Text('وجبة قليلة البروتين', style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('هذه الوجبة فيها تقريبًا ${grams}غ بروتين. هدفك في رجيم عالي البروتين أن تكون الوجبة حول ${min}غ أو أكثر.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showProteinBehindNudge(BuildContext context, int remaining) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.track_changes_rounded, color: cs.primary, size: 48),
            const SizedBox(height: 8),
            Text('باقي لك بروتين كثير', style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('بعد هذه الوجبة، باقي لك تقريبًا ${remaining}غ بروتين. حاول تختار وجبة أو سناك بروتين أعلى لاحقًا.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showMediterraneanFatNudge(BuildContext context, int grams, int limit) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.eco_rounded, color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.teal, size: 48),
            const SizedBox(height: 8),
            Text('وجبة عالية الدهون', style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('هذه الوجبة فيها تقريبًا ${grams}غ دهون. في البحر المتوسط الدهون الصحية ممتازة، لكن الكمية ما زالت مهمة. حد التنبيه عندك ${limit}غ.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showMediterraneanPlateNudge(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.restaurant_rounded, color: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.teal, size: 48),
            const SizedBox(height: 8),
            Text('وازن الطبق أكثر', style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('الوجبة تبدو عالية بالكارب وقليلة البروتين. جرّب تضيف بروتين أو خضار أكثر عشان تناسب البحر المتوسط.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تمام')),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showHighCarbNudge(BuildContext context, int grams, int limit, {bool isKeto = false}) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  final title = isKeto ? 'وجبة عالية الكارب (كيتو)' : 'وجبة عالية الكارب';
  final msg = isKeto
      ? 'هذه الوجبة تحتوي ~${grams} غ كارب وقد تؤثر على الكيتو.'
      : 'هذه الوجبة تحتوي ~${grams} غ كارب. حدّك اليومي هو ${limit} غ.';
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.info, color: cs.primary, size: 48),
            const SizedBox(height: 8),
            Text(title, style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(msg, style: txt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('تمام')),
          ],
        ),
      ),
    ),
  );
}

Future<bool> _confirmExceedCarb(BuildContext context, int total, int limit, {String title = 'تجاوز حد الكارب'}) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  return await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.warning_amber_rounded, color: cs.error, size: 52),
            const SizedBox(height: 8),
            Text(title, style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('الإجمالي بعد الإضافة سيكون ~${total} غ > الحد ${limit} غ.', style: txt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: ()=> Navigator.pop(ctx, false), child: const Text('إلغاء'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: ()=> Navigator.pop(ctx, true), child: const Text('متابعة'))),
              ],
            ),
          ],
        ),
      ),
    ),
  ) ?? false;
}

Future<void> _showHighFatNudge(BuildContext context, int grams, int limit) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.info_outline, color: cs.primary, size: 48),
            const SizedBox(height: 8),
            Text('وجبة عالية الدهون', style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('هذه الوجبة تحتوي ~${grams}غ دهون. حدّك اليومي هو ${limit}غ.', style: txt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('تمام')),
          ],
        ),
      ),
    ),
  );
}

Future<bool> _confirmExceedFat(BuildContext context, int total, int limit, {String title = 'تجاوز حد الدهون'}) async {
  final cs = Theme.of(context).colorScheme;
  final txt = Theme.of(context).textTheme;
  return await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(999))),
            const SizedBox(height: 12),
            Icon(Icons.warning_amber_rounded, color: cs.error, size: 52),
            const SizedBox(height: 8),
            Text(title, style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('الإجمالي بعد الإضافة سيكون ~${total}غ > الحد ${limit}غ.', style: txt.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: ()=> Navigator.pop(ctx, false), child: const Text('إلغاء'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: ()=> Navigator.pop(ctx, true), child: const Text('متابعة'))),
              ],
            ),
          ],
        ),
      ),
    ),
  ) ?? false;
}
