import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyHealthTips {
  // يمنع تكرار إظهار النصيحة مرتين بنفس الجلسة بسبب استدعاءات متقاربة
  static final Set<String> _sessionLocks = <String>{};

  // نصايح يومية باللهجة العامية لكل هدف
  static final Map<String, List<String>> _tips = {
    'إنقاص الوزن': [
      'خلّ أكلك أقل شوي من احتياجك… فرق بسيط يوميًا يجيب نتيجة.',
      'قبل لا تاكل اشرب موية، كثير مرات نحسب العطش جوع.',
      'إذا بتسوي “سناك”، خله شي يشبع مثل زبادي/بيض/فواكه.',
      'حط بروتين في كل وجبة عشان احساس الشبع يكون أطول.',
      'نص صحنك خضار… يملّي البطن وسعراته قليلة.',
      'خفف المشروبات السكرية والغازية هي اللي ترفع السعرات بسرعة.',
      'لو تقدر امشِ 10 دقايق بعد الأكل، تفرق كثير.',
      'لا تاكل وأنت تتفرج… بدون ما تحس تخلص الكيس كله.',
      'خلّ الزيوت والصلصات على قدّها… هي “سعرات مخفية”.',
      'نام زين… قلة النوم تخلّي النفسية والجوع أسوأ.',
      'سوّ لك خطة بسيطة للأسبوع بدل ما تتفاجأ بالجوع.',
      'إذا غلطت بوجبة، لا تقول “خربت”… كمّل طبيعي.',
    ],
    'زيادة الوزن': [
      'زود أكلك شوي شوي… لا تقلبها دفعة وحدة وتتعّب.',
      'خلّ عندك عدد/سناكات باليوم حتى لو صغيرة.',
      'البروتين مهم… حاول يكون موجود كل يوم وبأكثر من وجبة.',
      'السموذي بالحليب/الزبادي يساعدك تزود سعرات بدون ثقل.',
      'ضيف دهون مفيدة: مكسرات، أفوكادو، زبدة فول سوداني.',
      'بعد التمرين خذ كارب وبروتين… يعينك على التعافي.',
      'اشتغل على تمارين مركبة… هي اللي تبني جسمك أسرع.',
      'سجل أكلك يومين وشوف وين ناقصك… يمكن تحسبك تاكل كثير وأنت لا.',
      'إذا شهيتك ضعيفة، زود 100–150 سعرة كل كم يوم.',
      'لا تعتمد على السكريات طول الوقت… بتزيد دهون أكثر من فائدة.',
    ],
    'بناء العضلات': [
      'أهم شي الاستمرار… لا تتحمس أسبوع وتختفي شهر.',
      'زود الأوزان أو التكرارات تدريجيًا  .',
      'ركز على التكنيك قبل لا تثقل… عشان ما تطيح بإصابة.',
      'خلّ بروتينك موزّع على اليوم، مو وجبة وحدة.',
      'تمارين الأساسيات تكفيك: سكوات، بنش، ظهر، كتف.',
      'قرّب من الفشل بالعدّات بس بأمان… لا تتهور.',
      'قبل التمرين سو إحماء خفيف… وبعده إطالة بسيطة.',
      'النوم مو كسل… هو اللي يبني عضلك فعليًا.',
      'لا تكثر كارديو إذا هدفك تضخيم… خله معقول.',
      'لو أكلك “صيانة + شوي” يكون أفضل من ضخامة عشوائية.',
    ],
    'خفض الدهون': [
      'خفف المقليات والوجبات السريعة… هي اللي تعطل كل شي.',
      'سوّ خطواتك أعلى… المشي يحرق بدون ما تحس.',
      'لا تكثر صوصات… ملعقتين ممكن تسوى وجبة كاملة!',
      'خلّ سناكك بروتين + شي فيه ألياف… يشبعك أكثر.',
      'وازن أسبوعك… مو لازم كل يوم يكون 100%.',
      'تابع مقاسات/صور… الميزان لحاله يخدع بسبب السوائل.',
      'إذا بتاكل برا، اختار مشوي/فرن بدل مقلي.',
      'اشرب موية على مدار اليوم… كثير يخلطون بين العطش والجوع.',
      'سهر أقل = جوع أقل… تجربة كل الناس.',
      'خلّ مكافأتك “حصة صغيرة” مو يوم كامل مفتوح.',
    ],
    'الصيام المتقطع': [
      'ابدأ بالتدريج… لا تدخل 16/8 من أول يوم.',
      'خلك على قهوة سادة/موية وقت الصيام… لا تدخل سعرات.',
      'إذا تتعب، زود أملاح خفيفة أو شوربة داخل نافذة الأكل.',
      'لا تعوض كل شي بوجبة وحدة… قسم أكلك داخل النافذة.',
      'خل فطورك يبدأ ببروتين… يثبت الطاقة.',
      'إذا تمرينك قوي، خله قريب من وقت الأكل.',
      'ثبّت وقتك قدر الإمكان… العادة تسهّل الالتزام.',
      'راقب نومك… الصيام مع سهر = تعب وجوع.',
      'إذا حسّيت دوخة متكررة… خفف وراجع وضعك.',
    ],
    'نمط حياة صحي': [
      'تحرك 20–30 دقيقة باليوم… حتى لو مشي بسيط.',
      'خل أكلك ألوان… خضار وفواكه متنوعة.',
      'موية… لا تستسهلها. سو لك تذكير.',
      'إذا شغلك جلوس، قم كل ساعة وتحرك دقيقتين.',
      'خفف سكر… مو لازم تمنع، بس قلّل.',
      'خلك على نوم ثابت قد ما تقدر.',
      'شمس الصباح 5–10 دقايق تفرق بالمزاج.',
      'إذا توترت، خذ نفس عميق كم مرة وهدّي.',
      'رتّب مشترياتك… اللي بالبيت هو اللي بتاكله.',
      'جهّز خضار جاهزة بالثلاجة عشان ما تكسل.',
    ],
    'خفض ضغط الدم': [
      'خفف الملح قد ما تقدر… خصوصًا الأكل الجاهز.',
      'امشِ بشكل منتظم… حتى 30 دقيقة باليوم ممتاز.',
      'كثر أكل فيه بوتاسيوم: موز، سبانخ، بطاطس.',
      'خفف المقليات واللحوم المصنعة… ترفع الصوديوم.',
      'تابع ضغطك بين فترة وفترة.',
      'إذا تشرب كافيين كثير، جرّب تقلله وشوف الفرق.',
      'الوزن الزايد يرفع الضغط… أي نزول بسيط يفيد.',
      'إذا عندك أدوية/حالة، لا تغيّر شي إلا مع طبيبك.',
    ],
    'زيادة النشاط اليومي': [
      'خذ الدرج بدل المصعد لو تقدر.',
      'امشِ 5 دقايق كل ساعة… منبّه بالجوال يساعد.',
      'اركن أبعد شوي… خطوات زيادة بدون ما تحس.',
      'سو مكالماتك وأنت تتمشى.',
      'بعد الوجبة امشِ 10 دقايق… هضم وطاقة.',
      'حط هدف خطوات واقعي وزوده تدريجي.',
      'خل عندك جزمة مريحة بالسيارة/الدوام.',
      'إذا طفشت، سو نشاط قصير 7 دقايق بالبيت.',
    ],
    'تحسين الصحة العامة': [
      'سوي فحوصات دورية حسب عمرك ووضعك.',
      'لا تترك نفسك طول اليوم على شاشة… خذ فواصل.',
      'اهتم بجلستك… الظهر يتعب بسرعة.',
      'وازن بين الشغل والراحة… لا تحرق نفسك.',
      'الأكل الليلي الثقيل يخرب النوم… خففه.',
      'حط وقت بسيط لشي تحبه… رياضة/قراءة/هواية.',
      'كُل ببطء… المخ يتأخر لين يحس بالشبع.',
      'خلك اجتماعي… النفسية جزء من الصحة.',
    ],
    'ضبط مستوى السكر': [
      'امشِ 10–15 دقيقة بعد الأكل… يساعد كثير.',
      'لا تكدّس نشويات بوجبة وحدة… وزّعها.',
      'اختر كارب أهدى: شوفان، بقوليات، خبز أسمر.',
      'خل مع النشويات بروتين وألياف… عشان ما يرتفع بسرعة.',
      'خفف العصيرات… الفاكهة الكاملة أفضل.',
      'راقب حجم الحصة… خصوصًا رز/خبز.',
      'سجّل اللي يأثر عليك… كل جسم يختلف.',
      'إذا عندك خطة علاج/دواء، التزم وتابع مع طبيبك.',
    ],
    'اتباع رجيم نباتي': [
      'خل بروتينك حاضر: عدس، حمص، فول، توفو.',
      'انتبه لفيتامين B12… غالبًا تحتاج مكمل أو أكل مدعّم.',
      'للحديد: عدس/سبانخ + شي فيه فيتامين C مثل ليمون.',
      'أوميغا-3: شيا/كتّان/جوز… أو مكمل طحالب.',
      'نوّع بين حبوب وبقول… يعطيك بروتين أكمل.',
      'لا تعتمد على أكل نباتي “مصنّع” كثير… مو دايم صحي.',
      'راقب بروتينك خصوصًا لو تتمرن.',
      'جرّب وصفات جديدة عشان ما تمل بسرعة.',
    ],
  };

  static List<String> _forGoal(String goal) {
    return _tips[goal] ?? _tips['نمط حياة صحي']!;
  }

  /// يطلع نصيحة اليوم إذا ما انعرضت اليوم لهالمستخدم (وبنفس الهدف)
  static Future<void> showTodayIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentEmail') ?? 'guest';
    final goal = prefs.getString('goal_$email') ?? 'نمط حياة صحي';

    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // ربطناها بالهدف بعد عشان لو تغيّر هدفه ما يصير لخبطه
    final seenKey = 'daily_tip_seen_${email}_$goal';
    final indexKey = 'daily_tip_index_${email}_$goal';

    // ✅ قفل للجلسة (يعالج ظهورها مرتين بسبب استدعاءات متزامنة/متقاربة)
    final sessionLock = '$email|$goal|$todayKey';
    if (_sessionLocks.contains(sessionLock)) return;
    _sessionLocks.add(sessionLock);

    try {
      // إذا انعرضت اليوم لهذا الهدف خلاص
      if (prefs.getString(seenKey) == todayKey) return;

      // ✅ قفل تخزين سريع (يعالج السباق قبل ما يتم تحديث seenKey بعد إغلاق الـSheet)
      final inflightKey = 'daily_tip_inflight_${email}_$goal';
      if (prefs.getString(inflightKey) == todayKey) return;
      await prefs.setString(inflightKey, todayKey);

      final tips = _forGoal(goal);
      int? idx = prefs.getInt(indexKey);

      if (idx == null) {
        // أول مرة لهالهدف: اختيار “عشوائي ثابت” حسب اليوم + المستخدم
        final seedStr = '$email|$goal|$todayKey';
        final seed =
            seedStr.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
        idx = seed % tips.length;
      } else {
        // بعدها ندور يوميًا
        idx = (idx + 1) % tips.length;
      }

      final tip = tips[idx];

      await _showSheet(
        context,
        title: 'نصيحة اليوم 💡',
        subtitle: 'هدفك الحالي: $goal',
        tip: tip,
      );

      // حدث الحالة (مرّة واحدة باليوم)
      await prefs.setString(seenKey, todayKey);
      await prefs.setInt(indexKey, idx);
    } finally {
      _sessionLocks.remove(sessionLock);
    }
  }

  static Future<void> _showSheet(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String tip,
  }) async {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final t = theme.textTheme;

    await Future<void>.delayed(Duration.zero);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      backgroundColor: s.surface,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: s.primaryContainer,
                  foregroundColor: s.onPrimaryContainer,
                  child: const Icon(Icons.lightbulb),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(tip, style: t.bodyMedium)),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('تم ✅'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
