import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/diet_model.dart';

/// دمج عناصر القوائم إلى نص بفواصل عربية "، "
String j(List<String> items) => items.join('، ');

class DietProvider with ChangeNotifier {
  /// قائمة الرجيمات (نماذج جاهزة). تقدر تزيد/تنقص براحتك.
  final List<DietModel> diets = [
    // ===== إنقاص الوزن =====
    DietModel(
      id: 'low_cal',
      name: 'رجيم منخفض السعرات',
      goalType: 'إنقاص الوزن',
      benefits: j(['يدعم نزولًا آمنًا بتخفيض ~500 سعرة/يوم', 'يحسّن حساسية الإنسولين']),
      risks: j(['هبوط طاقة إن كان العجز كبيرًا', 'احتمال خسارة عضلية مع بروتين منخفض']),
      tips: j(['اطرح 500 من سعراتك الأساسية', 'احرص على بروتين كافٍ', 'اشرب ماء بكثرة']),
      recommendedFoods: j(['صدور دجاج', 'تونة', 'بيض', 'زبادي خالي الدسم', 'خضار ورقية']),
      calorieDelta: -500,
      proteinPerKg: 1.6,
    ),
    DietModel(
      id: 'keto',
      name: 'رجيم الكيتو',
      goalType: 'إنقاص الوزن',
      benefits: j(['تقليل الشهية لدى البعض', 'اعتماد الدهون للطاقة']),
      risks: j(['دوخة/إمساك بالبداية', 'نقص ألياف إن أهملت الخضار']),
      tips: j(['كارب منخفض جدًا', 'دهون صحية', 'بروتين معتدل']),
      recommendedFoods: j(['بيض', 'لحم', 'سمك دهني', 'أفوكادو', 'زيت زيتون', 'خضار ورقية']),
      carbCapGrams: 50,
      proteinPerKg: 1.6,
    ),

    // ===== الصيام المتقطع =====
    DietModel(
      id: 'if_16_8',
      name: 'صيام 16/8',
      goalType: 'الصيام المتقطع',
      benefits: j(['ينظم مواعيد الأكل', 'يساعد على تقليل السعرات تلقائيًا']),
      risks: j(['صداع مؤقت', 'جوع بالبداية']),
      tips: j(['ابدأ 16/8', 'حافظ على وجبات كاملة مغذية داخل نافذة الأكل']),
      recommendedFoods: j(['ماء', 'قهوة/شاي بدون سكر بالصيام', 'بروتين وخضار في الأكل']),
      eatStart: const TimeOfDay(hour: 12, minute: 0),
      eatEnd: const TimeOfDay(hour: 20, minute: 0),
      calorieDelta: -300,
      proteinPerKg: 1.6,
    ),

    // ===== زيادة الوزن =====
    DietModel(
      id: 'high_energy',
      name: 'رجيم عالي الطاقة',
      goalType: 'زيادة الوزن',
      benefits: j(['يرفع الوزن تدريجيًا', 'كثافة طاقة أعلى']),
      risks: j(['زيادة دهنية إن زادت الحلويات/الدهون المتحولة']),
      tips: j(['4–6 وجبات باليوم', 'أضف دهون صحية وكارب بكل وجبة']),
      recommendedFoods: j(['تمر', 'عسل', 'زبدة فول سوداني', 'شوفان', 'موز', 'حليب كامل الدسم']),
      calorieDelta: 400,
      proteinPerKg: 1.6,
    ),

    // ===== بناء العضلات =====
    DietModel(
      id: 'high_protein',
      name: 'رجيم عالي البروتين',
      goalType: 'بناء العضلات',
      benefits: j(['يدعم زيادة الكتلة العضلية', 'يشبع لفترة أطول']),
      risks: j(['قد يجهد الكِلى عند الإفراط لمن لديهم مشاكل مسبقة']),
      tips: j(['وزّع البروتين 3–5 وجبات', 'تغذية قبل/بعد التمرين']),
      recommendedFoods: j(['دجاج', 'سمك', 'بيض', 'لبن', 'عدس', 'بروتين مصل']),
      proteinPerKg: 1.8,
      calorieDelta: 200,
    ),

    // ===== خفض الدهون =====
    DietModel(
      id: 'low_fat',
      name: 'رجيم منخفض الدهون',
      goalType: 'خفض الدهون',
      benefits: j(['يقلّل السعرات من الدهون', 'يدعم صحة القلب']),
      risks: j(['قد يقل امتصاص ADEK مع انخفاض دهون شديد']),
      tips: j(['مشوي/هوائي', 'راقب الدهون المضافة']),
      recommendedFoods: j(['مشوي', 'مسلوق', 'ألبان قليلة الدسم', 'لحم/سمك بدون جلد']),
      fatPctMax: 0.25,
      calorieDelta: -300,
    ),
    DietModel(
      id: 'low_carb',
      name: 'رجيم قليل الكربوهيدرات',
      goalType: 'خفض الدهون',
      benefits: j(['يقلل الإنسولين', 'يعزّز استخدام الدهون للطاقة']),
      risks: j(['نقص طاقة بالبداية']),
      tips: j(['تجنّب السكر والنشويات المكررة', 'ركز على البروتين والخضار']),
      recommendedFoods: j(['لحوم', 'بيض', 'خضار ورقية', 'مكسرات باعتدال']),
      carbCapGrams: 100,
      calorieDelta: -300,
      proteinPerKg: 1.6,
    ),

    // ===== خفض ضغط الدم =====
    DietModel(
      id: 'dash_bp',
      name: 'رجيم DASH (خفض الضغط)',
      goalType: 'خفض ضغط الدم',
      benefits: j(['يخفض الضغط', 'يزيد الألياف']),
      risks: j(['النتائج تدريجية']),
      tips: j(['قلّل الصوديوم', 'أكثر من الخضار والفواكه']),
      recommendedFoods: j(['خضار', 'فواكه', 'حبوب كاملة', 'لبن قليل الدسم']),
      sodiumCapMg: 1500,
      calorieDelta: -100,
    ),

    // ===== ضبط مستوى السكر =====
    DietModel(
      id: 'low_gi',
      name: 'رجيم منخفض المؤشر الجلايسيمي',
      goalType: 'ضبط مستوى السكر',
      benefits: j(['يبطّئ امتصاص الجلوكوز', 'يحسّن الشبع']),
      risks: j(['يتطلب انتقاء أدق للأطعمة']),
      tips: j(['شوفان/شعير/بقول', 'فاكهة كاملة بدل العصير']),
      recommendedFoods: j(['شوفان', 'عدس', 'شعير', 'تفاح كامل', 'خضار كثيرة']),
      carbCapGrams: 150,
    ),

    // ===== نباتي =====
    DietModel(
      id: 'vegan_hp',
      name: 'نباتي عالي البروتين',
      goalType: 'اتباع رجيم نباتي',
      benefits: j(['يحافظ على العضلات بدون لحوم']),
      risks: j(['أصعب خارج المنزل — حضّر وجباتك']),
      tips: j(['بقوليات وصويا وكينوا وبذور']),
      recommendedFoods: j(['عدس', 'حمص', 'توفو/تمبيه', 'كينوا', 'مكسرات']),
      proteinPerKg: 1.7,
    ),

    // ===== نمط حياة صحي / طاقة خفيفة =====
    DietModel(
      id: 'light_balanced',
      name: 'رجيم متوازن خفيف',
      goalType: 'نمط حياة صحي',
      benefits: j(['طاقة بدون ثِقل', 'مرن وسهل الالتزام']),
      risks: j(['قد لا يناسب التضخيم الشديد']),
      tips: j(['وجبات صغيرة متكررة مع بروتين', 'خضار وألياف يوميًا']),
      recommendedFoods: j(['فواكه', 'شوفان', 'لبن قليل الدسم', 'مكسرات باعتدال']),
      calorieDelta: 0,
      proteinPerKg: 1.6,
    ),
  ];

  DietModel? _activeDiet;
  DietModel? get activeDiet => _activeDiet;

  /// استرجاع الرجيم المفعّل من التخزين (إن وُجد)
  Future<void> loadActiveDiet() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('activeDietId');
    if (id != null) {
      _activeDiet = diets.firstWhere(
        (d) => d.id == id || d.name == id,
        orElse: () => diets.first,
      );
      notifyListeners();
    }
  }

  /// ضبط الرجيم المفعّل وحفظه
  Future<void> setActiveDietById(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      _activeDiet = null;
      await prefs.remove('activeDietId');
    } else {
      _activeDiet = diets.firstWhere(
        (d) => d.id == id || d.name == id,
        orElse: () => diets.first,
      );
      await prefs.setString('activeDietId', _activeDiet!.id);
    }
    notifyListeners();
  }

  /// ✅ يختار رجيم تلقائيًا حسب الهدف ويجعله Active
  Future<void> assignDietBasedOnGoal(String goal) async {
    // نوحّد بعض الصيغ المختلفة لنفس الهدف
    final normalized = _normalizeGoal(goal);

    String pickId;
    switch (normalized) {
      case 'إنقاص الوزن':
        pickId = 'low_cal';
        break;
      case 'زيادة الوزن':
        pickId = 'high_energy';
        break;
      case 'بناء العضلات':
        pickId = 'high_protein';
        break;
      case 'خفض الدهون':
        pickId = 'low_fat'; // بإمكانك تبدّل لـ 'low_carb' حسب تفضيلك
        break;
      case 'الصيام المتقطع':
        pickId = 'if_16_8';
        break;
      case 'ضبط مستوى السكر':
        pickId = 'low_gi';
        break;
      case 'نمط حياة صحي':
      case 'زيادة النشاط اليومي':
      case 'زيادة النشاط اليومي ورفع الطاقة':
      case 'تحسين الصحة العامة':
        pickId = 'light_balanced';
        break;
      default:
        pickId = 'light_balanced';
    }

    await setActiveDietById(pickId);
  }

  /// توحيد صيغ الأهداف
  String _normalizeGoal(String g) {
    g = g.trim();
    if (g == 'ضبط مستوى السكر في الدم') return 'ضبط مستوى السكر';
    if (g == 'رفع الطاقة والحيوية') return 'زيادة النشاط اليومي ورفع الطاقة';
    return g;
    }
}
