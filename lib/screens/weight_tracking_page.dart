import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;


import 'package:flutter/material.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:health/health.dart';

// PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✅ المصدر الموحّد لاستهلاك اليوم (كما في الصفحة الرئيسية)
import '../services/tracker_store.dart';
import '../water/water_store.dart';
import '../data/app_repository.dart';


// ==== Global helpers for insights ====
double _toD(v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

/// Sum possible nutrient maps/lists (k/cal, p, c, f)
Map<String, double> sumFromIterable(Iterable items) {
  double cal = 0, p = 0, c = 0, f = 0;
  for (final it in items) {
    if (it is String) {
      try {
        final m = jsonDecode(it);
        cal += _toD(m['k'] ?? m['cal']);
        p += _toD(m['p'] ?? m['protein']);
        c += _toD(m['c'] ?? m['carb']);
        f += _toD(m['f'] ?? m['fat']);
      } catch (_) {}
    } else if (it is Map) {
      cal += _toD(it['k'] ?? it['cal']);
      p += _toD(it['p'] ?? it['protein']);
      c += _toD(it['c'] ?? it['carb']);
      f += _toD(it['f'] ?? it['fat']);
    }
  }
  return {'cal': cal, 'protein': p, 'carb': c, 'fat': f};
}

/// ========= بث لحظي لتحديث الوزن =========
class WeightLiveBus {
  static final StreamController<void> _ctrl =
      StreamController<void>.broadcast();
  static Stream<void> get stream => _ctrl.stream;
  static void ping() {
    if (!_ctrl.isClosed) _ctrl.add(null);
  }
}

/// ========= Helpers =========
String _todayKey() => DateTime.now().toIso8601String().split('T').first;

/// يحوّل أي تمثيل للتاريخ إلى مفتاح yyyy-MM-dd (يدعم ISO/epoch وبعض الصيغ الشائعة).
String? _normalizeYmd(dynamic value) {
  if (value == null) return null;

  DateTime? dt;
  if (value is int) {
    dt = DateTime.fromMillisecondsSinceEpoch(value);
  } else if (value is double) {
    dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
  } else {
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    // ISO أو ISO مع مسافة بدل T
    dt = DateTime.tryParse(raw) ?? DateTime.tryParse(raw.replaceFirst(' ', 'T'));

    // صيغ شائعة
    if (dt == null) {
      final fmts = <DateFormat>[
        DateFormat('yyyy/MM/dd'),
        DateFormat('dd/MM/yyyy'),
        DateFormat('d/M/yyyy'),
        DateFormat('dd-MM-yyyy'),
        DateFormat('d-M-yyyy'),
        DateFormat('yyyy-MM-dd'),
      ];
      for (final f in fmts) {
        try {
          dt = f.parseStrict(raw);
          break;
        } catch (_) {}
      }
    }
  }

  if (dt == null) return null;
  final d0 = DateTime(dt.year, dt.month, dt.day);
  return DateFormat('yyyy-MM-dd').format(d0);
}


Future<String?> _currentEmail() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('currentEmail');
}
Future<String?> _currentGoal() async {
  final prefs = await SharedPreferences.getInstance();
  final email = prefs.getString('currentEmail');
  // أولوية: المفاتيح المرتبطة بالبريد من صفحة "بياناتي"
  if (email != null) {
    final g = prefs.getString('goal_$email');
    if (g != null && g.trim().isNotEmpty) return g;
  }
  // بدائل قديمة إن وُجدت
  return prefs.getString('goal') ??
         prefs.getString('user_goal') ??
         prefs.getString('plan_goal') ??
         prefs.getString('target_goal');
}


/// ✅ غلاف بسيط يحافظ على النداءات الموجودة في هذا الملف
class DailyTrackerStore {
  static Future<void> addIntake({
    required double cal,
    required double protein,
    required double carb,
    required double fat,
  }) {
    return TrackerStore.addIntake(
      cal: cal,
      protein: protein,
      carb: carb,
      fat: fat,
    );
  }
}

/// قراءة مجاميع يوم محدد (متوافقة مع صيغ متعددة قديمة/حديثة).
Future<Map<String, double>> _readTotalsForDate(
  SharedPreferences prefs,
  String email,
  String ymd,
) async {
  double toD(v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  // 1) المفاتيح الأساسية المستخدمة في صفحة الهوم
  try {
    final totalsKey = 'kcal_daytotals_${email}_$ymd';
    final rawTotals = prefs.getString(totalsKey);
    if (rawTotals != null) {
      final m = jsonDecode(rawTotals);
      if (m is Map) {
        final k = toD(m['k']);
        final p = toD(m['p']);
        final c = toD(m['c']);
        final f = toD(m['f']);
        if (k > 0 || p > 0 || c > 0 || f > 0) {
          return {'cal': k, 'p': p, 'c': c, 'f': f};
        }
      }
    }
  } catch (_) {}

  // 2) نفس fallback تبع الهوم: قائمة intake_entries تجمع k أو cal وباقي الماكروز
  try {
    final entriesKey = 'intake_entries_${email}_$ymd';
    final raw = prefs.getString(entriesKey);
    if (raw != null) {
      final list = jsonDecode(raw);
      if (list is List) {
        double k=0, p=0, c=0, f=0;
        for (final e in list) {
          if (e is Map) {
            final kk = e['k'] ?? e['cal'];
            k += toD(kk);
            p += toD(e['p'] ?? e['protein'] ?? e['protein_g']);
            c += toD(e['c'] ?? e['carb'] ?? e['carbs'] ?? e['carb_g']);
            f += toD(e['f'] ?? e['fat'] ?? e['fat_g']);
          }
        }
        if (k > 0 || p > 0 || c > 0 || f > 0) {
          return {'cal': k, 'p': p, 'c': c, 'f': f};
        }
      }
    }
  } catch (_) {}

  // 3) فallback موسّع (كما كان) يدعم مفاتيح أخرى محتملة
  double _calFrom(Map m) {
    final k = m['k'] ?? m['cal'] ?? m['kcal'] ?? m['calories'] ?? (m['energy'] is Map ? m['energy']['kcal'] : m['energy']);
    final p = m['p'] ?? m['protein'] ?? m['protein_g'];
    final c = m['c'] ?? m['carb'] ?? m['carbs'] ?? m['carb_g'];
    final f = m['f'] ?? m['fat'] ?? m['fat_g'];
    double cal = toD(k ?? 0);
    if (cal == 0) cal = toD(p)*4 + toD(c)*4 + toD(f)*9;
    return cal;
  }
  Map<String, double> sumFromIterable(Iterable items) {
    double cal = 0, p = 0, c = 0, f = 0;
    for (final it in items) {
      try {
        Map m;
        if (it is String) { m = Map<String, dynamic>.from(jsonDecode(it)); }
        else if (it is Map) { m = Map<String, dynamic>.from(it); }
        else { continue; }
        cal += _calFrom(m);
        p   += toD(m['p'] ?? m['protein'] ?? m['protein_g']);
        c   += toD(m['c'] ?? m['carb'] ?? m['carbs'] ?? m['carb_g']);
        f   += toD(m['f'] ?? m['fat'] ?? m['fat_g']);
      } catch (_) {}
    }
    return {'cal': cal, 'p': p, 'c': c, 'f': f};
  }

  final entryListKeys = <String>[
    'intake_entries_${email}_$ymd',
    'kcal_entries_${email}_$ymd',
    'intakes_${email}_$ymd',
    'meals_${email}_$ymd',
    'food_log_${email}_$ymd',
    'food_log_${ymd}_$email',
  ];
  for (final k in entryListKeys) {
    final raw = prefs.getString(k);
    if (raw == null) continue;
    try {
      final data = jsonDecode(raw);
      if (data is List) {
        final s = sumFromIterable(data);
        if (s.values.any((v)=> v>0)) return s;
      } else if (data is Map) {
        if (data['items'] is List) {
          final s = sumFromIterable(data['items']);
          if (s.values.any((v)=> v>0)) return s;
        } else {
          final m = Map<String, dynamic>.from(data);
          final cal = _calFrom(m);
          final p = toD(m['p'] ?? m['protein'] ?? m['protein_g']);
          final c = toD(m['c'] ?? m['carb'] ?? m['carbs'] ?? m['carb_g']);
          final f = toD(m['f'] ?? m['fat'] ?? m['fat_g']);
          if (cal>0 || p>0 || c>0 || f>0) return {'cal': cal, 'p': p, 'c': c, 'f': f};
        }
      }
    } catch (_) {}
  }

  return {'cal': 0, 'p': 0, 'c': 0, 'f': 0};
}

/// ====== نموذج معلومات المستخدم للتقرير ======
class _UserProfile {
  final String email;
  final String fullName;
  final String goal;
  final String? gender; // "ذكر"/"أنثى" أو null
  final double? heightCm;
  final double? weightKg;
  final int? age;
  _UserProfile({
    required this.email,
    required this.fullName,
    required this.goal,
    this.gender,
    this.heightCm,
    this.weightKg,
    this.age,
  });

  double? get bmi {
    if (heightCm == null || weightKg == null) return null;
    final h = heightCm! / 100.0;
    if (h <= 0) return null;
    return weightKg! / (h * h);
  }

  String get bmiClass {
    final b = bmi;
    if (b == null) return 'غير متوفر';
    if (b < 18.5) return 'نحافة';
    if (b < 25) return 'طبيعي';
    if (b < 30) return 'زيادة وزن';
    return 'سمنة';
  }

  double? get bmr {
    // Mifflin–St Jeor (تقريبي إذا توفر العمر/الجنس/الطول/الوزن)
    if (heightCm == null || weightKg == null || age == null || gender == null) {
      return null;
    }
    final w = weightKg!;
    final h = heightCm!;
    final a = age!;
    if (gender == 'أنثى' || gender?.toLowerCase() == 'female') {
      return (10 * w) + (6.25 * h) - (5 * a) - 161;
    }
    return (10 * w) + (6.25 * h) - (5 * a) + 5; // ذكر
  }
}


String? _readStringFlexible(SharedPreferences prefs, String key) {
  final v = prefs.get(key);
  if (v == null) return null;
  if (v is String) return v;
  // Convert non-strings safely (bool/num) to string
  return v.toString();
}


String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return null;
}

String _joinNameParts(String? first, String? last) {
  final f = (first ?? '').trim();
  final l = (last ?? '').trim();
  return [f, l].where((e) => e.isNotEmpty).join(' ').trim();
}

/// محاولة استخراج الاسم من وثيقة المستخدم في Firestore مع دعم عدة مفاتيح شائعة
String _extractFullNameFromUserDoc(Map<String, dynamic> data) {
  String? pick(String key) {
    final v = _asString(data[key]);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  // مباشر
  final direct = pick('fullName') ??
      pick('name') ??
      pick('displayName') ??
      pick('userName') ??
      pick('username');

  if (direct != null) return direct;

  // profile
  final profile = (data['profile'] is Map) ? Map<String, dynamic>.from(data['profile'] as Map) : null;
  if (profile != null) {
    final p = _asString(profile['fullName']) ??
        _asString(profile['name']) ??
        _asString(profile['displayName']) ??
        _asString(profile['userName']);
    if (p != null && p.trim().isNotEmpty) return p.trim();

    final pf = _asString(profile['firstName']);
    final pl = _asString(profile['lastName']);
    final joined = _joinNameParts(pf, pl);
    if (joined.isNotEmpty) return joined;
  }

  // metrics
  final metrics = (data['metrics'] is Map) ? Map<String, dynamic>.from(data['metrics'] as Map) : null;
  if (metrics != null) {
    final mname = _asString(metrics['fullName']) ??
        _asString(metrics['name']) ??
        _asString(metrics['displayName']);
    if (mname != null && mname.trim().isNotEmpty) return mname.trim();

    final mf = _asString(metrics['firstName']);
    final ml = _asString(metrics['lastName']);
    final joined = _joinNameParts(mf, ml);
    if (joined.isNotEmpty) return joined;
  }

  // في حال تخزين الاسم كـ first/last على الجذر
  final f = _asString(data['firstName']);
  final l = _asString(data['lastName']);
  final joined = _joinNameParts(f, l);
  if (joined.isNotEmpty) return joined;

  return '';
}
Future<_UserProfile> _loadUserProfile() async {
  final prefs = await SharedPreferences.getInstance();

  final user = FirebaseAuth.instance.currentUser;
  final email = (user?.email ?? await _currentEmail() ?? 'unknown_user').trim();

  String fullName = '';

  // 1) حاول Firestore أولاً (ثابت بين الأجهزة + يتغير لحظيًا)
  try {
    if (user != null) {
      final usersCol = FirebaseFirestore.instance.collection('users');
      // بعض المشاريع تستخدم uid كـ docId، وبعضها تستخدم email
      var snap = await usersCol.doc(user.uid).get();
      if (!snap.exists && (user.email ?? '').trim().isNotEmpty) {
        snap = await usersCol.doc(user.email!.trim()).get();
      }
      if (snap.exists) {
        final data = (snap.data() ?? <String, dynamic>{});
        fullName = _extractFullNameFromUserDoc(data);
        // خزّن محليًا لسرعة فتح الشاشات الأخرى
        if (fullName.trim().isNotEmpty && email.isNotEmpty) {
          final parts = fullName.trim().split(RegExp(r'\s+'));
          final first = parts.isNotEmpty ? parts.first : '';
          final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
          await prefs.setString('firstName_$email', first);
          await prefs.setString('lastName_$email', last);
          await prefs.setString('fullName_$email', fullName.trim());
        }
      }
    }
  } catch (_) {}

  // 2) fallback: displayName من FirebaseAuth
  if (fullName.trim().isEmpty) {
    fullName = (user?.displayName ?? '').trim();
  }

  // 3) fallback: أي مفاتيح محلية شائعة
  if (fullName.trim().isEmpty) {
    final storedFull = prefs.getString('fullName_$email') ?? '';
    final first = prefs.getString('firstName_$email') ?? prefs.getString('name_$email') ?? '';
    final last = prefs.getString('lastName_$email') ?? '';
    fullName = storedFull.trim().isNotEmpty ? storedFull.trim() : _joinNameParts(first, last);
  }

  // مفاتيح شائعة للطول/العمر/الجنس
  double? height = prefs.getDouble('height_cm_$email') ??
      prefs.getDouble('height_$email') ??
      ((prefs.getInt('height_$email'))?.toDouble());

  int? age = prefs.getInt('age_$email') ??
      ((prefs.getString('age_$email') != null)
          ? int.tryParse(prefs.getString('age_$email')!)
          : null);

  String? gender = _readStringFlexible(prefs, 'gender_$email');
  if (gender != null && gender.trim().isEmpty) gender = null;

  final goal = _readStringFlexible(prefs, 'goal_$email') ?? 'نمط حياة صحي';

  final weight =
      prefs.getDouble('current_weight_$email') ?? prefs.getDouble('weight_$email');

  return _UserProfile(
    email: email,
    fullName: fullName.trim(),
    goal: goal,
    gender: gender,
    heightCm: height,
    weightKg: weight,
    age: age,
  );
}



/// ========= Screen =========
class WeightTrackingPage extends StatefulWidget {
  const WeightTrackingPage({super.key});
  @override
  State<WeightTrackingPage> createState() => _WeightTrackingPageState();
}


// ===== Helpers: data holders for charting/PDF (moved to top-level) =====


// ===== Helpers: data holders for charting/PDF =====
class _Series {
  final List<DateTime> dates;

  // التغذية
  final List<double> calories;
  final List<double> protein;
  final List<double> carb;
  final List<double> fat;

  // الترطيب (بالمل)
  final List<double> waterMl;

  // النشاط
  final List<int> steps;
  final List<int> burned;

  // الوزن
  final List<double?> weights;

  const _Series({
    required this.dates,
    required this.calories,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.waterMl,
    required this.steps,
    required this.burned,
    required this.weights,
  });
}

class _Grouped {
  final List<String> labelsText;
  final List<double> values;
  final List<DateTime> labelsDates;
  const _Grouped({
    required this.labelsText,
    required this.values,
    required this.labelsDates,
  });
}

class _GroupedByDate {
  final List<DateTime> labels;
  final List<double> values;
  const _GroupedByDate({
    required this.labels,
    required this.values,
  });
}

class _Agg {
  final DateTime label;
  final double sum;
  final int count;
  const _Agg(this.label, this.sum, this.count);
  _Agg add(double v) => _Agg(label, sum + v, count + 1);
}
// ===== End helpers =====

  
class _WeightTrackingPageState extends State<WeightTrackingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  Timer? _tick;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;

  // كاش استرجاع بيانات الأيام من السحابة لهذه التبويبة.
  // كان موجود في تبويبة سجل السعرات فقط، لذلك صار الخطأ عند البناء.
  bool _cloudDailyRestoreDone = false;
  List<Map<String, dynamic>> _cachedRemoteDays = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _initUserNameSync();
  }

  

  Future<void> _initUserNameSync() async {
    // ابدأ بالقيمة الحالية إن وجدت
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.trim().isNotEmpty) {
      setState(() => _displayName = user.displayName!.trim());
    }

    // اقرأ من التخزين المحلي كـ fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = (user?.email ?? await _currentEmail() ?? '').trim();
      if (email.isNotEmpty) {
        final stored = (prefs.getString('fullName_$email') ?? '').trim();
        final first = (prefs.getString('firstName_$email') ?? '').trim();
        final last = (prefs.getString('lastName_$email') ?? '').trim();
        final local = stored.isNotEmpty ? stored : _joinNameParts(first, last);
        if (local.isNotEmpty && mounted) {
          setState(() => _displayName = local);
        }
      }
    } catch (_) {}

    // استمع لتغيرات الاسم في Firestore حتى يتحدث فورًا عبر الأجهزة
    try {
      if (user == null) return;
      _userNameSub?.cancel();
      final usersCol = FirebaseFirestore.instance.collection('users');
      // اختر المرجع الصحيح (uid أو email) لتوحيد الاسم عبر الأجهزة
      DocumentReference<Map<String, dynamic>> ref = usersCol.doc(user.uid);
      try {
        final s1 = await ref.get();
        if (!s1.exists && (user.email ?? '').trim().isNotEmpty) {
          ref = usersCol.doc(user.email!.trim());
        }
      } catch (_) {
        if ((user.email ?? '').trim().isNotEmpty) {
          ref = usersCol.doc(user.email!.trim());
        }
      }

      _userNameSub = ref.snapshots().listen((snap) async {
        if (!snap.exists) return;
        final data = snap.data() ?? <String, dynamic>{};
        final name = _extractFullNameFromUserDoc(data).trim();
        if (name.isEmpty) return;

        if (mounted) setState(() => _displayName = name);

        // خزّن محليًا
        try {
          final prefs = await SharedPreferences.getInstance();
          final email = (user.email ?? '').trim();
          if (email.isNotEmpty) {
            final parts = name.split(RegExp(r'\s+'));
            final first = parts.isNotEmpty ? parts.first : '';
            final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
            await prefs.setString('firstName_$email', first);
            await prefs.setString('lastName_$email', last);
            await prefs.setString('fullName_$email', name);
          }
        } catch (_) {}
      });
    } catch (_) {}
  }
@override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ====== زر تصدير PDF (مُحسَّن مع بيانات المستخدم) ======
  Future<void> _exportTrackingPdf(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final profile = await _loadUserProfile();
      final now = DateTime.now();

      final week = await _collectSeries(daysBack: 7);
      final month = await _collectSeries(daysBack: 30);
      final year = await _collectSeries(daysBack: 365);

      final tajawal =
          pw.Font.ttf(await rootBundle.load('assets/Tajawal-Regular.ttf'));

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: tajawal, bold: tajawal),
      );

      // ====== صفحة غلاف ======
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('تقرير التتبّع الصحي — تطبيق وازن',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo800,
                      )),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'تاريخ التوليد: ${DateFormat('yyyy/MM/dd HH:mm').format(now)}',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(8),
                      color: PdfColors.grey200,
                    ),
                    padding: const pw.EdgeInsets.all(10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _kv('الاسم', profile.fullName.isEmpty ? 'غير محدد' : profile.fullName),
                        _kv('البريد', profile.email),
                        _kv('الهدف', profile.goal),
                        _kv('الجنس', profile.gender ?? 'غير محدد'),
                        _kv('الطول', profile.heightCm != null ? '${profile.heightCm!.toStringAsFixed(0)} سم' : 'غير محدد'),
                        _kv('الوزن الحالي', profile.weightKg != null ? '${profile.weightKg!.toStringAsFixed(1)} كجم' : 'غير محدد'),
                        _kv('العمر', profile.age?.toString() ?? 'غير محدد'),
                        _kv('BMI', profile.bmi != null ? '${profile.bmi!.toStringAsFixed(1)} (${profile.bmiClass})' : 'غير متوفر'),
                        _kv('BMR تقديري', profile.bmr != null ? '${profile.bmr!.toStringAsFixed(0)} سعرة/يوم' : 'غير متوفر'),
          
        ],
                    ),
                  ),
                  pw.Spacer(),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text('© وازن — تقرير آلي للاستخدام الشخصي.',
                        style: const pw.TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      pw.Widget header(String title) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 18.0, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6.0),
              pw.Divider(),
            ],
          );

      // أسبوعي
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  header('التتبّع — أسبوعي'),
                  _sectionTitle('الأكل (سعرات) — آخر 7 أيام'),
                  _bars(
                    values: week.calories,
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                  ),
                  _statsTable(
                    columns: ['اليوم', 'سعرات'],
                    rows: List.generate(
                        week.dates.length,
                        (i) => [
                              DateFormat('yyyy/MM/dd').format(week.dates[i]),
                              week.calories[i].toStringAsFixed(0),
                            ]),
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الماكروز — بروتين/كارب/دهون (آخر 7 أيام)'),
                  _twoBarsSideBySide(
                    leftTitle: 'بروتين (جم)',
                    left: week.protein,
                    rightTitle: 'كارب (جم)',
                    right: week.carb,
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                  ),
                  pw.SizedBox(height: 6.0),
                  pw.Text('دهون (جم)',
                      style: pw.TextStyle(
                          fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
                  _bars(
                    values: week.fat,
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                    color: PdfColors.grey700,
                  ),
                  _statsTable(
                    columns: ['اليوم', 'بروتين', 'كارب', 'دهون'],
                    rows: List.generate(
                        week.dates.length,
                        (i) => [
                              DateFormat('yyyy/MM/dd').format(week.dates[i]),
                              week.protein[i].toStringAsFixed(0),
                              week.carb[i].toStringAsFixed(0),
                              week.fat[i].toStringAsFixed(0),
                            ]),
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الترطيب — ماء (مل)'),
                  _bars(
                    values: week.waterMl,
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                    color: PdfColors.teal600,
                  ),
                  _statsTable(
                    columns: ['اليوم', 'ماء (مل)'],
                    rows: List.generate(
                        week.dates.length,
                        (i) => [
                              DateFormat('yyyy/MM/dd').format(week.dates[i]),
                              week.waterMl[i].toStringAsFixed(0),
                            ]),
                  ),
                  pw.SizedBox(height: 10.0),

                  _sectionTitle('النشاط — خطوات ومحروق'),
                  _twoBarsSideBySide(
                    leftTitle: 'خطوات',
                    left: week.steps.map((e) => e.toDouble()).toList(),
                    rightTitle: 'محروق',
                    right: week.burned.map((e) => e.toDouble()).toList(),
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الوزن — قراءات الأسبوع'),
                  _bars(
                    values: week.weights.map<double>((e) => (e ?? 0.0)).toList(),
                    labelBuilder: (i) =>
                        DateFormat('E', 'ar').format(week.dates[i]),
                    color: PdfColors.grey700,
                  ),
                  _weightSummaryTable(week),
                ],
              ),
            ),
          ),
        ),
      );

      // شهري (متوسطات أسبوعية)
      final monthWeeks = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.calories,
      );
      final monthSteps = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.steps.map((e) => e.toDouble()).toList(),
      );
      final monthBurned = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.burned.map((e) => e.toDouble()).toList(),
      );
      final monthWeights = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.weights.map<double>((e) => (e ?? 0.0)).toList(),
      );

      final monthProtein = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.protein,
      );
      final monthCarb = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.carb,
      );
      final monthFat = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.fat,
      );
      final monthWater = _groupAverage(
        weekSize: 7,
        dates: month.dates,
        values: month.waterMl,
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  header('التتبّع — شهري'),
                  _sectionTitle('الأكل (سعرات) — متوسطات أسبوعية خلال الشهر'),
                  _bars(
                      values: monthWeeks.values,
                      labelBuilder: (i) => 'أسبوع ${i + 1}'),
                  _statsTable(
                    columns: ['أسبوع', 'متوسط السعرات'],
                    rows: List.generate(
                        monthWeeks.values.length,
                        (i) => [
                              'أسبوع ${i + 1}',
                              monthWeeks.values[i].toStringAsFixed(0),
                            ]),
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الماكروز — متوسط أسبوعي خلال الشهر'),
                  _twoBarsSideBySide(
                    leftTitle: 'بروتين (جم)',
                    left: monthProtein.values,
                    rightTitle: 'كارب (جم)',
                    right: monthCarb.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                  ),
                  pw.SizedBox(height: 6.0),
                  pw.Text('دهون (جم)',
                      style: pw.TextStyle(
                          fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
                  _bars(
                    values: monthFat.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                    color: PdfColors.grey700,
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الترطيب — ماء (مل) (متوسط أسبوعي)'),
                  _bars(
                    values: monthWater.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                    color: PdfColors.teal600,
                  ),
                  pw.SizedBox(height: 10.0),

                  _sectionTitle('النشاط — خطوات/محروق (متوسط أسبوعي)'),
                  _twoBarsSideBySide(
                    leftTitle: 'خطوات',
                    left: monthSteps.values,
                    rightTitle: 'محروق',
                    right: monthBurned.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                  ),
                  pw.SizedBox(height: 10.0),
                  _sectionTitle('الوزن — متوسطات أسبوعية'),
                  _bars(
                    values: monthWeights.values,
                    labelBuilder: (i) => 'أسبوع ${i + 1}',
                    color: PdfColors.grey700,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // سنوي (متوسط شهري)
      final byMonthCalories =
          _groupByMonthAverage(month.dates, year.dates, year.calories);
      final byMonthSteps = _groupByMonthAverage(month.dates, year.dates,
          year.steps.map((e) => e.toDouble()).toList());
      final byMonthBurned = _groupByMonthAverage(month.dates, year.dates,
          year.burned.map((e) => e.toDouble()).toList());
      final byMonthWeights = _groupByMonthAverage(month.dates, year.dates,
          year.weights.map<double>((e) => (e ?? 0.0)).toList());

      final byMonthProtein =
          _groupByMonthAverage(month.dates, year.dates, year.protein);
      final byMonthCarb =
          _groupByMonthAverage(month.dates, year.dates, year.carb);
      final byMonthFat =
          _groupByMonthAverage(month.dates, year.dates, year.fat);
      final byMonthWater =
          _groupByMonthAverage(month.dates, year.dates, year.waterMl);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  header('التتبّع — سنوي'),
                  _sectionTitle('الأكل (سعرات) — متوسط شهري'),
                  _bars(
                    values: byMonthCalories.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthCalories.labels[i]),
                  ),
                  pw.SizedBox(height: 8.0),
                  _sectionTitle('الماكروز — متوسط شهري'),
                  _twoBarsSideBySide(
                    leftTitle: 'بروتين (جم)',
                    left: byMonthProtein.values,
                    rightTitle: 'كارب (جم)',
                    right: byMonthCarb.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthProtein.labels[i]),
                  ),
                  pw.SizedBox(height: 6.0),
                  pw.Text('دهون (جم)',
                      style: pw.TextStyle(
                          fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
                  _bars(
                    values: byMonthFat.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthFat.labels[i]),
                    color: PdfColors.grey700,
                  ),
                  pw.SizedBox(height: 8.0),
                  _sectionTitle('الترطيب — ماء (مل) (متوسط شهري)'),
                  _bars(
                    values: byMonthWater.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthWater.labels[i]),
                    color: PdfColors.teal600,
                  ),
                  pw.SizedBox(height: 8.0),

                  _sectionTitle('النشاط — خطوات/محروق (متوسط شهري)'),
                  _twoBarsSideBySide(
                    leftTitle: 'خطوات',
                    left: byMonthSteps.values,
                    rightTitle: 'محروق',
                    right: byMonthBurned.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthSteps.labels[i]),
                  ),
                  pw.SizedBox(height: 8.0),
                  _sectionTitle('الوزن — متوسط شهري'),
                  _bars(
                    values: byMonthWeights.values,
                    labelBuilder: (i) =>
                        DateFormat('MMM', 'ar').format(byMonthWeights.labels[i]),
                    color: PdfColors.grey700,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      
// ====== صفحة "ملفّي الصحي" — ملخص شخصي ======
final prefsPdf = await SharedPreferences.getInstance();
final pdfEmail = await _currentEmail() ?? 'unknown_user';
final tCalPdf = prefsPdf.getDouble('caloriesNeeded_$pdfEmail') ?? 2000.0;

final wkCals = week.calories.where((e) => e > 0).toList();
final wkAvgCal = wkCals.isNotEmpty ? wkCals.reduce((a,b)=>a+b)/wkCals.length : 0.0;
int onTargetDays = 0;
for (final v in wkCals) {
  if (tCalPdf > 0 && v >= tCalPdf*0.85 && v <= tCalPdf*1.15) onTargetDays++;
}
final adherence = wkCals.isEmpty ? 0.0 : (onTargetDays / wkCals.length * 100.0);

doc.addPage(
  pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (ctx) => pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        padding: const pw.EdgeInsets.all(18),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('ملفّي الصحي — ملخص',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo800,
                )),
            pw.SizedBox(height: 10),
            pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.indigo50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('الاسم')),
                    pw.Text(profile.fullName.isNotEmpty ? profile.fullName : '—'),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('العمر')),
                    pw.Text(profile.age?.toString() ?? '—'),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('الطول (سم)')),
                    pw.Text(profile.heightCm?.toStringAsFixed(0) ?? '—'),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('الوزن الحالي (كجم)')),
                    pw.Text(profile.weightKg?.toStringAsFixed(1) ?? '—'),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('BMI')),
                    pw.Text(
                      ((profile.bmi)!=null)
                        ? '${profile.bmi!.toStringAsFixed(1)} (${profile.bmiClass})'
                        : '—',
                    ),
                  ]),
                  pw.SizedBox(height: 4),
                  pw.Row(children: [
                    pw.Expanded(child: pw.Text('BMR (تقريبي)')),
                    pw.Text(profile.bmr?.toStringAsFixed(0) ?? '—'),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text('ملخص هذا الأسبوع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('المؤشر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('القيمة')),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('هدف السعرات (يومي)')),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(tCalPdf.toStringAsFixed(0))),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('متوسط السعرات المُثبتة')),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(wkAvgCal.toStringAsFixed(0))),
                ]),
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('أيام ضمن الهدف (±15%)')),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${onTargetDays}/${wkCals.length} (${adherence.toStringAsFixed(0)}%)')),
                ]),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);
final dir = await getApplicationDocumentsDirectory();
      final name = 'tracking_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(await doc.save());
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إنشاء الملف: $name')),
        );
        await OpenFile.open(file.path);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تصدير PDF: $e')),
        );
      }
    }
  }
// جمع بيانات يومية لعدد أيام للخلف (أقدم -> أحدث)
  Future<_Series> _collectSeries({required int daysBack}) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';

    // الأداء: لا ننتظر Firestore أثناء بناء الرسوم حتى لا تعلق صفحة التتبع.
    unawaited(TrackerStore.syncFromCloud(limit: daysBack + 30));
    unawaited(WaterStore.syncFromCloud(limit: daysBack + 30));
    final remoteDays = <Map<String, dynamic>>[];

    // -------------------------
    // 1) الأوزان (حديث + قديم)
    // -------------------------
    final weightMap = <String, double>{};

    // الحديث: weight_log_$email => List<Map>{date, kg}
    final weightLogRaw = prefs.getString('weight_log_$email');
    if (weightLogRaw != null) {
      try {
        final list =
            (jsonDecode(weightLogRaw) as List).cast<Map<String, dynamic>>();
        for (final e in list) {
          final d = e['date']?.toString();
          final kg = (e['kg'] as num?)?.toDouble();
          if (d != null && kg != null) weightMap[d] = kg;
        }
      } catch (_) {}
    }

    // القديم: weightHistory_$email => List<String(JSON)]
    final historyList = prefs.getStringList('weightHistory_$email');
    if (historyList != null) {
      for (final s in historyList) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final d = m['date']?.toString();
          final kg = (m['weight'] as num?)?.toDouble();
          if (d != null && kg != null) {
            weightMap.putIfAbsent(d, () => kg);
          }
        } catch (_) {}
      }
    }

    // لو اليوم له وزن حالي ولم يكن في الخريطة
    final current = prefs.getDouble('current_weight_$email') ??
        prefs.getDouble('weight_$email');
    final todayYmd =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .toIso8601String()
            .split('T')
            .first;
    if (current != null && !weightMap.containsKey(todayYmd)) {
      weightMap[todayYmd] = current;
    }

    // الوزن السحابي من users/{uid}/days/{ymd}/tracking.weightKg
    for (final d in remoteDays) {
      final ymd = (d['date'] ?? '').toString();
      final tracking = d['tracking'];
      final kg = tracking is Map && tracking['weightKg'] is num
          ? (tracking['weightKg'] as num).toDouble()
          : 0.0;
      if (ymd.isNotEmpty && kg > 0) {
        weightMap.putIfAbsent(ymd, () => kg);
      }
    }

    // -------------------------
    // 2) الماء (ليتر) -> (مل)
    // -------------------------
    final waterLitersMap = <String, double>{};
    final waterLogRaw = prefs.getString('water_log_$email');
    if (waterLogRaw != null) {
      try {
        final m = jsonDecode(waterLogRaw) as Map<String, dynamic>;
        for (final e in m.entries) {
          waterLitersMap[e.key] = (e.value as num).toDouble();
        }
      } catch (_) {}
    }
    for (final d in remoteDays) {
      final ymd = (d['date'] ?? '').toString();
      final water = d['water'];
      final liters = water is Map && water['liters'] is num
          ? (water['liters'] as num).toDouble()
          : 0.0;
      if (ymd.isNotEmpty && liters > 0) {
        waterLitersMap.putIfAbsent(ymd, () => liters);
      }
    }

    // -------------------------
    // 3) بناء السلاسل اليومية
    // -------------------------
    final now = DateTime.now();
    final dates = <DateTime>[];
    final calories = <double>[];
    final proteins = <double>[];
    final carbs = <double>[];
    final fats = <double>[];
    final waterMl = <double>[];
    final steps = <int>[];
    final burned = <int>[];
    final weights = <double?>[];

    for (int i = daysBack - 1; i >= 0; i--) {
      final day =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final key = day.toIso8601String().split('T').first;

      // التغذية (سعرات/ماكروز) — المصدر الموحّد + fallback إلى مفاتيح قديمة
      double cal = 0.0, p = 0.0, c = 0.0, f = 0.0;
      try {
        final totals = await _readTotalsForDate(prefs, email, key);
        cal = (totals['cal'] ?? 0.0);
        p = (totals['p'] ?? 0.0);
        c = (totals['c'] ?? 0.0);
        f = (totals['f'] ?? 0.0);
      } catch (_) {}

      // fallback: diet_YYYY-MM-DD (قد يكون بدون email)
      if (cal == 0.0 && p == 0.0 && c == 0.0 && f == 0.0) {
        final raw = prefs.getString('diet_$key');
        if (raw != null) {
          try {
            final m = jsonDecode(raw) as Map<String, dynamic>;
            cal = (m['calories'] as num?)?.toDouble() ?? 0.0;
            p = (m['protein'] as num?)?.toDouble() ?? 0.0;
            c = (m['carb'] as num?)?.toDouble() ?? 0.0;
            f = (m['fat'] as num?)?.toDouble() ?? 0.0;
          } catch (_) {}
        }
      }

      // النشاط (خطوات/محروق)
      int s = 0, b = 0;
      final aRaw = prefs.getString('activity_${key}_$email');
      if (aRaw != null) {
        try {
          final a = jsonDecode(aRaw) as Map<String, dynamic>;
          s = (a['steps'] ?? 0) as int;
          b = (a['burned'] ?? 0) as int;
        } catch (_) {}
      }

      // الماء (الهدف في التطبيق بالمل، التخزين باللتر)
      double liters = prefs.getDouble('water_${key}_$email') ??
          waterLitersMap[key] ??
          0.0;

      // legacy (إن وُجد) – ماء مخزن كمل
      final legacyMlInt = prefs.getInt('waterMl_${key}_$email') ??
          prefs.getInt('water_ml_${key}_$email') ??
          prefs.getInt('water_${key}_$email');
      if (legacyMlInt != null && legacyMlInt > 0) {
        liters = legacyMlInt / 1000.0;
      } else {
        final legacyMlD = prefs.getDouble('waterMl_${key}_$email') ??
            prefs.getDouble('water_ml_${key}_$email');
        if (legacyMlD != null && legacyMlD > 0) {
          liters = legacyMlD / 1000.0;
        }
      }

      final w = weightMap[key];

      dates.add(day);
      calories.add(cal);
      proteins.add(p);
      carbs.add(c);
      fats.add(f);
      waterMl.add(liters * 1000.0);
      steps.add(s);
      burned.add(b);
      weights.add(w);
    }

    return _Series(
      dates: dates,
      calories: calories,
      protein: proteins,
      carb: carbs,
      fat: fats,
      waterMl: waterMl,
      steps: steps,
      burned: burned,
      weights: weights,
    );
  }

  _Grouped _groupAverage({
    required int weekSize,
    required List<DateTime> dates,
    required List<double> values,
  }) {
    final out = <double>[];
    final labels = <String>[];
    for (int i = 0; i < values.length; i += weekSize) {
      final end = math.min(i + weekSize, values.length);
      final slice = values.sublist(i, end);
      final double avg = slice.isEmpty
          ? 0.0
          : slice.reduce((a, b) => a + b) / slice.length.toDouble();

      out.add(avg);
      labels.add('أسبوع ${labels.length + 1}');
    }
    return _Grouped(labelsText: labels, values: out, labelsDates: []);
  }

  _GroupedByDate _groupByMonthAverage(
    List<DateTime> monthDates,
    List<DateTime> yearDates,
    List<double> yearValues,
  ) {
    final map = <String, _Agg>{}; // yyyy-MM -> (sum,count,DateTime label)
    for (int i = 0; i < yearDates.length; i++) {
      final d = yearDates[i];
      final key = DateFormat('yyyy-MM').format(d);
      map.putIfAbsent(key, () => _Agg(d, 0, 0));
      map[key] = map[key]!.add(yearValues[i]);
    }
    final keys = map.keys.toList()..sort();
    final labels = <DateTime>[];
    final values = <double>[];
    for (final k in keys) {
      final a = map[k]!;
      labels.add(DateTime(a.label.year, a.label.month, 1));
      values.add(a.sum / math.max(a.count, 1));
    }
    final start = values.length > 12 ? values.length - 12 : 0;
    return _GroupedByDate(
        labels: labels.sublist(start), values: values.sublist(start));
  }

  // عناصر PDF صغيرة
  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.SizedBox(width: 120, child: pw.Text('$k:')),
            pw.Expanded(child: pw.Text(v)),
          ],
        ),
      );

  pw.Widget _sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4.0),
        child: pw.Text(t,
            style:
                pw.TextStyle(fontSize: 14.0, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _statsTable(
      {required List<String> columns, required List<List<String>> rows}) {
    final colWidths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < columns.length; i++) {
      colWidths[i] = const pw.FlexColumnWidth();
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: colWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: columns
              .map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.all(6.0),
                    child: pw.Text(c),
                  ))
              .toList(),
        ),
        ...rows.map((r) => pw.TableRow(
              children: r
                  .map((c) => pw.Padding(
                        padding: const pw.EdgeInsets.all(6.0),
                        child: pw.Text(c),
                      ))
                  .toList(),
            )),
      ],
    );
  }

  pw.Widget _weightSummaryTable(_Series s) {
    final vals = s.weights.whereType<double>().toList();
    if (vals.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6.0),
        child: pw.Text('لا توجد قراءات وزن في هذه الفترة'),
      );
    }
    final min = vals.reduce(math.min);
    final max = vals.reduce(math.max);
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return _statsTable(
      columns: ['أدنى', 'أعلى', 'متوسط'],
      rows: [
        [
          min.toStringAsFixed(1),
          max.toStringAsFixed(1),
          avg.toStringAsFixed(1)
        ],
      ],
    );
  }

  pw.Widget _bars({
    required List<double> values,
    required String Function(int) labelBuilder,
    PdfColor color = PdfColors.teal600,
  }) {
    final double maxVal = values.fold<double>(0.0, (p, n) => p > n ? p : n);

    final bars = <pw.Widget>[];
    for (int i = 0; i < values.length; i++) {
      final double h = maxVal == 0.0 ? 1.0 : (values[i] / maxVal) * 60.0;
      bars.add(
        pw.Column(
          children: [
            pw.Stack(children: [
  pw.Container(
    width: 14.0,
    height: h,
    decoration: pw.BoxDecoration(
      color: color,
      borderRadius: pw.BorderRadius.circular(4),
    ),
  ),
  pw.Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: pw.Center(child: pw.Text(values[i].toStringAsFixed(0), style: const pw.TextStyle(fontSize: 8))),
  ),
]),
pw.SizedBox(height: 4.0),
pw.Text(labelBuilder(i), style: const pw.TextStyle(fontSize: 8.0)),

          ],
        ),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6.0),
      child: pw.SizedBox(
        height: 90.0,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: bars,
        ),
      ),
    );
  }

  pw.Widget _twoBarsSideBySide({
    required String leftTitle,
    required List<double> left,
    required String rightTitle,
    required List<double> right,
    required String Function(int) labelBuilder,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(leftTitle,
            style:
                pw.TextStyle(fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
        _bars(
            values: left, labelBuilder: labelBuilder, color: PdfColors.indigo),
        pw.SizedBox(height: 6.0),
        pw.Text(rightTitle,
            style:
                pw.TextStyle(fontSize: 12.0, fontWeight: pw.FontWeight.bold)),
        _bars(
            values: right,
            labelBuilder: labelBuilder,
            color: PdfColors.deepOrange),
      ],
    );
  }

  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('التتبّع'),
            if (_displayName.trim().isNotEmpty)
              Text(
                _displayName,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(.65)),
              ),
          ],
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceVariant.withOpacity(.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(.25)),
              ),
              child: TabBar(
                controller: _tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.06),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurface.withOpacity(.65),
                tabs: const [
                  Tab(text: 'الماكروز'),
                  Tab(text: 'الوزن'),
                  Tab(text: 'النشاط'),
                  Tab(text: 'تحليلات'),
                ],
              ),
            ),
          ),
        ),
        
        actions: [
          IconButton(
            tooltip: 'تصدير PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () async {
              final ok = await PremiumAccess.ensureSubscribed(context, feature: PremiumFeature.trackingPdf);
              if (ok) {
                await _exportTrackingPdf(context);
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _CaloriesHistoryScreen(),
          _WeightTab(),
          _ActivityTab(),
          _InsightsTab(),
        ],
      ),
    );
  }
BarChartGroupData _bar(int x, double used, double target, {required Color color}) {
    final percent = target <= 0 ? 0.0 : (used / target * 100);
    final clamped = percent.clamp(0.0, 200.0).toDouble(); // حتى 200%
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: clamped,
          width: 18.0,
          color: color.withOpacity(.9),
          borderRadius: BorderRadius.circular(6.0),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: 200,
            color: color.withOpacity(.18),
          ),
        )
      ],
    );
  }

  Future<void> _quickAddDialog(BuildContext context) async {
    final c = TextEditingController();
    final p = TextEditingController();
    final k = TextEditingController();
    final f = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة يدوية لليوم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _numField(c, 'سعرات (سعرة)'),
            _numField(p, 'بروتين (غم)'),
            _numField(k, 'كارب (غم)'),
            _numField(f, 'دهون (غم)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cal = double.tryParse(c.text) ?? 0;
              final pro = double.tryParse(p.text) ?? 0;
              final crb = double.tryParse(k.text) ?? 0;
              final fat = double.tryParse(f.text) ?? 0;
              await DailyTrackerStore.addIntake(
                cal: cal,
                protein: pro,
                carb: crb,
                fat: fat,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController c, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// تحليلات ذكية حسب الهدف
String _smartAnalysis(
  String goal,
  double uCal,
  double uP,
  double uC,
  double uF,
  double tCal,
  double tP,
  double tC,
  double tF,
) {
  double rP = tP == 0 ? 0 : uP / tP;
  double rC = tC == 0 ? 0 : uC / tC;
  double rF = tF == 0 ? 0 : uF / tF;
  double rCal = tCal == 0 ? 0 : uCal / tCal;

  String highFat = rF > 1.1 ? 'الدهون مرتفعة اليوم. ' : '';
  String highCarb = rC > 1.1 ? 'الكارب مرتفع اليوم. ' : '';
  String lowProtein = rP < 0.7 ? 'البروتين منخفض. ' : '';
  String okCal = (rCal >= 0.9 && rCal <= 1.1) ? 'السعرات قريبة من هدفك. ' : '';
  String lowCal = rCal < 0.85 ? 'السعرات أقل بكثير من هدفك. ' : '';
  String highCalTxt = rCal > 1.15 ? 'تجاوزت هدف السعرات اليوم. ' : '';

  switch (goal) {
    case 'إنقاص الوزن':
    case 'خفض الدهون':
      if (rF > 1.0 && rC > 1.0) {
        return 'هدفك إنقاص/خفض الدهون: $highFat$highCarbخفّف الدهون والسكريات، وارفع البروتين . $okCal';
      }
      if (rF > 1.0) {
        return 'هدفك إنقاص/خفض الدهون: $highFatاختر مصادر بروتين خفيفة وقلّل الزيوت. $okCal';
      }
      if (rC > 1.2) {
        return 'هدفك إنقاص/خفض الدهون: $highCarbقلّل النشويات المكررة وزيد الألياف والخضار. $okCal';
      }
      if (rP < 0.8) {
        return 'هدفك إنقاص/خفض الدهون: $lowProteinزيد من البروتين للحفاظ على الكتلة العضلية.';
      }
      return 'جيد! توزيعتك تدعم الهدف — استمر على توازن بروتين أعلى ودهون/كارب مضبوطة. $okCal';

    case 'زيادة الوزن':
      if (rCal < 0.95) {
        return 'لهدف زيادة الوزن: $lowCal زد حصصك تدريجيًا خاصة الكارب والبروتين.';
      }
      if (rP < 0.9) {
        return 'لهدف زيادة الوزن: $lowProteinاحرص على بروتين كافٍ مع كل وجبة.';
      }
      if (rC < 0.9) {
        return 'لهدف زيادة الوزن: الكارب أقل من المطلوب — زِيد الأرز/الخبز الكامل/الشوفان.';
      }
      return 'ممتاز! تقدّم مناسب للزيادة — حافظ على فائض سعرات متوازن وبروتين كافٍ.';

    case 'بناء العضلات':
      if (rP < 1.0) {
        return 'هدفك بناء العضلات: $lowProteinحاول الوصول لهدف البروتين اليومي.';
      }
      if (rCal < 0.95) {
        return 'هدفك بناء العضلات: $lowCal زيد السعرات قليلا مع توزيع كارب جيد حول التمرين.';
      }
      return 'رائع! بروتينك جيد وتقريبًا عند هدف السعرات — استمر ووزّع الكارب حول التمرين.';

    case 'الصيام المتقطع':
      if (rP < 0.8) {
        return 'الصيام المتقطع: $lowProteinاحرص على بروتين كاف داخل نافذة الأكل.';
      }
      if (rCal > 1.2) {
        return 'الصيام المتقطع: $highCalTxtراقب حجم الوجبات داخل النافذة.';
      }
      return 'جيد! التزم بمواعيد النافذة ووجبات متوازنة مع بروتين جيد.';

    case 'نمط حياة صحي':
    case 'تحسين الصحة العامة':
      if (rF > 1.2) {
        return 'نمط صحي: $highFatقلّل المقليات واختر دهون صحية بكميات معتدلة.';
      }
      if (rC > 1.2) return 'نمط صحي: $highCarbفضّل الحبوب الكاملة والخضار.';
      return 'توزيع متوازن — استمر على اعتدال السعرات وجودة الاختيارات.';

    case 'خفض ضغط الدم':
      return 'خفض الضغط: راقب الصوديوم واشرب ماء كفاية. ${highFat.isNotEmpty ? highFat : ''}${highCarb.isNotEmpty ? highCarb : ''} ركّز على البوتاسيوم (موز/أفوكادو/سبانخ).';

    case 'زيادة النشاط اليومي':
      return 'زيادة النشاط: اجعل الكارب معتدلًا قبل النشاط والبروتين موزعًا خلال اليوم. ${okCal.isNotEmpty ? okCal : ''}';

    case 'ضبط مستوى السكر':
    case 'اتباع رجيم نباتي':
      if (rC > 1.2) {
        return 'السكر/النباتي: $highCarbانتبه للتوزيع عبر اليوم واختر كارب منخفض المؤشر.';
      }
      if (rP < 0.8) {
        return 'السكر/النباتي: $lowProteinأضف مصادر بروتين نباتي (عدس/حمص/توفو).';
      }
      return 'جيد! حافظ على كارب معقّد وألياف عالية وبروتين كافٍ.';
  }
  return 'توزيعك اليومي جيد عمومًا — راقب البروتين واعتدل في الدهون والكارب، واضبط السعرات حسب هدفك.';
}

class _MacroTile {
  final String label;
  final double used, target;
  final IconData icon;
  final Color color;
  _MacroTile(this.label, this.used, this.target, this.icon, this.color);

  Widget buildBar() {
    final remaining = (target - used).clamp(0.0, target).toDouble();
    final percent =
        target == 0 ? 0.0 : (used / target).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text('$label - المتبقي: ${remaining.toStringAsFixed(0)}'),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: color.withOpacity(.18),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 10.0,
          ),
        ),
      ]),
    );
  }
} // 👈 قفل الكلاس

class _AnalysisCard extends StatelessWidget {
  final String text;
  const _AnalysisCard({required this.text});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.indigo.withOpacity(.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

class _CaloriesHistoryScreen extends StatefulWidget {
  const _CaloriesHistoryScreen();
  @override
  State<_CaloriesHistoryScreen> createState() => _CaloriesHistoryScreenState();
}


class _CaloriesHistoryScreenState extends State<_CaloriesHistoryScreen> with WidgetsBindingObserver {
  StreamSubscription? _macrosSub;
  SharedPreferences? _prefsRef;
  String? _emailRef;

  // أهداف اليوم من صفحة بياناتي
  double? _tCal, _tP, _tC, _tF;
  // الالتزام العام
  double _adherence = 0;
  int _okCalDays = 0, _okPDays = 0;
  // عرض/إخفاء السلاسل
  bool _showCal = true, _showP = true, _showC = true, _showF = true;
  // Heatmap & Highlights & Micro-goals
  List<Map<String, dynamic>> _heat = []; // [{date, score, cal, p, c, f}]
  Map<String, dynamic>? _bestDay;
  Map<String, dynamic>? _worstDay;
  Set<String> _microEnabled = {}; // {'cal_ok','protein_ok','logging_ok'}
  Map<String, double> _microProgress = {}; // id -> 0..1


  // آخر 7/14/30 يوم (بدون اليوم الجاري حتى يُثبَّت)
  int _days = 7;
  List<Map<String, dynamic>> _series = []; // [{date:'yyyy-mm-dd', cal:..., p:..., c:..., f:...}]
  String? _goal;

  Timer? _tick;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;
  bool _cloudDailyRestoreDone = false;
  List<Map<String, dynamic>> _cachedRemoteDays = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    _load();
    _macrosSub = MacrosLiveBus.listen(_load);
  }

    @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _macrosSub?.cancel();
    super.dispose();
  }
Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    _goal = await _currentGoal();
    _prefsRef = prefs; _emailRef = email;
    await _loadMicroEnabled(prefs, email);
    
    // تحميل الأهداف من صفحة بياناتي
    if (email != null) {
      _tCal = prefs.getDouble('caloriesNeeded_${email}');
      _tP   = prefs.getDouble('protein_${email}');
      _tC   = prefs.getDouble('carbs_${email}');
      _tF   = prefs.getDouble('fat_${email}');
    }
final now = DateTime.now();
    final list = <Map<String, dynamic>>[];

    for (int i = _days-1; i >= 0; i--) { // يشمل اليوم الحالي
      final d = now.subtract(Duration(days: i)).toIso8601String().split('T').first;
      if (email == null) continue;
      final totals = await _readTotalsForDate(prefs, email, d);
      final cal = (totals['cal'] ?? 0).toDouble();
      final p  = (totals['p']   ?? 0).toDouble();
      final c  = (totals['c']   ?? 0).toDouble();
      final f  = (totals['f']   ?? 0).toDouble();
      if (cal>0 || p>0 || c>0 || f>0) {
        list.add({'date': d, 'cal': cal, 'p': p, 'c': c, 'f': f});
      } else {
        list.add({'date': d, 'cal': 0, 'p': 0, 'c': 0, 'f': 0});
      }
    }
    if (!mounted) return;
    setState(() => _series = list);
    _computeAdherence();
    _computeWeeklyHeatmap();
    _computeBestWorst();
    _computeMicroProgress();
  }

  // ألوان ثابتة متوافقة مع أسلوبك السابق (يمكن تعديلها لاحقًا لو أردت)
  Color get _calColor => Theme.of(context).colorScheme.primary;
  Color get _pColor   => Colors.indigo;  // بروتين
  Color get _cColor   => Colors.orange;  // كارب
  Color get _fColor   => Colors.redAccent; // دهون

  
  void _computeAdherence() {
    final daysWith = _series.where((e)=> ((e['cal'] as num?)?.toDouble() ?? 0) > 0).toList();
    final tCal = _tCal ?? (daysWith.isEmpty ? 2000.0 : daysWith.map((e)=> (e['cal'] as num).toDouble()).reduce((a,b)=>a+b)/daysWith.length);
    final tP   = _tP ?? (tCal * 0.30 / 4);
    final tC   = _tC ?? (tCal * 0.40 / 4);
    final tF   = _tF ?? (tCal * 0.30 / 9);
    int okCal=0, okP=0; double sum=0; int n=0;
    for (final d in _series) {
      final cal = (d['cal'] as num).toDouble();
      final p   = (d['p'] as num).toDouble();
      final c   = (d['c'] as num).toDouble();
      final f   = (d['f'] as num).toDouble();
      if (cal<=0 && p<=0 && c<=0 && f<=0) continue;
      double s=0;
      if (tCal>0 && (cal>=tCal*0.9 && cal<=tCal*1.1)) { s+=40; okCal++; }
      if (p>=tP*0.9) { s+=25; okP++; }
      if (tC>0 && (c>=tC*0.8 && c<=tC*1.2)) s+=15;
      if (tF>0 && (f>=tF*0.8 && f<=tF*1.2)) s+=15;
      if (cal>0) s+=5;
      sum+=s; n++;
    }
    setState(() { _adherence = n==0?0:(sum/n).clamp(0,100); _okCalDays=okCal; _okPDays=okP; });
  }

  Widget _adherenceHero(ColorScheme cs, TextTheme t) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(width: 90, height: 90, child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 90, height: 90, child: CircularProgressIndicator(
              value: _adherence/100.0, strokeWidth: 10, backgroundColor: cs.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${_adherence.toStringAsFixed(0)}%', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const Text('التزام', style: TextStyle(fontSize: 12)),
            ]),
          ])),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children:[const Text('🔥', style: TextStyle(fontSize: 18)), const SizedBox(width:6), Text('ضمن السعرات: $_okCalDays يوم', style: t.bodyMedium)]),
            const SizedBox(height: 6),
            Row(children:[const Text('🥩', style: TextStyle(fontSize: 18)), const SizedBox(width:6), Text('البروتين مُتحقق: $_okPDays يوم', style: t.bodyMedium)]),
            const SizedBox(height: 8),
            Text('حسّن الالتزام برفع البروتين وتثبيت السعرات حول الهدف اليومي.', style: t.bodySmall?.copyWith(color: cs.onSurface.withOpacity(.7))),
          ])),
        ],
      ),
    );
  }

  // رسم موحّد (سعرات + ماكروز ×تحويل سعرات) مع إمكانية إظهار/إخفاء السلاسل
  Widget _combinedMacroChart(List<double> kcal, List<double> p, List<double> c, List<double> f) {
    final protKcal = p.map((e)=> e*4).toList();
    final carbKcal = c.map((e)=> e*4).toList();
    final fatKcal  = f.map((e)=> e*9).toList();
    final n = _series.length;
    List<FlSpot> spots(List<double> arr)=> arr.asMap().entries.map((e)=> FlSpot(e.key.toDouble(), e.value)).toList();
    final maxY = [...kcal, ...protKcal, ...carbKcal, ...fatKcal].fold<double>(0, (m,v)=> v>m?v:m) * 1.15;
    final cs = Theme.of(context).colorScheme; final t = Theme.of(context).textTheme;
    Widget legend(Color c, String label)=> Container(
      padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
      decoration: BoxDecoration(color: cs.surface, border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width:10, height:10, decoration: BoxDecoration(color:c, shape: BoxShape.circle)), const SizedBox(width:6), Text(label, style: t.labelMedium)]),
    );
    return Container(
      height: 260,
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: Offset(0,4))]),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الرسم الموحَّد (السعرات + الماكروز)', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Expanded(child: LineChart(LineChartData(
            minY: 0, maxY: maxY <= 0 ? 1 : maxY,
            lineTouchData: LineTouchData(enabled: true),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, interval: math.max(1, n~/6).toDouble(),
                getTitlesWidget: (v,meta){ final i=v.toInt(); if(i<0||i>=n) return const SizedBox.shrink(); final d=_series[i]['date'] as String; return Text(d.substring(5), style: const TextStyle(fontSize: 10)); },
              )),
            ),
            gridData: FlGridData(show: true, horizontalInterval: (maxY/4).clamp(1, 999999)),
            borderData: FlBorderData(show: true, border: const Border(top: BorderSide.none, right: BorderSide.none, left: BorderSide(width:.8), bottom: BorderSide(width:.8))),
            lineBarsData: [
              if (_showCal) LineChartBarData(spots: spots(kcal), isCurved: true, barWidth: 2.5, color: _calColor, dotData: const FlDotData(show:false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_calColor.withOpacity(.25), _calColor.withOpacity(0)]))),
              if (_showP)   LineChartBarData(spots: spots(protKcal), isCurved: true, barWidth: 2.3, color: _pColor,   dotData: const FlDotData(show:false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_pColor.withOpacity(.18), _pColor.withOpacity(0)]))),
              if (_showC)   LineChartBarData(spots: spots(carbKcal), isCurved: true, barWidth: 2.3, color: _cColor,   dotData: const FlDotData(show:false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_cColor.withOpacity(.18), _cColor.withOpacity(0)]))),
              if (_showF)   LineChartBarData(spots: spots(fatKcal),  isCurved: true, barWidth: 2.3, color: _fColor,   dotData: const FlDotData(show:false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_fColor.withOpacity(.18), _fColor.withOpacity(0)]))),
            ],
          ))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            legend(_calColor, '🔥 السعرات (سعرة)'),
            legend(Colors.indigo, '🥩 البروتين (×4 سعرة)'),
            legend(Colors.orange, '🍞 الكارب (×4 سعرة)'),
            legend(Colors.redAccent, '🧈 الدهون (×9 سعرة)'),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            FilterChip(label: const Text('🔥 السعرات'), selected: _showCal, onSelected: (v)=> setState(()=> _showCal=v)),
            FilterChip(label: const Text('🥩 البروتين'), selected: _showP, onSelected: (v)=> setState(()=> _showP=v)),
            FilterChip(label: const Text('🍞 الكارب'), selected: _showC, onSelected: (v)=> setState(()=> _showC=v)),
            FilterChip(label: const Text('🧈 الدهون'), selected: _showF, onSelected: (v)=> setState(()=> _showF=v)),
          ]),
        ],
      ),
    ),
  );
  }

  void _computeWeeklyHeatmap() {
    // نستخدم آخر 28 يوماً (4 أسابيع) بعدد أيام المدى المختار إن كان أكبر
    final n = _series.length;
    final take = n < 28 ? n : 28;
    final days = _series.sublist(n - take, n);
    final tCal = _tCal ?? (days.where((e)=> e['cal']>0).isEmpty ? 2000.0 : days.map((e)=> (e['cal'] as num).toDouble()).reduce((a,b)=>a+b)/days.length);
    _heat = days.map((d){
      final cal = (d['cal'] as num).toDouble();
      final p = (d['p'] as num).toDouble();
      final c = (d['c'] as num).toDouble();
      final f = (d['f'] as num).toDouble();
      // درجة الالتزام يوميًا بناء على السعرات ±10%
      double score = 0;
      if (tCal>0 && cal>0) {
        final dev = (cal - tCal).abs()/tCal;
        score = (1.0 - dev).clamp(0.0, 1.0);
        if (dev <= 0.10) score = 1.0; // ضمن الهدف
      }
      return {'date': d['date'], 'score': score, 'cal': cal, 'p': p, 'c': c, 'f': f};
    }).toList();
  }

  void _computeBestWorst() {
    if (_series.isEmpty) { _bestDay=null; _worstDay=null; return; }
    final tCal = _tCal ?? 2000.0;
    double dayScore(Map<String,dynamic> d){
      final cal = (d['cal'] as num).toDouble();
      final p = (d['p'] as num).toDouble();
      final c = (d['c'] as num).toDouble();
      final f = (d['f'] as num).toDouble();
      double s=0;
      if (tCal>0 && cal>0 && (cal>=tCal*0.9 && cal<=tCal*1.1)) s+=40;
      // بروتين أقوى وزنًا
      final tP = _tP ?? (tCal*0.30/4);
      if (tP>0 && p>=tP*0.9) s+=35;
      final tC = _tC ?? (tCal*0.40/4);
      if (tC>0 && (c>=tC*0.8 && c<=tC*1.2)) s+=15;
      final tF = _tF ?? (tCal*0.30/9);
      if (tF>0 && (f>=tF*0.8 && f<=tF*1.2)) s+=10;
      return s;
    }
    Map<String,dynamic>? best; double bScore=-1;
    Map<String,dynamic>? worst; double wScore=1e9;
    for (final d in _series){
      final sc = dayScore(d.cast<String,dynamic>());
      if (sc> bScore){ bScore=sc; best=d; }
      if (sc< wScore){ wScore=sc; worst=d; }
    }
    _bestDay = best?.cast<String,dynamic>();
    _worstDay = worst?.cast<String,dynamic>();
  }

  Future<void> _loadMicroEnabled(SharedPreferences prefs, String? email) async {
    final raw = prefs.getString('microgoals_enabled_${email ?? 'unknown'}');
    if (raw != null) {
      try {
        _microEnabled = Set<String>.from((jsonDecode(raw) as List).map((e)=> e.toString()));
      } catch (_) {}
    } else {
      _microEnabled = {'cal_ok','protein_ok','logging_ok'}; // افتراضيًا فعّالة
    }
  }

  Future<void> _saveMicroEnabled(SharedPreferences prefs, String? email) async {
    await prefs.setString('microgoals_enabled_${email ?? 'unknown'}', jsonEncode(_microEnabled.toList()));
  }

  void _computeMicroProgress() {
    final n = _series.length;
    if (n==0) { _microProgress = {}; return; }
    final tCal = _tCal ?? 2000.0;
    final tP   = _tP ?? (tCal*0.30/4);
    int okCal=0, okP=0, okLog=0;
    for (final d in _series) {
      final cal = (d['cal'] as num).toDouble();
      final p   = (d['p'] as num).toDouble();
      if (cal>0) okLog++;
      if (tCal>0 && cal>=tCal*0.9 && cal<=tCal*1.1) okCal++;
      if (tP>0 && p>=tP*0.9) okP++;
    }
    _microProgress = {
      'cal_ok': okCal / n,
      'protein_ok': okP / n,
      'logging_ok': okLog / n,
    };
  }

  Widget _weeklyHeatmap(ColorScheme cs, TextTheme t) {
    // grid 4 أسابيع × 7 أيام
    final cols = 4; final rows = 7;
    final items = _heat; // آخر 28 يوم
    Color colorFor(double s) {
      // 0→سطح، 1→primary
      return Color.lerp(cs.surfaceVariant, cs.primary, s.clamp(0,1))!;
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('التزام السعرات آخر ٤ أسابيع', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // أسماء الأيام
          Column(
            children: const [
              SizedBox(height: 20, width: 20),
              Text('س', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ح', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ن', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ث', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ر', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('خ', style: TextStyle(fontSize: 12)),
              SizedBox(height: 8),
              Text('ج', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(width: 8),
          for (int c=0;c<cols;c++)
            Column(children: [
              Text('الأسبوع ${c+1}', style: t.labelSmall),
              const SizedBox(height: 4),
              for (int r=0;r<rows;r++)
                Builder(builder: (_) {
                  final idx = c*rows + r;
                  if (idx >= items.length) return const SizedBox(height: 20, width: 20);
                  final s = items[idx];
                  final val = (s['score'] as num).toDouble();
                  final d   = s['date'] as String;
                  return Tooltip(
                    message: '$d\n${val>=1? 'ضمن الهدف' : 'انحراف ${(100 - (val*100)).toStringAsFixed(0)}%'}',
                    child: Container(
                      width: 20, height: 20,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: colorFor(val),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
            ]),
        ]),
      ]),
    );
  }

  Widget _bestWorstCards(ColorScheme cs, TextTheme t) {
    Widget card(String title, Map<String,dynamic>? d, Color color, IconData icon) {
      return Expanded(child: Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))]),
        padding: const EdgeInsets.all(12),
        child: d==null? const Text('لا توجد بيانات'): Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))]),
          const SizedBox(height: 6),
          Text('${d['date']}', style: t.labelMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            Chip(label: Text('سعرات: ${(d['cal'] as num).toString()}')),
            Chip(label: Text('بروتين: ${(d['p'] as num).toString()}غ')),
            Chip(label: Text('كارب: ${(d['c'] as num).toString()}غ')),
            Chip(label: Text('دهون: ${(d['f'] as num).toString()}غ')),
          ]),
        ]),
      ));
    }
    return Row(children: [
      card('أفضل يوم', _bestDay, Colors.green, Icons.trending_up_rounded),
      const SizedBox(width: 12),
      card('أقل التزام', _worstDay, Colors.redAccent, Icons.trending_down_rounded),
    ]);
  }

  
Widget _microGoals(ColorScheme cs, TextTheme t) {
    Widget goalCard(String id, String label, String helper) {
      final enabled = _microEnabled.contains(id);
      final prog = _microProgress[id] ?? 0;
      return Container(
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))]),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Switch(
              value: enabled,
              onChanged: (v) async {
                setState(() { if (v) _microEnabled.add(id); else _microEnabled.remove(id); });
                final prefs = _prefsRef ?? await SharedPreferences.getInstance();
                final email = _emailRef ?? await _currentEmail() ?? 'unknown_user';
                await _saveMicroEnabled(prefs, email);
                _computeMicroProgress();
              },
            ),
            const SizedBox(width: 6),
            Text(label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          LinearProgressIndicator(value: prog, minHeight: 8, backgroundColor: cs.surfaceVariant),
          const SizedBox(height: 6),
          Text(helper, style: t.bodySmall?.copyWith(color: cs.onSurface.withOpacity(.7))),
        ]),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final spacing = 12.0;
      int cols = 1;
      if (w >= 900) cols = 3;
      else if (w >= 560) cols = 2;
      final itemW = (w - spacing * (cols - 1)) / cols;

      List<Widget> tiles = [
        SizedBox(width: itemW, child: goalCard('cal_ok', 'ضمن السعرات ±10%', 'كم نسبة الأيام ضمن هدف السعرات خلال المدة؟')),
        SizedBox(width: itemW, child: goalCard('protein_ok', 'البروتين ≥ 90% من الهدف', 'نسبة الأيام التي حققت حد البروتين الأدنى.')),
        SizedBox(width: itemW, child: goalCard('logging_ok', 'تسجيل يومي مستمر', 'كم يوم تم تسجيل وجبات فيه خلال المدة؟')),
        SizedBox(width: itemW, child: Container(
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))]),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('هدف مخصص', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('أضف هدفًا مخصصًا لاحقًا'),
          ]),
        )),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('أهداف مصغّرة (تتبع المدة المختارة)', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: spacing, runSpacing: spacing, children: tiles),
        ],
      );
    });
  }


double _maxOf(List<double> vals) => vals.isEmpty ? 0 : vals.reduce((a,b)=>a>b?a:b);

  List<String> _tipsForGoal(String goal, Map<String,double> avg) {
    final out = <String>[];
    final cal = avg['cal']!, p = avg['p']!, c = avg['c']!, f = avg['f']!;
    // نسب تقريبية من السعرات
    final calFromP = p*4, calFromC = c*4, calFromF = f*9;
    final pc = cal==0?0: (calFromP/cal);
    final cc = cal==0?0: (calFromC/cal);
    final fc = cal==0?0: (calFromF/cal);

    switch (goal) {
      case 'بناء العضلات':
      case 'بناء عضلات':
        if (pc < 0.25) out.add('هدفك بناء عضلات: ارفع البروتين (جرّب إضافة وجبة/سناك بروتيني).');
        if (fc > 0.35) out.add('هدفك بناء عضلات: الدهون مرتفعة؛ خفّف المقليات والزيوت ووجّه السعرات للبروتين/الكارب حول التمرين.');
        if (cc < 0.35) out.add('هدفك بناء عضلات: الكارب منخفض؛ أضف نشويات معقّدة (شوفان/أرز/بطاطس) خاصة قبل وبعد التمرين.');
        out.add('حافظ على فائض سعرات بسيط ومنتظم (حوالي +10٪ من احتياجك).');
        break;

      case 'إنقاص الوزن':
      case 'خفض الدهون':
        if (pc < 0.30) out.add('إنقاص وزن: ارفع البروتين للحفاظ على الكتلة العضلية.');
        if (cc > 0.45) out.add('إنقاص وزن: قلّل السكريات/الكارب العالي المؤشر وأضف أليافًا وخضار.');
        if (fc > 0.35) out.add('إنقاص وزن: راقب الدهون (أوزن الزيت/المكسرات) واختر الطبخ بدون قلي.');
        out.add('استهدف عجزًا بسيطًا (‑15٪ تقريبًا) مع مشي يومي.');
        break;

      case 'زيادة الوزن':
        if (pc < 0.25) out.add('زيادة وزن: احرص على بروتين كافٍ بكل وجبة.');
        if (cc < 0.45) out.add('زيادة وزن: زِد الكارب المعقّد (أرز/خبز كامل/مكرونة).');
        out.add('قسّم السعرات على 3–5 وجبات مع سناكات عالية الطاقة.');
        break;

      case 'الصيام المتقطع':
        if (pc < 0.30) out.add('الصيام: البروتين منخفض داخل نافذة الأكل — عزّزه في الوجبتين الرئيسيتين.');
        if (cc > 0.50) out.add('الصيام: الكارب مرتفع — اختر نشويات منخفضة المؤشر.');
        out.add('التزم بمواعيد النافذة واشرب ماءً كافيًا خلال اليوم.');
        break;

      default:
        out.add('استمر على توزيع متزن وراقب جودة الاختيارات.');
    }

    // نصائح عامة إضافية
    if (cal == 0) out.add('لا توجد بيانات كافية — احرص على تسجيل وجباتك.');
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t  = Theme.of(context).textTheme;

    List<double> kcal = _series.map((e)=> (e['cal'] as num).toDouble()).toList();
    List<double> prot = _series.map((e)=> (e['p'] as num).toDouble()).toList();
    List<double> carb = _series.map((e)=> (e['c'] as num).toDouble()).toList();
    List<double> fat  = _series.map((e)=> (e['f'] as num).toDouble()).toList();

    final maxCal = _maxOf(kcal);
    final maxP   = _maxOf(prot);
    final maxC   = _maxOf(carb);
    final maxF   = _maxOf(fat);

    pw.Widget? _; // لا شيء — فقط لإرضاء التحذير إن وُجد 😄

    Widget _rangeChip(String label, int days) {
      final sel = _days == days;
      return ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) { setState(() { _days = days; }); _load(); },
      );
    }

    
    Widget _aggregatesRow(List<double> kcal, List<double> prot, List<double> carb, List<double> fat) {
      double sum(List<double> v) => v.isEmpty ? 0.0 : v.reduce((a,b)=>a+b);
      String fmt(double v, {bool intLike=false}) {
        if (intLike) return v.round().toString();
        return v >= 1000 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      }
      final t  = Theme.of(context).textTheme;
      final cs = Theme.of(context).colorScheme;

      Widget card(String label, String value) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.labelMedium?.copyWith(color: cs.outline)),
              const SizedBox(height: 4),
              Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        );
      }

      final sCal = fmt(sum(kcal), intLike: true);
      final sP   = fmt(sum(prot));
      final sC   = fmt(sum(carb));
      final sF   = fmt(sum(fat));

      return Wrap(
        spacing: 8, runSpacing: 8,
        children: [
          card('إجمالي السعرات', '$sCal سعرة'),
          card('إجمالي البروتين', '$sP غ'),
          card('إجمالي الكارب', '$sC غ'),
          card('إجمالي الدهون', '$sF غ'),
        ],
      );
    }

Widget _singleChart(String title, List<double> values, Color color) {
      final spots = values.asMap().entries.map((e)=> FlSpot(e.key.toDouble(), e.value)).toList();
      final maxY = (values.isEmpty ? 1 : _maxOf(values)) * 1.1;
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Expanded(
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: maxY <= 0 ? 1 : maxY,
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: math.max(1, values.length ~/ 6).toDouble(),
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= _series.length) return const SizedBox.shrink();
                            final d = _series[i]['date'] as String;
                            return Text(d.substring(5), style: const TextStyle(fontSize: 10));
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                        color: color,
                        belowBarData: BarAreaData(
                          show: true,
                          color: color.withOpacity(.10),
                        ),
                        spots: spots,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // متوسطات للفترة المختارة
    Map<String,double> avg = {
      'cal': (kcal.isEmpty?0: kcal.reduce((a,b)=>a+b)/kcal.length),
      'p'  : (prot.isEmpty?0: prot.reduce((a,b)=>a+b)/prot.length),
      'c'  : (carb.isEmpty?0: carb.reduce((a,b)=>a+b)/carb.length),
      'f'  : (fat.isEmpty?0:  fat.reduce((a,b)=>a+b)/fat.length),
    };
    final tips = _tipsForGoal(_goal ?? 'عام', avg);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // اختيار المدة
        Row(
          children: [
            Text('تتبّع الماكروز', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: PopupMenuButton<int>(
                tooltip: 'تصفية المدة',
                icon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Icon(Icons.filter_alt_rounded),
                ),
                onSelected: (v) { setState(() { _days = v; }); _load(); },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 7,  child: Text('آخر ٧ أيام')),
                  PopupMenuItem(value: 14, child: Text('آخر ١٤ يوم')),
                  PopupMenuItem(value: 30, child: Text('آخر شهر')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _adherenceHero(cs, t),
        const SizedBox(height: 12),
        _combinedMacroChart(kcal, prot, carb, fat),
        const SizedBox(height: 12),
        _weeklyHeatmap(cs, t),
        const SizedBox(height: 12),
        _bestWorstCards(cs, t),
        const SizedBox(height: 12),
        _aggregatesRow(kcal, prot, carb, fat),
        const SizedBox(height: 12),
        _microGoals(cs, t),
        const SizedBox(height: 12),
        _singleChart('السعرات', kcal, _calColor),
        const SizedBox(height: 12),
        _singleChart('البروتين (غم)', prot, _pColor),
        const SizedBox(height: 12),
        _singleChart('الكارب (غم)', carb, _cColor),
        const SizedBox(height: 12),
        _singleChart('الدهون (غم)', fat, _fColor),
        const SizedBox(height: 16),

        // نصائح ذكية حسب الهدف
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: cs.primary.withOpacity(.06), blurRadius: 12, offset: const Offset(0,4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('نصائح حسب هدفك${_goal!=null ? ' — $_goal' : ''}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...tips.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s, style: t.bodyMedium)),
                  ],
                ),
              )),
            ],
          ),
        ),
      ],
    );
  }
}


//// ========= Weight Tab =========
class _WeightTab extends StatefulWidget {
  const _WeightTab();
  @override
  State<_WeightTab> createState() => _WeightTabState();
}

class _WeightTabState extends State<_WeightTab> with WidgetsBindingObserver {
  List<_WeightPoint> points = [];
  double? currentWeight;
  double? targetWeight;

  StreamSubscription<void>? _weightSub; // ✅ اشتراك البث اللحظي
  bool _cloudWeightsRestored = false;
  Map<String, double> _cachedRemoteWeights = <String, double>{};

  Timer? _tick;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadWeights();
    _weightSub = WeightLiveBus.stream.listen((_) => _loadWeights());
    _tick = Timer.periodic(const Duration(seconds: 45), (_) => _loadWeights());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _weightSub?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadWeights();
    }
  }

  Future<void> _loadWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';

    // وزن اليوم الحالي للعرض السريع
    currentWeight = prefs.getDouble('current_weight_$email') ??
        prefs.getDouble('weight_$email');

    targetWeight = prefs.getDouble('goal_target_$email') ??
        prefs.getDouble('targetWeight_$email');

    // بعد حذف التطبيق: استرجع قراءات الوزن من السحابة مرة واحدة ثم ادمجها مع المحلي.
    final remoteWeights = !_cloudWeightsRestored
        ? await AppRepository.readWeightLogs(limit: 370)
        : _cachedRemoteWeights;
    if (!_cloudWeightsRestored) {
      _cachedRemoteWeights = remoteWeights;
      _cloudWeightsRestored = true;
    }

    // نجمع كل القراءات من المصدرين
    final map = <String, double>{};

    // 1) الحديث: weight_log_$email => List<Map>{date, kg}
    final raw = prefs.getString('weight_log_$email');
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final e in list) {
          final d = _normalizeYmd(e['date']);
          final kg = (e['kg'] as num?)?.toDouble();
          if (d != null && kg != null) map[d] = kg;
        }
      } catch (_) {}
    }

    // 2) القديم: weightHistory_$email => List<String(json)> {"date","weight"}
    final histList = prefs.getStringList('weightHistory_$email');
    if (histList != null) {
      for (final s in histList) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final d = _normalizeYmd(m['date']);
          final kg = (m['weight'] as num?)?.toDouble();
          if (d != null && kg != null) {
            map.putIfAbsent(d, () => kg); // لا نغطي الحديث لو موجود
          }
        } catch (_) {}
      }
    }

    // 3) لو عندنا وزن اليوم الحالي وغير موجود كقراءة اليوم
    final ymd =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .toIso8601String()
            .split('T')
            .first;
    if (currentWeight != null && !map.containsKey(ymd)) {
      map[ymd] = currentWeight!;
    }

    for (final e in remoteWeights.entries) {
      map.putIfAbsent(e.key, () => e.value);
    }
    if (currentWeight == null && remoteWeights.isNotEmpty) {
      final sortedRemoteDates = remoteWeights.keys.toList()..sort();
      currentWeight = remoteWeights[sortedRemoteDates.last];
      await prefs.setDouble('weight_$email', currentWeight!);
    }

    // تحويل إلى نقاط مرتبة (مع تحمّل أي مفاتيح غير صالحة)
    final pts = <_WeightPoint>[];
    for (final e in map.entries) {
      final dt = DateTime.tryParse(e.key);
      if (dt == null) continue;
      pts.add(_WeightPoint(DateTime(dt.year, dt.month, dt.day), e.value));
    }
    pts.sort((a, b) => a.t.compareTo(b.t));

    if (!mounted) return;
    setState(() => points = pts);
  }

  double _weeklyAvg() {
    final now = DateTime.now();
    final last7 = points
        .where((p) => now.difference(p.t).inDays <= 7)
        .map((e) => e.kg)
        .toList();
    if (last7.isEmpty) return 0;
    return last7.reduce((a, b) => a + b) / last7.length;
  }

  @override
  Widget build(BuildContext context) {
    final avg = _weeklyAvg();
    final cs = Theme.of(context).colorScheme;


    final double? delta = points.length >= 2
        ? (points.last.kg - points[points.length - 2].kg)
        : null;
    return RefreshIndicator(
      onRefresh: _loadWeights,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [cs.primary.withOpacity(.10), cs.secondary.withOpacity(.10)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('نصيحة سريعة',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface)),
                      const SizedBox(height: 2),
                      Text(
                        'سجّل وزنك بانتظام لملاحظة التغيّر. اضغط + لإضافة قراءة جديدة، ويمكنك تحديد هدفك من ملفك الشخصي.',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(.75),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (currentWeight != null || avg > 0 || (targetWeight != null && targetWeight! > 0))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.22)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.04),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.monitor_weight_outlined,
                                size: 18, color: cs.primary),
                            const SizedBox(width: 6),
                            Text('الحالي',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface.withOpacity(.8))),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            currentWeight == null
                                ? '--'
                                : '${currentWeight!.toStringAsFixed(1)} كجم',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface),
                          ),
                          if (delta != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'التغيّر: ${(delta! >= 0 ? '+' : '')}${delta!.toStringAsFixed(1)} كجم',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (delta! >= 0
                                          ? Colors.redAccent
                                          : Colors.green)
                                      .withOpacity(.9),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.insights_outlined,
                                size: 18, color: cs.secondary),
                            const SizedBox(width: 6),
                            Text('متوسط 7 أيام',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface.withOpacity(.8))),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            avg <= 0 ? '--' : '${avg.toStringAsFixed(1)} كجم',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface),
                          ),
                        ],
                      ),
                    ),
                    if (targetWeight != null && targetWeight! > 0) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.flag_outlined,
                                  size: 18, color: cs.tertiary),
                              const SizedBox(width: 6),
                              Text('الهدف',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface.withOpacity(.8))),
                            ]),
                            const SizedBox(height: 6),
                            Text(
                              '${targetWeight!.toStringAsFixed(1)} كجم',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 270,
            child: points.isEmpty
                ? const Center(child: Text('لا توجد قراءات بعد'))
                : Builder(
                    builder: (context) {
                      final n = points.length;
                      final spots = <FlSpot>[
                        for (int i = 0; i < n; i++)
                          FlSpot(i.toDouble(), points[i].kg),
                      ];
                      final ys = points.map((e) => e.kg).toList();
                      final minY = ys.reduce(math.min);
                      final maxY = ys.reduce(math.max);
                      final pad = (maxY - minY).abs() < 0.5
                          ? 1.0
                          : (maxY - minY) * 0.15;
                      final avgY = ys.reduce((a, b) => a + b) / ys.length;
                      final interval = math.max(1, (n / 5).floor());

                      return LineChart(
                        LineChartData(
                          minY: minY - pad,
                          maxY: maxY + pad,
                          lineTouchData: LineTouchData(
                            enabled: true,
                            handleBuiltInTouches: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipItems: (touched) => touched.map((s) {
                                final i = s.x.round().clamp(0, n - 1);
                                final dt = points[i].t;
                                return LineTooltipItem(
                                  '${DateFormat('yyyy/MM/dd').format(dt)}\n${s.y.toStringAsFixed(1)} كجم',
                                  TextStyle(color: cs.onSurface),
                                );
                              }).toList(),
                            ),
                          ),
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                interval: 1,
                                getTitlesWidget: (value, meta) {
                                  final i = value.round();
                                  if (i < 0 || i >= n) {
                                    return const SizedBox.shrink();
                                  }
                                  final show = (i % interval == 0) ||
                                      i == 0 ||
                                      i == n - 1;
                                  if (!show) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                        DateFormat('MM/dd').format(points[i].t)),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 34,
                                interval: (((maxY - minY) / 4)
                                        .clamp(0.5, 5.0))
                                    .toDouble(),
                                getTitlesWidget: (v, _) =>
                                    Text(v.toStringAsFixed(0)),
                              ),
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: (((maxY - minY) / 4)
                                    .clamp(0.5, 5.0))
                                .toDouble(),
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: Colors.grey.withOpacity(.18),
                              strokeWidth: 1,
                              dashArray: [4, 4],
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          extraLinesData: ExtraLinesData(
                            horizontalLines: [
                              HorizontalLine(
                                y: avgY,
                                color: cs.primary.withOpacity(.35),
                                strokeWidth: 1.5,
                                dashArray: [6, 4],
                                label: HorizontalLineLabel(
                                  show: true,
                                  alignment: Alignment.topRight,
                                  padding: const EdgeInsets.only(
                                      right: 4, bottom: 2),
                                  style:
                                      TextStyle(fontSize: 10, color: cs.primary),
                                  labelResolver: (_) => 'متوسط',
                                ),
                              ),
                              if (targetWeight != null && targetWeight! > 0)
                                HorizontalLine(
                                  y: targetWeight!,
                                  color: cs.secondary.withOpacity(.45),
                                  strokeWidth: 1.5,
                                  dashArray: [2, 4],
                                  label: HorizontalLineLabel(
                                    show: true,
                                    alignment: Alignment.topRight,
                                    padding: const EdgeInsets.only(
                                        right: 4, bottom: 2),
                                    style: TextStyle(
                                        fontSize: 10, color: cs.secondary),
                                    labelResolver: (_) => 'هدف',
                                  ),
                                ),
                            ],
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              curveSmoothness: .35,
                              barWidth: 3,
                              gradient: LinearGradient(colors: [
                                cs.primary,
                                cs.secondary,
                              ]),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    cs.primary.withOpacity(.18),
                                    cs.secondary.withOpacity(.05),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              dotData: FlDotData(
                                show: true,
                                checkToShowDot: (spot, barData) =>
                                    spot.x == (n - 1).toDouble(),
                                getDotPainter:
                                    (spot, percent, barData, index) =>
                                        FlDotCirclePainter(
                                  radius: 4.5,
                                  color: cs.primary,
                                  strokeWidth: 2,
                                  strokeColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('قراءات الوزن (الأحدث في الأسفل):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ...points.map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.monitor_weight_outlined),
                  title: Text('${p.kg.toStringAsFixed(1)} كجم'),
                  subtitle: Text(DateFormat('yyyy/MM/dd').format(p.t)),
                )),
          ],
        ],
      ),
    );
  }
}

class _WeightPoint {
  final DateTime t;
  final double kg;
  _WeightPoint(this.t, this.kg);
}

//// ========= Activity Tab =========
class _ActivityTab extends StatefulWidget {
  const _ActivityTab();
  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  // ⬅️ Health بنسخته الحديثة (بدل HealthFactory)
  final Health health = Health();

  int steps = 0;
  int burned = 0;

  Timer? _tick;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _fetchFromHealth();
    _tick = Timer.periodic(const Duration(seconds: 10), (_) => _loadSaved());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    final raw = prefs.getString('activity_${_todayKey()}_$email');
    if (raw != null) {
      final m = jsonDecode(raw);
      if (!mounted) return;
      final s = (m['steps'] as num?)?.toInt() ?? 0;
      final b = (m['burned'] as num?)?.toInt() ?? 0;
      setState(() {
        steps = s;
        burned = b;
      });
}
  }

  Future<void> _saveActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';
    await prefs.setString(
      'activity_${_todayKey()}_$email',
      jsonEncode({'steps': steps, 'burned': burned}),
    );
  }

  Future<void> _fetchFromHealth() async {
    try {
      final types = [HealthDataType.STEPS, HealthDataType.ACTIVE_ENERGY_BURNED];
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);

      await health.configure();

      final ok = await health.requestAuthorization(types);
      if (ok) {
        final data = await health.getHealthDataFromTypes(
          types: types,
          startTime: start,
          endTime: now,
        );

        int s = 0;
        double b = 0;
        for (final p in data) {
          if (p.type == HealthDataType.STEPS) s += (p.value as num).toInt();
          if (p.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
            b += (p.value as num).toDouble();
          }
        }
        if (!mounted) return;
        setState(() {
          steps = s;
          burned = b.toInt();
        });
await _saveActivity();
      }
    } catch (_) {
      // تجاهل لو غير مدعوم
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _stat('الخطوات', '$steps 👣', Icons.directions_walk, Colors.green),
        _stat('المحروق', '$burned 🔥', Icons.local_fire_department_outlined,
            Colors.red),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              minY: 0.0,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => Colors.black87,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final idx = group.x.toInt();
                    final value = rod.toY.toStringAsFixed(0);
                    return BarTooltipItem(
                      idx == 0 ? '$value خطوة' : '$value سعرة',
                      const TextStyle(color: Colors.white),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      switch (v.toInt()) {
                        case 0:
                          return const Text('خطوات');
                        case 1:
                          return const Text('محروق');
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(.2), dashArray: [4,4], strokeWidth: 1),),
              borderData: FlBorderData(show: false),
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barRods: [
                    BarChartRodData(
                      toY: steps.toDouble(),
                      color: Colors.green.withOpacity(.9),
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: math.max(steps.toDouble(), burned.toDouble()),
                        color: Colors.green.withOpacity(.15),
                      ),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 1,
                  barRods: [
                    BarChartRodData(
                      toY: burned.toDouble(),
                      color: Theme.of(context).colorScheme.primary.withOpacity(.9),
                      borderRadius: BorderRadius.circular(6),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: math.max(steps.toDouble(), burned.toDouble()),
                        color: Colors.red.withOpacity(.15),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _fetchFromHealth,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث من Health'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final sCtl = TextEditingController(text: steps.toString());
                final bCtl = TextEditingController(text: burned.toString());
                await showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('تعديل يدوي'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                            controller: sCtl,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(hintText: 'الخطوات')),
TextField(
                            controller: bCtl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                hintText: 'السعرات المحروقة')),
                      ],
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إلغاء')),
                      ElevatedButton(
                        onPressed: () async {
                          steps = int.tryParse(sCtl.text) ?? steps;
                          burned = int.tryParse(bCtl.text) ?? burned;
                          await _saveActivity();
                          if (context.mounted) Navigator.pop(context);
                          setState(() {});
                        },
                        child: const Text('حفظ'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text('تعديل يدوي'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    final onSurface = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withOpacity(.12)),
        color: color.withOpacity(0.06),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              Text(value, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== UI Enhancements: Kcal Summary Card & Cutting Hint =====
class _KcalSummaryCard extends StatelessWidget {
  final double todayKcal, targetKcal, p, c, f;
  final String goalType;
  const _KcalSummaryCard({
    required this.todayKcal,
    required this.targetKcal,
    required this.p,
    required this.c,
    required this.f,
    required this.goalType,
  });

  @override
Widget build(BuildContext context) {
  final remain = (targetKcal - todayKcal);
  final percent = targetKcal > 0 ? (todayKcal / targetKcal).clamp(0, 1) : 0.0;

  return Directionality(
    textDirection: ui.TextDirection.ltr, // ✅ Flutter TextDirection بدون تعارض
    child: Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.local_fire_department),
                const SizedBox(width: 8),
                Text(
                  'ملخص السعرات اليوم',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    '${remain >= 0 ? 'متبقي' : 'تجاوز'} ${_fmt(remain.abs())}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: percent.toDouble(),
                minHeight: 12,
              ),
            ),
Row(
              children: [
                Expanded(child: Text('اليوم: ${_fmt(todayKcal)} kcal')),
                Expanded(
                  child: Text(
                    'الهدف: ${_fmt(targetKcal)} kcal',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _MacroRow(label: 'بروتين', grams: p, kcal: p * 4),
            const Divider(height: 12),
            _MacroRow(label: 'كربوهيدرات', grams: c, kcal: c * 4),
            const Divider(height: 12),
            _MacroRow(label: 'دهون', grams: f, kcal: f * 9),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'إجمالي طاقة الماكروز: ${_fmt(p * 4 + c * 4 + f * 9)} kcal',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const SizedBox(height: 6),
            _CuttingHint(goalType: goalType, fatGrams: f),
          ],
        ),
      ),
    ),
  );
}


  String _fmt(num n) =>
      (n is int || n == n.roundToDouble()) ? n.toString() : n.toStringAsFixed(1);
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double grams;
  final double kcal;
  const _MacroRow({required this.label, required this.grams, required this.kcal});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          '${grams.toStringAsFixed(0)} جم  ·  ${kcal.toStringAsFixed(0)} kcal',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _CuttingHint extends StatelessWidget {
  final String goalType;
  final double fatGrams;
  const _CuttingHint({required this.goalType, required this.fatGrams});

  @override
  Widget build(BuildContext context) {
    if (goalType != 'cut' && goalType != 'تنشيف') return const SizedBox.shrink();
    // 👇 عدّل العتبة حسب سياستك/وزن المستخدم
    final bool highFat = fatGrams > 70;
    if (!highFat) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'دهونك اليوم مرتفعة وأنت على هدف تنشيف — حاول تخفّض الدهون في الوجبات القادمة.',
            ),
          ),
        ],
      ),
    );
  }
}


class _GoalCoachLine extends StatelessWidget {
  final String goal;
  final double latestKg;
  final double protein;
  final double fat;
  final double carbs;

  const _GoalCoachLine({
    required this.goal,
    required this.latestKg,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  @override
  Widget build(BuildContext context) {
    // عبارات بسيطة حسب الهدف — دون لمس أي منطق حسابي موجود
    String tip;
    switch (goal) {
      case 'تنشيف الدهون':
        tip = fat > 0 && protein > 0 ? 'تنبيه: الدهون أعلى من هدفك. جرّب تقليل الدهون وزيادة البروتين اليوم.' : 'ركز على بروتين أعلى ودهون أقل.';
        break;
      case 'بناء العضلات':
        tip = protein <= 0 ? 'ارفع البروتين وقسّم وجباتك لدعم البناء.' : 'استمر على بروتين كافٍ مع كارب داعم للتمرين.';
        break;
      case 'إنقاص الوزن':
        tip = 'حافظ على عجز سعري بسيط وتتبع الماء. تقدّم ثابت أهم من السرعة.';
        break;
      case 'زيادة الوزن':
        tip = 'ارفع الكارب الصحي وزد عدد الوجبات تدريجيًا.';
        break;
      default:
        tip = 'استمر على توازن الماكروز والماء والنوم الجيد.';
    }
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 16, color: Color(0xFF6A7C7C)),
        const SizedBox(width: 6),
        Expanded(child: Text(tip, style: TextStyle(color: cs.outline, fontSize: 12.5))),
      ],
    );
  }
}

//// ========= Insights Tab =========
class _InsightsTab extends StatefulWidget {
  const _InsightsTab();
  @override
  State<_InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<_InsightsTab> with WidgetsBindingObserver {
  final PageController _page = PageController();
  int _idx = 0;
  Timer? _auto;

  // كاش مؤقت لاسترجاع بيانات السعرات/الماء/الوزن من السحابة مرة واحدة فقط داخل تبويب التتبع.
  bool _cloudDailyRestoreDone = false;
  List<Map<String, dynamic>> _cachedRemoteDays = const <Map<String, dynamic>>[];

  // البيانات الأساسية
  double? heightCm;
  double? weightKg;
  int? age;
  String? gender;
  double? targetCal;
  double? targetProteinG;
  double? targetCarbG;
  double? targetFatG;
  int waterTargetMl = 2000;
  int stepsTarget = 8000;

  // ملخص الأيام الأخيرة
  late List<_DaySummary> last7 = [];

  Timer? _tick;
  bool _loadAllBusy = false;

  // اسم المستخدم للعرض + التقرير
  String _displayName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userNameSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
    _tick = Timer.periodic(const Duration(seconds: 60), (_) => _loadAll());
    _auto = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_idx + 1) % 5; // خمس شرائح
      _page.animateToPage(next, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _page.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (_loadAllBusy) return;
    _loadAllBusy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
    final email = await _currentEmail() ?? 'unknown_user';

    List<Map<String, dynamic>> remoteDays = _cachedRemoteDays;
    if (!_cloudDailyRestoreDone) {
      // لا نعلّق التبويب على الشبكة؛ المزامنة بالخلفية والقراءة من المحلي فورية.
      unawaited(TrackerStore.syncFromCloud(limit: 45));
      unawaited(WaterStore.syncFromCloud(limit: 45));
      remoteDays = const <Map<String, dynamic>>[];
      _cachedRemoteDays = remoteDays;
      _cloudDailyRestoreDone = true;
    }

    // -------- بيانات أساسية (قراءة مرنة للمفاتيح) --------
    heightCm = prefs.getDouble('height_$email') ??
        prefs.getDouble('height_cm_$email') ??
        (prefs.getInt('height_$email')?.toDouble());

    weightKg = prefs.getDouble('current_weight_$email') ??
        prefs.getDouble('weight_$email') ??
        prefs.getDouble('goal_current_$email');

    age = prefs.getInt('age_$email') ??
        (prefs.getString('age_$email') != null
            ? int.tryParse(prefs.getString('age_$email')!)
            : null);

    gender = _readStringFlexible(prefs, 'gender_$email');

    targetCal = prefs.getDouble('caloriesNeeded_$email');
    targetProteinG = prefs.getDouble('protein_$email');
    targetCarbG = prefs.getDouble('carbs_$email') ?? prefs.getDouble('carb_$email');
    targetFatG = prefs.getDouble('fat_$email');

    waterTargetMl = prefs.getInt('waterMlTarget_$email') ?? waterTargetMl;
    stepsTarget = prefs.getInt('stepsTarget_$email') ?? stepsTarget;

    // -------- خرائط مساعدة (ماء/وزن) --------
    final waterLitersMap = <String, double>{};
    final waterLogRaw = prefs.getString('water_log_$email');
    if (waterLogRaw != null) {
      try {
        final m = jsonDecode(waterLogRaw) as Map<String, dynamic>;
        for (final e in m.entries) {
          waterLitersMap[e.key] = (e.value as num).toDouble();
        }
      } catch (_) {}
    }
    for (final d in remoteDays) {
      final ymd = (d['date'] ?? '').toString();
      final water = d['water'];
      final liters = water is Map && water['liters'] is num
          ? (water['liters'] as num).toDouble()
          : 0.0;
      if (ymd.isNotEmpty && liters > 0) {
        waterLitersMap.putIfAbsent(ymd, () => liters);
      }
    }

    final weightMap = <String, double>{};
    final weightLogRaw = prefs.getString('weight_log_$email');
    if (weightLogRaw != null) {
      try {
        final list =
            (jsonDecode(weightLogRaw) as List).cast<Map<String, dynamic>>();
        for (final e in list) {
          final d = e['date']?.toString();
          final kg = (e['kg'] as num?)?.toDouble();
          if (d != null && kg != null) weightMap[d] = kg;
        }
      } catch (_) {}
    }
    final historyList = prefs.getStringList('weightHistory_$email');
    if (historyList != null) {
      for (final s in historyList) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final d = m['date']?.toString();
          final kg = (m['weight'] as num?)?.toDouble();
          if (d != null && kg != null) weightMap.putIfAbsent(d, () => kg);
        } catch (_) {}
      }
    }
    final todayYmd =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .toIso8601String()
            .split('T')
            .first;
    final currentW = prefs.getDouble('current_weight_$email') ??
        prefs.getDouble('weight_$email');
    if (currentW != null && !weightMap.containsKey(todayYmd)) {
      weightMap[todayYmd] = currentW;
    }
    for (final d in remoteDays) {
      final ymd = (d['date'] ?? '').toString();
      final tracking = d['tracking'];
      final kg = tracking is Map && tracking['weightKg'] is num
          ? (tracking['weightKg'] as num).toDouble()
          : 0.0;
      if (ymd.isNotEmpty && kg > 0) {
        weightMap.putIfAbsent(ymd, () => kg);
      }
    }

    // -------- آخر 7 أيام (أقدم -> أحدث) --------
    final now = DateTime.now();
    final tmp = <_DaySummary>[];

    for (int i = 6; i >= 0; i--) {
      final day =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final ymd = day.toIso8601String().split('T').first;

      // السعرات/الماكروز
      final totals = await _readTotalsForDate(prefs, email, ymd);
      final kcal = (totals['cal'] ?? 0.0);
      final p = (totals['p'] ?? 0.0);
      final c = (totals['c'] ?? 0.0);
      final f = (totals['f'] ?? 0.0);

      // الماء — التخزين باللتر في water_$ymd_$email
      double liters = prefs.getDouble('water_${ymd}_$email') ??
          waterLitersMap[ymd] ??
          0.0;
      final waterMl = (liters * 1000).round();

      // النشاط — التخزين في activity_$ymd_$email (JSON)
      int steps = 0, burned = 0;
      final aRaw = prefs.getString('activity_${ymd}_$email');
      if (aRaw != null) {
        try {
          final a = jsonDecode(aRaw) as Map<String, dynamic>;
          steps = (a['steps'] ?? 0) as int;
          burned = (a['burned'] ?? 0) as int;
        } catch (_) {}
      }

      // الوزن (اختياري)
      final w = weightMap[ymd];

      tmp.add(_DaySummary(
        date: day,
        kcal: kcal,
        waterMl: waterMl,
        steps: steps,
        protein: p,
        carb: c,
        fat: f,
        burned: burned,
        weightKg: w,
      ));
    }

    last7 = tmp;

      if (mounted) setState(() {});
    } finally {
      _loadAllBusy = false;
    }
  }

  _CalScore get _calScore {
    if (targetCal == null || targetCal == 0) return _CalScore(0, 'لا يوجد هدف سعرات');
    final tol = targetCal! * 0.10; // ±10%
    int okDays = 0;
    for (final d in last7) {
      if ((d.kcal - targetCal!).abs() <= tol) okDays++;
    }
    final pct = okDays / (last7.isEmpty ? 1 : last7.length);
    String label;
    if (pct >= .7) label = 'ممتاز';
    else if (pct >= .5) label = 'جيد';
    else label = 'بحاجة لتحسين';
    return _CalScore(okDays, label);
  }

  _WaterScore get _waterScore {
    int okDays = 0;
    for (final d in last7) {
      if (d.waterMl >= waterTargetMl) okDays++;
    }
    String label;
    if (okDays >= 5) label = 'ممتاز';
    else if (okDays >= 3) label = 'جيد';
    else label = 'بحاجة لتحسين';
    return _WaterScore(okDays, label);
  }

  _StepsScore get _stepsScore {
    int okDays = 0;
    for (final d in last7) {
      if (d.steps >= stepsTarget) okDays++;
    }
    String label;
    if (okDays >= 5) label = 'ممتاز';
    else if (okDays >= 3) label = 'جيد';
    else label = 'بحاجة لتحسين';
    return _StepsScore(okDays, label);
  }

  double? get _bmi {
    final h = heightCm;
    final w = weightKg;
    if (h == null || w == null || h <= 0) return null;
    final m = h / 100.0;
    return w / (m * m);
  }

  String _bmiLabel(double bmi) {
    if (bmi < 18.5) return 'نحافة';
    if (bmi < 25) return 'طبيعي';
    if (bmi < 30) return 'زيادة وزن';
    if (bmi < 35) return 'سمنة (١)';
    if (bmi < 40) return 'سمنة (٢)';
    return 'سمنة مفرطة';
  }


  List<String> _buildRecommendations() {
    final recs = <String>[];

    // بناء على BMI
    if (_bmi != null) {
      final b = _bmi!;
      if (b >= 30) {
        recs.addAll([
          'استهدف عجزًا سعريًا 10–15% لمدة 6–8 أسابيع ثم راحة أسبوع.',
          'اجعل البروتين بين 1.8–2.2 جم/كجم من وزن الجسم يوميًا.',
          'قسّم وجباتك إلى 3–4 وجبات ثابتة لتقليل الجوع.',
        ]);
      } else if (b >= 25) {
        recs.addAll([
          'عجز سعري معتدل 10% يكفي للوصول لهدفك تدريجيًا.',
          'ارفع خطواتك اليومية +1500 خطوة فوق المتوسط الحالي.',
        ]);
      } else if (b < 18.5) {
        recs.addAll([
          'فائض سعري خفيف 5–10% مع تركيز على البروتين والجودة.',
          'تمارين مقاومة 3 مرات أسبوعيًا لزيادة الكتلة العضلية.',
        ]);
      } else {
        recs.add('حافظ على السعرات الحالية مع بروتين كافٍ وتمارين مقاومة للحفاظ على التناسق.');
      }
    }

    // التزام السعرات
    if (_calScore.okDays >= 5) {
      recs.add('استمر! التزامك بالسعرات ممتاز خلال الأسبوع.');
    } else if (_calScore.okDays <= 2) {
      recs.addAll([
        'حضّر وجباتك مسبقًا ليومين–ثلاثة لتسهيل الالتزام.',
        'استبدل المشروبات السكرية بالماء/القهوة السوداء/الشاي.',
      ]);
    } else {
      recs.add('قلّل “اللقيمات بين الوجبات” واجعل سناك بروتيني/خضار.');
    }

    // الماء
    if (_waterScore.okDays <= 2) {
      recs.addAll([
        'احمل معك قنينة ماء وحدد تنبيه كل 90 دقيقة.',
        'ابدأ يومك بكوبين ماء وأضف كوبًا قبل كل وجبة.',
      ]);
    } else if (_waterScore.okDays >= 5) {
      recs.add('ترطيب ممتاز — استمر على هدف الماء اليومي.');
    }

    // الخطوات
    if (_stepsScore.okDays <= 2) {
      recs.addAll([
        'أضف 10 دقائق مشي بعد الغداء والعشاء.',
        'اركن بعيدًا درجتين إضافيتين + استخدم الدرج بدل المصعد.',
      ]);
    } else if (_stepsScore.okDays >= 5) {
      recs.add('فكّر بزيادة هدفك 500–1000 خطوة للأسبوع القادم.');
    }

    // توصيات عامة مرنة
    if (weightKg != null) {
      final minP = (weightKg!*1.6).round();
      final maxP = (weightKg!*2.2).round();
      recs.add('استهدف بروتين يومي بين ~%d–%d جم.'.replaceFirst('%d', minP.toString()).replaceFirst('%d', maxP.toString()));
    }
    recs.addAll([
      'نم 7–8 ساعات ليلًا واغلق الشاشات قبل النوم بـ 60 دقيقة.',
      'أدخل خضار/ألياف في وجبتين على الأقل يوميًا.',
      'ثبّت مواعيد وجباتك قدر الإمكان لتقليل قرارات اليوم.',
      'مرّة أسبوعيًا: مراجعة الوزن والمتوسط لتقييم التقدم.',
    ]);

    // إزالة التكرارات والاقتصار على 8–12 بند
    final seen = <String>{};
    final dedup = <String>[];
    for (final r in recs) {
      if (!seen.contains(r)) { seen.add(r); dedup.add(r); }
    }
    if (dedup.length > 12) {
      return dedup.sublist(0, 12);
    } else if (dedup.length < 8) {
      const fillers = [
        'بدّل المقليات بالشوي أو القلاية الهوائية.',
        'اجعل أول لقمة من البروتين/الخضار لتقليل الشهية.',
        'اختر قهوة بدون إضافات سكرية.',
        'وزّع حصص الدهون الصحية (زيت زيتون/مكسرات) بدل الزيادات العشوائية.',
      ];
      dedup.addAll(fillers.take(8 - dedup.length));
    }
    return dedup;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t  = Theme.of(context).textTheme;
    final nPages = 5;

    final recs = _buildRecommendations();

    return Column(
      children: [
        // مؤشّر شبيه الستوري
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: List.generate(nPages, (i) {
              final active = i == _idx;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsetsDirectional.only(end: i == nPages-1 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: active ? cs.primary : cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: PageView(
            controller: _page,
            onPageChanged: (i) => setState(() => _idx = i),
            children: [
              _InsightCard(
                gradient: [cs.primaryContainer, cs.surface],
                title: 'الطول والوزن',
                big: _bmi == null ? '—' : _bmi!.toStringAsFixed(1),
                subtitle: _bmi == null ? 'أدخل بياناتك لنحسب مؤشر كتلة الجسم' : 'BMI — ${_bmiLabel(_bmi!)}',
                extra: (heightCm != null && weightKg != null)
                    ? 'الطول: ${heightCm!.toStringAsFixed(0)} سم • الوزن: ${weightKg!.toStringAsFixed(1)} كجم'
                    : 'الطول/الوزن غير مكتملين',
              ),
              _InsightCard(
                gradient: [cs.secondaryContainer, cs.surface],
                title: 'التزام السعرات (٧ أيام)',
                big: '${_calScore.okDays}/7',
                subtitle: targetCal == null ? 'لا يوجد هدف سعرات' : 'هدفك: ${targetCal!.toStringAsFixed(0)} سعرة',
                extra: 'التقييم: ${_calScore.label}',
              ),
              _InsightCard(
                gradient: [cs.tertiaryContainer, cs.surface],
                title: 'الماء (٧ أيام)',
                big: '${_waterScore.okDays}/7',
                subtitle: 'هدفك: ${waterTargetMl} مل',
                extra: 'التقييم: ${_waterScore.label}',
              ),
              _InsightCard(
                gradient: [cs.primaryContainer, cs.surfaceVariant],
                title: 'الخطوات (٧ أيام)',
                big: '${_stepsScore.okDays}/7',
                subtitle: 'هدفك: ${stepsTarget} خطوة',
                extra: 'التقييم: ${_stepsScore.label}',
              ),
              // الشريحة الخامسة: توصيات ذكية
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [cs.secondaryContainer, cs.surface], begin: Alignment.topRight, end: Alignment.bottomLeft),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: cs.shadow.withOpacity(.08), blurRadius: 16, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('توصيات ذكية لك', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: recs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.check_circle_rounded, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(child: Text(recs[i], style: t.bodyMedium)),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  final List<Color> gradient;
  final String title;
  final String big;
  final String subtitle;
  final String extra;
  const _InsightCard({
    required this.gradient,
    required this.title,
    required this.big,
    required this.subtitle,
    required this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t  = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: cs.shadow.withOpacity(.08), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(big, style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(width: 10),
                Expanded(child: Text(subtitle, style: t.bodyMedium)),
              ],
            ),
            const Spacer(),
            Text(extra, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _DaySummary {
  final DateTime date;
  final double kcal;
  final double protein;
  final double carb;
  final double fat;
  final int waterMl;
  final int steps;
  final int burned;
  final double? weightKg;

  _DaySummary({
    required this.date,
    required this.kcal,
    required this.waterMl,
    required this.steps,
    this.protein = 0,
    this.carb = 0,
    this.fat = 0,
    this.burned = 0,
    this.weightKg,
  });
}

class _CalScore {
  final int okDays; final String label;
  _CalScore(this.okDays, this.label);
}
class _WaterScore {
  final int okDays; final String label;
  _WaterScore(this.okDays, this.label);
}
class _StepsScore {
  final int okDays; final String label;
  _StepsScore(this.okDays, this.label);
}

/// Event bus لتحديث صفحة تتبع الماكروز فورياً عند إضافة/حذف الوجبات من صفحات أخرى.
class MacrosLiveBus {
  static final _ctrl = StreamController<void>.broadcast();
  static void ping() { if (!_ctrl.isClosed) _ctrl.add(null); }
  static StreamSubscription listen(void Function() fn) => _ctrl.stream.listen((_) => fn());
}
