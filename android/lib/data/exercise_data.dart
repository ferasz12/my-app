// lib/virtual_gym/exercise_data.dart
// نفس البنية مع توسيع كبير في قاعدة التمارين الأساسية (_base)
// يولّد التمارين تلقائياً لكل مستوى ولكل "تنويع تقني"

class Exercise {
  final String id;
  final String name;
  final String baseName;
  final String group;
  final bool isHome;
  final String level; // Beginner / Intermediate / Advanced
  final List<String> equipment;
  final List<String> goals;
  final String description;
  final String benefits;
  final String youtube;
  final List<String> muscles;

  const Exercise({
    required this.id,
    required this.name,
    required this.baseName,
    required this.group,
    required this.isHome,
    required this.level,
    required this.equipment,
    required this.goals,
    required this.description,
    required this.benefits,
    required this.youtube,
    required this.muscles,
  });
}

class ExerciseData {
  // مستويات ثابتة كما هي
  static const List<String> levels = ["Beginner", "Intermediate", "Advanced"];

  // تنويعات تقنية عامة (نفس المنطق القديم)
  static const List<String> _techMods = [
    "قبضة واسعة",
    "قبضة ضيقة",
    "نطاق جزئي",
    "إيقاع بطيء",
    "إيقاف سفلي",
    "سوبرسِت",
  ];

  // قاعدة موسّعة: نفس التمارين مع أسماء دارجة + وصف/فوائد مبسّطة
  static final List<Map<String, dynamic>> _base = [
    // ---------- الصدر ----------
    {
      "name": "بنش برس بار",
      "group": "الصدر",
      "isHome": false,
      "equipment": ["Barbell", "Bench"],
      "goals": ["بناء العضلات", "نمط حياة صحي"],
      "description": "استلقِ على البنش، ثبّت كتفك واسحب لوحَي الكتف، ونزّل البار فوق وسط الصدر وارفعه بقوة.",
      "benefits": "يبني قوة وكتلة للصدر مع مساهمة للتراي والكتف الأمامي.",
      "youtube": "https://www.youtube.com/watch?v=SCVCLChPQFY",
      "muscles": ["Chest", "Triceps", "Front Delts"]
    },
    {
      "name": "بنش مائل دمبل",
      "group": "الصدر",
      "isHome": false,
      "equipment": ["Dumbbell", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "بنش مائل خفيف، نزّل الدمبل ببطء واطلع للعالي مع ضغط الصدر.",
      "benefits": "يركّز على الصدر العلوي ويحسّن التوازن بين الجانبين.",
      "youtube": "https://www.youtube.com/watch?v=8iPEnn-ltC8",
      "muscles": ["Upper Chest", "Triceps"]
    },
    {
      "name": "فلآي دمبل (تفتيح)",
      "group": "الصدر",
      "isHome": false,
      "equipment": ["Dumbbell", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "افتح الذراعين قوسيًّا مع ثني بسيط للكوعين وارجع أقفل على الصدر.",
      "benefits": "تمطيط وعزل ممتاز لألياف الصدر.",
      "youtube": "https://www.youtube.com/watch?v=eozdVDA78K0",
      "muscles": ["Chest"]
    },
    {
      "name": "كروس أوفر كيبل",
      "group": "الصدر",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["بناء العضلات"],
      "description": "خطوة قدّام بسيطة، اسحب المقابض للقدّام وتقبّض الصدر بالمنتصف.",
      "benefits": "توتر مستمر وعزل للصدر من زوايا مختلفة.",
      "youtube": "https://www.youtube.com/watch?v=taI4XduLpTk",
      "muscles": ["Chest"]
    },
    {
      "name": "ديبس صدر",
      "group": "الصدر",
      "isHome": false,
      "equipment": ["Parallel Bars"],
      "goals": ["بناء العضلات"],
      "description": "ميل جسمك للأمام، انزل تحت بتحكم واطلع بقوة مع تقبّض الصدر.",
      "benefits": "يركّز على الصدر السفلي ويقوّي الترايسبس.",
      "youtube": "https://www.youtube.com/watch?v=2z8JmcrW-As",
      "muscles": ["Lower Chest", "Triceps", "Front Delts"]
    },
    {
      "name": "بوش أب مائل (على كرسي)",
      "group": "الصدر",
      "isHome": true,
      "equipment": ["Bodyweight", "Chair"],
      "goals": ["تحسين اللياقة العامة", "نمط حياة صحي"],
      "description": "يدينك على سطح مرتفع، نزل صدرك واطلع مع شدّ الجذع.",
      "benefits": "بديل منزلي ممتاز للتحميل على الصدر.",
      "youtube": "https://www.youtube.com/watch?v=IODxDxX7oi4",
      "muscles": ["Chest", "Triceps", "Front Delts"]
    },

    // ---------- الظهر ----------
    {
      "name": "بار رو أرضي",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Barbell"],
      "goals": ["بناء العضلات"],
      "description": "ميل جذعك للأمام بظهر محايد، اسحب البار لبطنك واثبت ثواني.",
      "benefits": "يزوّد سمك الظهر الأوسط والسفلي ويقوّي القبضة.",
      "youtube": "https://www.youtube.com/watch?v=vT2GjY_Umpw",
      "muscles": ["Lats", "Mid-back", "Biceps"]
    },
    {
      "name": "سحب عالي أمامي (Lat Pulldown)",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description": "اسحب البار/المقبض لأسفل للصدر وقرّب لوحَي الكتف من بعض.",
      "benefits": "يعرض الظهر ويفعّل اللات بشكل واضح.",
      "youtube": "https://www.youtube.com/watch?v=CAwf7n6Luuc",
      "muscles": ["Lats", "Biceps"]
    },
    {
      "name": "ون آرم دمبل رو",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Dumbbell", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "ادعم جسمك على البنش واسحب الدمبل لفوق بدون لف ظهر.",
      "benefits": "يعالج الفروقات بين الجانبين ويعزل اللات.",
      "youtube": "https://www.youtube.com/watch?v=pYcpY20QaE8",
      "muscles": ["Lats", "Rear Delts"]
    },
    {
      "name": "عقلة قبضة واسعة (Pull-Up)",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Pull-up Bar"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description": "اطلع حتى ذقنك فوق البار، شدّ لوحَي كتفك لتقوية اللات.",
      "benefits": "أفضل تمرين لعرض الظهر؛ وزن جسم كامل.",
      "youtube": "https://www.youtube.com/watch?v=eGo4IYlbE5g",
      "muscles": ["Lats", "Biceps", "Rear Delts"]
    },
    {
      "name": "Chin-Up (قبضة معكوسة)",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Pull-up Bar"],
      "goals": ["بناء العضلات"],
      "description": "راحة اليدين باتجاهك لزيادة شغل البايسبس مع الظهر.",
      "benefits": "يجمّع قوة للبايسبس واللات معًا.",
      "youtube": "https://www.youtube.com/watch?v=b3XyZV1JZNo",
      "muscles": ["Biceps", "Lats"]
    },
    {
      "name": "تي-بار رو (T-Bar Row)",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["T-Bar", "Barbell"],
      "goals": ["بناء العضلات"],
      "description": "سحب ثابت مع صدر مثبت وكتف راجع لزيادة سمك الظهر.",
      "benefits": "يضرب الظهر الأوسط بقوة وتحكم.",
      "youtube": "https://www.youtube.com/watch?v=VHR4tZ0QJ7g",
      "muscles": ["Mid-back", "Lats", "Rear Delts"]
    },
    {
      "name": "ديدلفت تقليدي",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Barbell"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description": "ارفع البار من الأرض بظهر محايد وكعبين ثابتة.",
      "benefits": "قوة شاملة للسلسلة الخلفية وتحسين الأداء العام.",
      "youtube": "https://www.youtube.com/watch?v=op9kVnSso6Q",
      "muscles": ["Posterior Chain", "Hamstrings", "Glutes", "Lower Back", "Traps"]
    },
    {
      "name": "Face Pull (كيبل)",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["تحسين القوام", "بناء العضلات"],
      "description": "اسحب الحبل باتجاه الوجه بمرفقين مرتفعين وكتف راجع.",
      "benefits": "يعالج انحناءة الكتف ويقوّي الخلفي والروتيتور كف.",
      "youtube": "https://www.youtube.com/watch?v=rep-qVOkqgk",
      "muscles": ["Rear Delts", "Traps", "Rotator Cuff"]
    },

    // ---------- الأكتاف ----------
    {
      "name": "شولدر برس بار (جالس)",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Barbell", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "ادفع البار فوق الراس بخط عمودي، بطن مشدود وظهر ثابت.",
      "benefits": "يقوّي الدلتويد الأمامي والجانبي مع الترايسبس.",
      "youtube": "https://www.youtube.com/watch?v=qEwKCR5JCog",
      "muscles": ["Front Delts", "Triceps"]
    },
    {
      "name": "رفرفة جانبية دمبل (سايد رف)",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "ارفع الدمبل جانبياً لمستوى الكتف بدون تذبذب بالجسم.",
      "benefits": "يزيد عرض الكتف ويبرز الدلتويد الجانبي.",
      "youtube": "https://www.youtube.com/watch?v=3VcKaXpzqRo",
      "muscles": ["Lateral Delts"]
    },
    {
      "name": "رفرفة خلفية دمبل",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "انحنِ خفيف وارفع الدمبل للخلف مع عصر لوحَي الكتف.",
      "benefits": "يقوّي الخلفي ويوازن الكتف ويحسّن القوام.",
      "youtube": "https://www.youtube.com/watch?v=EA7u4Q_8HQ0",
      "muscles": ["Rear Delts", "Upper Back"]
    },
    {
      "name": "أرنولد برس",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "ضغط كتف مع تدوير القبضة أثناء الرفع للنطاق الكامل.",
      "benefits": "يستهدف الأمامي والجانبي ويزيد التحكم.",
      "youtube": "https://www.youtube.com/watch?v=6Z15_WdXmVw",
      "muscles": ["Front Delts", "Lateral Delts", "Triceps"]
    },
    {
      "name": "فرونت ريز دمبل",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "ارفع الدمبل قدّامك حتى كتفك، بدون تقوّس للظهر.",
      "benefits": "يركّز على الدلتويد الأمامي.",
      "youtube": "https://www.youtube.com/watch?v=-t7fuZ0KhDA",
      "muscles": ["Front Delts"]
    },
    {
      "name": "شراجز دمبل",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "ارفع كتفك لفوق واثبت، ونزّل ببطء بتحكم.",
      "benefits": "يقوّي الترابيس العلوية ويحسّن الثبات.",
      "youtube": "https://www.youtube.com/watch?v=GcX1SOwq4nA",
      "muscles": ["Traps"]
    },
    {
      "name": "أب رايت رو بار",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Barbell"],
      "goals": ["بناء العضلات"],
      "description": "اسحب البار لفوق بمحاذاة الجسم حتى تحت الذقن.",
      "benefits": "يضرب الترابيس والدلتويد الجانبي.",
      "youtube": "https://www.youtube.com/watch?v=JEb9gJh3spE",
      "muscles": ["Traps", "Lateral Delts"]
    },

    // ---------- الذراعين (باي/تراي/سواعد) ----------
    // بايسبس
    {
      "name": "كورل بايسبس بار مستقيم",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Barbell"],
      "goals": ["بناء العضلات"],
      "description": "اثنِ المرفق وارفع البار بدون ترجيح للجسم.",
      "benefits": "يزيد كتلة البايسبس وقوة الساعد.",
      "youtube": "https://www.youtube.com/watch?v=kwG2ipFRgfo",
      "muscles": ["Biceps"]
    },
    {
      "name": "كورل بايسبس دمبل تبادلي",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "ارفع كل ذراع بالتبادل مع تدوير راحة اليد للأعلى.",
      "benefits": "نطاق حركة أفضل ومعالجة الفروقات الجانبية.",
      "youtube": "https://www.youtube.com/watch?v=ykJmrZ5v0Oo",
      "muscles": ["Biceps"]
    },
    {
      "name": "هامر كورل دمبل",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "قبضة مطرقة (محايدة) لزيادة شغل العضدية والسواعد.",
      "benefits": "سُمك الذراع وقوة القبضة.",
      "youtube": "https://www.youtube.com/watch?v=zC3nLlEvin4",
      "muscles": ["Biceps", "Brachialis", "Forearms"]
    },
    {
      "name": "بريچر كورل (EZ)",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["EZ Bar", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "على مقعد الواعظ لعزل البايسبس وتقليل الغش.",
      "benefits": "قمة/تعريف للبايسبس بشكل أوضح.",
      "youtube": "https://www.youtube.com/watch?v=ZglRj5B5H8s",
      "muscles": ["Biceps"]
    },
    {
      "name": "إنكلين دمبل كورل",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Dumbbell", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "على بنش مائل لتمديد ألياف البايسبس ورفع بتحكم.",
      "benefits": "يشغّل الألياف الطويلة ويزيد الطول الشكلي.",
      "youtube": "https://www.youtube.com/watch?v=soxrZlIl35U",
      "muscles": ["Biceps"]
    },

    // ترايسبس
    {
      "name": "ترايسبس كيبل حبل",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["بناء العضلات"],
      "description": "مدّ الحبل لتحت وافتحه أسفل الحركة مع ثبات الكوع.",
      "benefits": "يعزل الترايسبس ويبرز الجانبي.",
      "youtube": "https://www.youtube.com/watch?v=vB5OHsJ3EME",
      "muscles": ["Triceps"]
    },
    {
      "name": "سكول كراشر (EZ Bar)",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["EZ Bar", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "اثنِ وامدد المرفقين وأنت مستلقي مع تحكم كامل.",
      "benefits": "يضرب الرأس الطويل للترايسبس ويزيد السمك.",
      "youtube": "https://www.youtube.com/watch?v=d_KZxkY_0cM",
      "muscles": ["Triceps"]
    },
    {
      "name": "كلوز قبضة بنش",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Barbell", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "قبضة أضيق على البنش لرفع مساهمة الترايسبس.",
      "benefits": "قوة ترايسبس ممتازة مع دعم للصدر.",
      "youtube": "https://www.youtube.com/watch?v=s4Cvet40H5g",
      "muscles": ["Triceps", "Chest", "Front Delts"]
    },
    {
      "name": "ديبس بنش (منزلي)",
      "group": "الذراعين",
      "isHome": true,
      "equipment": ["Bodyweight", "Chair"],
      "goals": ["نمط حياة صحي", "تحسين اللياقة العامة"],
      "description": "ادعم يديك على كرسي، انزل بتحكم واطلع مع شدّ الترايسبس.",
      "benefits": "تمرين بسيط وفعّال للترايسبس في البيت.",
      "youtube": "https://www.youtube.com/watch?v=6kALZikXxLc",
      "muscles": ["Triceps", "Chest"]
    },

    // سواعد
    {
      "name": "رست كورل (راحة لفوق)",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Barbell", "Dumbbell"],
      "goals": ["بناء العضلات", "تحسين القبضة"],
      "description": "ثبّت الساعدين وحرّك الرسغ لفوق ببطء وتحكم.",
      "benefits": "يقوّي مثنيات المعصم والسواعد.",
      "youtube": "https://www.youtube.com/watch?v=2Jm-WlG7r6E",
      "muscles": ["Forearms", "Wrist Flexors"]
    },
    {
      "name": "ريفيرس رست كورل",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Barbell", "Dumbbell"],
      "goals": ["بناء العضلات", "تحسين القبضة"],
      "description": "قبضة لأسفل وحرّك الرسغ لفوق مع تركيز على الباسطات.",
      "benefits": "يقوّي باسطات المعصم ويوازن الساعدين.",
      "youtube": "https://www.youtube.com/watch?v=8E3xZ8Vt_4k",
      "muscles": ["Forearms", "Wrist Extensors"]
    },
    {
      "name": "ريفيرس كورل (EZ/بار)",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["EZ Bar", "Barbell"],
      "goals": ["بناء العضلات"],
      "description": "كورل بقبضة معكوسة لفوق لتشغيل العضدية الكعبرية.",
      "benefits": "يزيد سماكة الساعد ويكمّل شكل الذراع.",
      "youtube": "https://www.youtube.com/watch?v=J8Ywz6YJdxs",
      "muscles": ["Forearms", "Brachioradialis", "Biceps"]
    },
    {
      "name": "فارمر ووك",
      "group": "الذراعين",
      "isHome": false,
      "equipment": ["Dumbbell", "Kettlebell"],
      "goals": ["تحسين اللياقة العامة", "تحسين القبضة"],
      "description": "امشِ بمسك أوزان ثقيلة بكل يد مع قوام مستقيم ونَفَس ثابت.",
      "benefits": "قبضة وترابيس وجذع قوية جدًا.",
      "youtube": "https://www.youtube.com/watch?v=Q86zun8J5wY",
      "muscles": ["Forearms", "Traps", "Core"]
    },

    // ---------- الأرجل ----------
    {
      "name": "سكوات بار",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Barbell", "Rack"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description": "نزل للموازي بظهر محايد وكعبين ثابتة واطلع بقوة.",
      "benefits": "قوة شاملة وكواد/ألوية/هامسترنغ.",
      "youtube": "https://www.youtube.com/watch?v=1xMaFs0L3ao",
      "muscles": ["Quads", "Glutes", "Hamstrings"]
    },
    {
      "name": "لانجز دمبل",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "خطوة قدّام 90° بالرُكَب، ادفع بالكعب وارجع.",
      "benefits": "توازن وتفعيل قوي للألوية والفخذين.",
      "youtube": "https://www.youtube.com/watch?v=QOVaHwm-Q6U",
      "muscles": ["Quads", "Glutes"]
    },
    {
      "name": "ليج برس",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات"],
      "description": "ادفع المنصّة مع ظهر ثابت، تحكّم بالنزول والطلوع.",
      "benefits": "تحميل آمن للفخذين وتقليل ضغط أسفل الظهر.",
      "youtube": "https://www.youtube.com/watch?v=IZxyjW7MPJQ",
      "muscles": ["Quads", "Glutes"]
    },
    {
      "name": "RDL رفعة رومانية",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Barbell", "Dumbbell"],
      "goals": ["بناء العضلات"],
      "description": "هينج من الحوض وظهر محايد، نزّل الوزن مع تمديد هامسترنغ.",
      "benefits": "يشغّل الهامسترنغ والألوية وأسفل الظهر بقوة.",
      "youtube": "https://www.youtube.com/watch?v=6P20npkvcb8",
      "muscles": ["Hamstrings", "Glutes", "Lower Back"]
    },
    {
      "name": "هيب ثرست بار",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Barbell", "Bench"],
      "goals": ["بناء العضلات"],
      "description": "ادفع الحوض للأعلى واثبت فوق مع تقبّض الألوية.",
      "benefits": "أفضل تفعيل للألوية وتحسين قوة الدفع.",
      "youtube": "https://www.youtube.com/watch?v=LM8XHLYJoYs",
      "muscles": ["Glutes", "Hamstrings"]
    },
    {
      "name": "غلوت بريدج (منزلي)",
      "group": "الأرجل",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["نمط حياة صحي"],
      "description": "ارفع الحوض من الأرض واثبت ثانية وانزل بتحكم.",
      "benefits": "تفعيل سريع للألوية في البيت.",
      "youtube": "https://www.youtube.com/watch?v=m2N0kdD0sGQ",
      "muscles": ["Glutes", "Hamstrings", "Core"]
    },
    {
      "name": "Leg Extension",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات"],
      "description": "مدّ الركبة لفوق مع تركيز على الكواد.",
      "benefits": "عزل قوي للفخذ الأمامي.",
      "youtube": "https://www.youtube.com/watch?v=yRdl6GWJ7nY",
      "muscles": ["Quads"]
    },
    {
      "name": "Leg Curl (ممدد/جالس)",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات"],
      "description": "اثنِ الركبة لتحت مع ثبات الحوض.",
      "benefits": "عزل للهامسترنغ وتحسين القوة الخلفية.",
      "youtube": "https://www.youtube.com/watch?v=1Tq3QdYUuHs",
      "muscles": ["Hamstrings"]
    },
    {
      "name": "كالف رايز واقف",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Machine", "Smith"],
      "goals": ["بناء العضلات"],
      "description": "اطلع على رؤوس الأصابع واثبت فوق وانزل ببطء.",
      "benefits": "سمانة خارجية (Gastrocnemius) أقوى وشكل أوضح.",
      "youtube": "https://www.youtube.com/watch?v=YMmgqO8Jo-k",
      "muscles": ["Calves"]
    },
    {
      "name": "كالف رايز جالس",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات"],
      "description": "ارفع الكعبين وأنت جالس لتركّز على النعلية.",
      "benefits": "يشغّل السمانة العميقة (Soleus).",
      "youtube": "https://www.youtube.com/watch?v=YMmgqO8Jo-k",
      "muscles": ["Calves"]
    },
    {
      "name": "Hip Abduction (تبعيد الورك)",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Machine", "Cable"],
      "goals": ["تحسين القوام", "بناء العضلات"],
      "description": "ابعِد الفخذ للخارج مع ثبات الجذع.",
      "benefits": "استقرار الحوض والركبة وتقوية الألوية الجانبية.",
      "youtube": "https://www.youtube.com/watch?v=73rQMCN3C5Y",
      "muscles": ["Glute Medius", "Abductors"]
    },
    {
      "name": "Hip Adduction (تقريب الورك)",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["تحسين اللياقة العامة"],
      "description": "قرّب الفخذين للداخل مع تحكم.",
      "benefits": "تقوية المقربات ودعم الركبة.",
      "youtube": "https://www.youtube.com/watch?v=7q9Rr7H1nS8",
      "muscles": ["Adductors"]
    },

    // ---------- البطن/الكور ----------
    {
      "name": "كرنش",
      "group": "البطن",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["خفض الدهون", "نمط حياة صحي"],
      "description": "ارفع الجزء العلوي بتقبّض البطن بدون شدّ الرقبة.",
      "benefits": "يشغّل البطن العلوي ويقوّي الانقباض.",
      "youtube": "https://www.youtube.com/watch?v=MKmrqcoCZ-M",
      "muscles": ["Abs"]
    },
    {
      "name": "بلانك",
      "group": "البطن",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["نمط حياة صحي", "تحسين اللياقة العامة"],
      "description": "جسمك خط مستقيم، شدّ الجذع ونفَس ثابت.",
      "benefits": "ثبات للجذع ودعم لأسفل الظهر.",
      "youtube": "https://www.youtube.com/watch?v=pSHjTRCQxIw",
      "muscles": ["Core", "Lower Back"]
    },
    {
      "name": "رفع رجلين (Leg Raise)",
      "group": "البطن",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["خفض الدهون"],
      "description": "ارفع رجولك مع لصق أسفل ظهرك بالأرض.",
      "benefits": "يركّز على البطن السفلي والهيب فليكسور.",
      "youtube": "https://www.youtube.com/watch?v=JB2oyawG9KI",
      "muscles": ["Lower Abs", "Hip Flexors"]
    },
    {
      "name": "Russian Twist",
      "group": "البطن",
      "isHome": true,
      "equipment": ["Bodyweight", "Plate"],
      "goals": ["تحسين اللياقة العامة"],
      "description": "لفّ الجذع يمين ويسار مع ثبات الحوض.",
      "benefits": "يشغّل الأوبليك (الجانبية) ويقوّي الكور.",
      "youtube": "https://www.youtube.com/watch?v=wkD8rjkodUI",
      "muscles": ["Obliques", "Abs"]
    },
    {
      "name": "Side Plank",
      "group": "البطن",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["نمط حياة صحي"],
      "description": "اثبت على جانبك مع شدّ الجذع بدون هبوط للحوض.",
      "benefits": "ثبات جانبي قوي ويحمي أسفل الظهر.",
      "youtube": "https://www.youtube.com/watch?v=K2VljzCC16g",
      "muscles": ["Obliques", "Core"]
    },
    {
      "name": "Bicycle Crunch (الدراجة)",
      "group": "البطن",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["نمط حياة صحي"],
      "description": "بدّل بين الكوع والركبة مع تمديد الرجل الثانية.",
      "benefits": "تنشيط شامل للبطن والجانبية.",
      "youtube": "https://www.youtube.com/watch?v=9FGilxCbdz8",
      "muscles": ["Abs", "Obliques", "Hip Flexors"]
    },

    // ---------- أسفل الظهر ----------
    {
      "name": "هايبر إكستنشن",
      "group": "أسفل الظهر",
      "isHome": false,
      "equipment": ["Machine", "Roman Chair"],
      "goals": ["تحسين اللياقة العامة"],
      "description": "مدّ الجذع من انثناء خفيف واطلع بتحكم مع شدّ القطنية.",
      "benefits": "يقوّي أسفل الظهر ويحسّن القوام.",
      "youtube": "https://www.youtube.com/watch?v=ph3pddpKzzw",
      "muscles": ["Lower Back", "Glutes"]
    },

    // ---------- تمارين منزلية عامة ----------
    {
      "name": "سكوات وزن الجسم",
      "group": "تمارين منزلية",
      "isHome": true,
      "equipment": ["None", "Bodyweight"],
      "goals": ["نمط حياة صحي", "زيادة النشاط اليومي", "تحسين اللياقة العامة"],
      "description": "نزل واطلع بثبات، ركبك باتجاه أصابع القدم وجذعك مشدود.",
      "benefits": "يقوّي الأرجل ويحسّن الحركة بدون أدوات.",
      "youtube": "https://www.youtube.com/watch?v=UXJrBgI2RxA",
      "muscles": ["Quads", "Glutes"]
    },
    {
      "name": "قفز الحبل",
      "group": "تمارين منزلية",
      "isHome": true,
      "equipment": ["Jump Rope"],
      "goals": ["خفض الدهون", "تحسين اللياقة العامة", "زيادة النشاط اليومي"],
      "description": "قفز مستمر بإيقاع ثابت وتنفس هادي.",
      "benefits": "كارديو قوي وحرق عالي للسعرات.",
      "youtube": "https://www.youtube.com/watch?v=QZzmbYg6r_U",
      "muscles": ["Calves", "Cardio"]
    },
    {
      "name": "بوش أب",
      "group": "تمارين منزلية",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["نمط حياة صحي", "تحسين اللياقة العامة"],
      "description": "نزل صدرك للأرض واطلع مع شدّ الجذع وخط جسم مستقيم.",
      "benefits": "يقوّي الصدر والكتف والترايسبس بوزن الجسم.",
      "youtube": "https://www.youtube.com/watch?v=IODxDxX7oi4",
      "muscles": ["Chest", "Triceps", "Front Delts"]
    },
    
    // ---------- إضافات جديدة 2025-10-17 ----------
    {
      "name": "سكواد بلغاري (Bulgarian Split Squat)",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Dumbbell", "Bench"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description": "اتّكئ بقدمك الخلفية على بنش، وانزل بالقدم الأمامية مع جذع مستقيم وركبة متتبعة لأصابع القدم.",
      "benefits": "يقوّي الكواد والألوية ويعالج الاختلالات الجانبية.",
      "youtube": "https://www.youtube.com/watch?v=2C-uNgKwPLE",
      "muscles": ["Quads", "Glutes", "Adductors"]
    },
    {
      "name": "هيب ثرست بار (Barbell Hip Thrust)",
      "group": "الألوية",
      "isHome": false,
      "equipment": ["Barbell", "Bench", "Pad"],
      "goals": ["بناء العضلات", "قوة"],
      "description": "اسند أعلى ظهرك على البنش، وادفع الورك للأعلى مع ضغط المؤخرة وثبات الذقن والصدر.",
      "benefits": "أقوى تمرين استهداف مباشر للألوية مع تقليل ضغط أسفل الظهر.",
      "youtube": "https://www.youtube.com/watch?v=LM8XHLYJoYs",
      "muscles": ["Glutes", "Hamstrings"]
    },
    {
      "name": "رومانيان ديدلفت (RDL)",
      "group": "الأرجل",
      "isHome": false,
      "equipment": ["Barbell"],
      "goals": ["قوة", "بناء العضلات"],
      "description": "قبضة على عرض الكتفين، اثنِ الركبة قليلًا وارجع الورك للخلف مع ظهر محايد والبار قريب من الساقين.",
      "benefits": "يطوّر سلسلة خلفية قوية: هِمسترنج وألوية وأسفل ظهر.",
      "youtube": "https://www.youtube.com/watch?v=uhghy9pFIPY",
      "muscles": ["Hamstrings", "Glutes", "Erectors"]
    },
    {
      "name": "بندلي رو (Pendlay Row)",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Barbell"],
      "goals": ["قوة", "بناء العضلات"],
      "description": "ظهر موازي للأرض تقريبًا، اسحب البار من الأرض لأسفل الصدر بانفجار ثم أعده للأرض كل تكرار.",
      "benefits": "يعزّز القوة الانفجارية وشغل اللات والرومبويدز مع ثبات العمود.",
      "youtube": "https://www.youtube.com/watch?v=C_p-s66KBpg",
      "muscles": ["Lats", "Rhomboids", "Traps", "Erectors"]
    },
    {
      "name": "فيس بول (Face Pull)",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Cable", "Rope Handle"],
      "goals": ["تصحيح القوام", "بناء العضلات"],
      "description": "اسحب الحبل نحو الوجه مع تدوير خارجي للمرفقين وشفط لوحي الكتف للخلف.",
      "benefits": "يقوّي الخلفي من الكتف ويحسّن صحة مفصل الكتف.",
      "youtube": "https://www.youtube.com/watch?v=eIq5CB9JfKE",
      "muscles": ["Rear Delts", "Rhomboids", "Rotator Cuff"]
    },
    {
      "name": "لاندماين برس (Landmine Press)",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Barbell", "Landmine"],
      "goals": ["قوة", "استقرار"],
      "description": "من وضع نصف ركوع، ادفع طرف البار قطريًا للأعلى مع شدّ الجذع ومنع ميل الحوض.",
      "benefits": "آمن للكتف ويجمع بين الدفع العمودي والأمامي.",
      "youtube": "https://www.youtube.com/watch?v=qFXojXa-RCU",
      "muscles": ["Front Delts", "Serratus", "Triceps", "Core"]
    },
    {
      "name": "زد برس دمبل (Z Press)",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["قوة", "استقرار"],
      "description": "جلوس أرضي بسيقان ممدودة، ادفع الدمبلز فوق الرأس بدون مساهمة من الأرجل.",
      "benefits": "يعزّز استقرار الجذع وقوة الكتف مع عزل للجزء العلوي.",
      "youtube": "https://www.youtube.com/watch?v=BK2z6pRRbvQ",
      "muscles": ["Front Delts", "Triceps", "Core"]
    },
    {
      "name": "رفرفة جانبية كيبل (Cable Lateral Raise)",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["بناء العضلات"],
      "description": "ارفع الذراع جانبًا بخط قوسي مع شدّ المعصم قليلًا والإبهام لأسفل للحفاظ على خط الكتف.",
      "benefits": "توتّر مستمر للدلتويد الجانبي طوال الحركة.",
      "youtube": "https://www.youtube.com/watch?v=Z5FA9aq3L6A",
      "muscles": ["Side Delts"]
    },
    {
      "name": "بالوف برس (Pallof Press)",
      "group": "الكور",
      "isHome": false,
      "equipment": ["Cable", "Band"],
      "goals": ["استقرار", "تصحيح القوام"],
      "description": "قف جانبيًا للكيبل، اضغط المقبض للأمام مع مقاومة الدوران وحافظ على الحوض والثدي ثابتين.",
      "benefits": "تمرين مضاد للدوران يقوّي الجذع العميق ويحمي أسفل الظهر.",
      "youtube": "https://www.youtube.com/watch?v=axgv7H_VQOo",
      "muscles": ["Obliques", "Transverse Abdominis"]
    },
    {
      "name": "سوينغ كتلبيل (Kettlebell Swing)",
      "group": "الكارديو/قوة",
      "isHome": true,
      "equipment": ["Kettlebell"],
      "goals": ["تحسين اللياقة العامة", "قوة"],
      "description": "مفصل ورك قوي يدفع الجرس للأمام، الظهر محايد والكتف مرتخية والذراعان يعملان كخطاف.",
      "benefits": "يرفع اللياقة ويطوّر الانفجار في السلسلة الخلفية.",
      "youtube": "https://www.youtube.com/watch?v=aGf1LuMCp4M",
      "muscles": ["Glutes", "Hamstrings", "Back"]
    },
    {
      "name": "تركيش غِت-أب (Turkish Get-Up)",
      "group": "الكور",
      "isHome": true,
      "equipment": ["Kettlebell", "Dumbbell"],
      "goals": ["استقرار", "تحسين اللياقة العامة"],
      "description": "انهض من الاستلقاء إلى الوقوف وأنت تحمل الوزن فوق الرأس مع متابعة النظر للوزن طوال الوقت.",
      "benefits": "يبني ثبات الكتف والمركز والتنسيق عبر سلسلة حركات وظيفية.",
      "youtube": "https://www.youtube.com/watch?v=iM2oTXgnDRU",
      "muscles": ["Core", "Shoulders", "Glutes"]
    },
    {
      "name": "فارمر كاري (Farmer's Carry)",
      "group": "الكور/قوة",
      "isHome": true,
      "equipment": ["Dumbbell", "Kettlebell"],
      "goals": ["قوة", "تحسين اللياقة العامة"],
      "description": "امشِ حاملاً أوزانًا ثقيلة بجانبك مع قفص صدري منخفض وكتفين لأسفل وقبضة قوية.",
      "benefits": "يقوّي القبضة والجذع وعضلات ما حول الكتف ويحسّن التحمل.",
      "youtube": "https://www.youtube.com/watch?v=8OtwXwrJizk",
      "muscles": ["Forearms", "Traps", "Core", "Glutes"]
    },
    {
      "name": "كوبنهاغن بلانك (Copenhagen Plank)",
      "group": "الكور",
      "isHome": true,
      "equipment": ["Bench"],
      "goals": ["استقرار", "تصحيح القوام"],
      "description": "ارتكز بالقدم العليا على بنش وارفع الحوض مع شدّ المقعدين الداخليين وإبقاء الجسم بخط واحد.",
      "benefits": "يقوّي المقربات (أدكتورز) ويعزّز ثبات الحوض.",
      "youtube": "https://www.youtube.com/watch?v=YRRnnZsRs9U",
      "muscles": ["Adductors", "Obliques", "Core"]
    },
    {
      "name": "هولو بودي هولد (Hollow Body Hold)",
      "group": "الكور",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["استقرار"],
      "description": "الأسفل ملاصق للأرض، الذراعان والساقان ممتدّتان قليلًا عن الأرض مع شدّ البطن.",
      "benefits": "أساس ممتاز لاستقرار الجذع وحركات الجمباز.",
      "youtube": "https://www.youtube.com/watch?v=LlDNef_Ztsc",
      "muscles": ["Transverse Abdominis", "Rectus Abdominis"]
    },
    {
      "name": "ديد بغ (Dead Bug)",
      "group": "الكور",
      "isHome": true,
      "equipment": ["Bodyweight"],
      "goals": ["استقرار", "تصحيح القوام"],
      "description": "استلقِ على ظهرك وحرّك الذراع والساق المتعاكستين مع إبقاء أسفل الظهر ملتصقًا بالأرض.",
      "benefits": "يعلّم التحكم الحركي ويخفّض ضغط أسفل الظهر.",
      "youtube": "https://www.youtube.com/watch?v=g_BYB0R-4Ws",
      "muscles": ["Core", "Hip Flexors"]
    }  ];

  /// التوليد: يكرّر كل تمرين أساسي عبر المستويات والتنويعات التقنية
  static List<Exercise> generate() {
    final List<Exercise> out = [];
    int counter = 1;

    for (final b in _base) {
      for (final level in levels) {
        for (final mod in _techMods) {
          final id = "EX${counter++}";
          final baseName = b["name"] as String;
          final name = "$baseName - $mod ($level)";
          out.add(Exercise(
            id: id,
            name: name,
            baseName: baseName,
            group: b["group"] as String,
            isHome: b["isHome"] as bool,
            level: level,
            equipment: List<String>.from(b["equipment"] as List),
            goals: List<String>.from(b["goals"] as List),
            description: "${b["description"]} | تنويع: $mod | مستوى: $level.",
            benefits: b["benefits"] as String,
            youtube: b["youtube"] as String,
            muscles: List<String>.from(b["muscles"] as List),
          ));
        }
      }
    }
    return out;
  }
}
