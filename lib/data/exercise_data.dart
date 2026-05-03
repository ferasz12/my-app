// lib/data/exercise_data.dart
//
// قاعدة تمارين النادي الافتراضي — (نسخة مختصرة)
// ✅ تحتوي فقط على المقاطع التي زودتنا بها
// ✅ سيتم إضافة مقاطع أخرى لاحقاً

class Exercise {
  final String id;
  final String name;
  final String baseName;
  final String group;
  final bool isHome;
  final String level; // Beginner / Intermediate / Advanced (يستخدم فقط في وضع التوليد)
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
  // مستويات ثابتة كما هي (إن احتجتها لاحقاً)
  static const List<String> levels = ["Beginner", "Intermediate", "Advanced"];

  // تنويعات تقنية عامة (تُستخدم فقط في generate)
  static const List<String> _techMods = [
    "قبضة واسعة",
    "قبضة ضيقة",
    "نطاق جزئي",
    "إيقاع بطيء",
    "إيقاف سفلي",
    "سوبرسِت",
  ];

  // ✅ فقط التمارين التي أرسلتها (صدر/ظهر/كتف/تراي/باي)
  static final List<Map<String, dynamic>> _base = [
    // ---------- الصدر ----------
    {
      "name": "الصدر المستوي - CHEST PRESS",
      "group": "الصدر",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description":
          "اضبط المقعد بحيث تكون المقابض بمستوى منتصف الصدر. اثبت لوحي الكتف للخلف، ادفع للأمام بدون قفل كامل للمرفق، وارجع ببطء حتى تحس بتمدد بسيط.",
      "benefits":
          "يعزل الصدر بشكل آمن ويوفر مسار ثابت يقلل الضغط على الكتف مقارنة بالبنش الحر.",
      "youtube": "https://youtube.com/shorts/Vospq67uxtk?feature=share",
      "muscles": ["Chest", "Triceps", "Front Delts"]
    },
    {
      "name": "صدر علوي - INCLINE CHEST PRESS",
      "group": "الصدر",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description":
          "اجعل الميل متوسط، وارفع الصدر للأعلى مع تثبيت الكتف للخلف. ادفع للأعلى وللأمام، ثم انزل ببطء حتى يكون الكوع تحت مستوى الكتف بقليل.",
      "benefits": "يركز على الصدر العلوي ويحسن شكل امتلاء الصدر من الأعلى.",
      "youtube": "https://youtube.com/shorts/2CaKaGakG9M?feature=share",
      "muscles": ["Upper Chest", "Triceps", "Front Delts"]
    },
    {
      "name": "تفتيح صدر - PEC DEC FLY",
      "group": "الصدر",
      "isHome": false,
      "equipment": ["Pec Deck"],
      "goals": ["بناء العضلات"],
      "description":
          "اضبط المقعد بحيث يكون الكتف بمستوى المرفق. اترك ثني خفيف بالمرفق، اقفل الذراعين للأمام مع عصر الصدر، وارجع ببطء بدون ترك الأوزان ترتطم.",
      "benefits": "عزل قوي للصدر وتوتر مستمر مناسب لزيادة الإحساس بالعضلة.",
      "youtube": "https://youtube.com/shorts/RbcqTYlb7Mc?feature=share",
      "muscles": ["Chest"]
    },

    // ---------- الظهر ----------
    {
      "name": "اللاتس - LAT PULLDOWN",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description":
          "ثبت فخذك تحت الوسادة، شد لوحي الكتف للأسفل أولاً، ثم اسحب البار للجزء العلوي من الصدر مع صدر مرفوع. ارجع ببطء للتمدد.",
      "benefits": "يزيد عرض الظهر (اللاتس) ويحسن قوة السحب.",
      "youtube": "https://youtube.com/shorts/htbfrvJj51w?feature=share",
      "muscles": ["Lats", "Biceps"]
    },
    {
      "name": "SEATED ROW - لاتس",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات"],
      "description":
          "اجلس بظهر محايد، اسحب المقبض للبطن مع سحب لوحي الكتف للخلف، وارجع ببطء بدون دفع الكتف للأمام بشكل مبالغ.",
      "benefits": "يبني سمك الظهر الأوسط ويقوي العضلات المساندة للكتف.",
      "youtube": "https://youtube.com/shorts/rYkTB9vdKj4?feature=share",
      "muscles": ["Mid-back", "Lats", "Biceps"]
    },
    {
      "name": "ظهر علوي - CHEST SUPPORTED ROW",
      "group": "الظهر",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات"],
      "description":
          "اسند صدرك على الوسادة، اسحب المقابض للخلف مع رفع بسيط للصدر، وركز على ضم لوحي الكتف. ارجع ببطء مع تحكم.",
      "benefits": "يعزل الظهر العلوي ويقلل الغش لأن الصدر مسنود.",
      "youtube": "https://youtube.com/shorts/gNTkQZDQa0k?feature=share",
      "muscles": ["Upper Back", "Rear Delts", "Biceps"]
    },

    // ---------- الأكتاف ----------
    {
      "name": "الكتف الجانبي - LATERAL RAISE",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Dumbbell"],
      "goals": ["بناء العضلات"],
      "description":
          "ارفع الدمبل للجانب حتى مستوى الكتف مع انحناء بسيط بالمرفق. لا ترفع أعلى من اللازم ولا تهز الجسم. انزل ببطء.",
      "benefits": "يبني عرض الكتف ويعطي شكل V للجسم.",
      "youtube": "https://youtube.com/shorts/tEc2-KoQcWA?feature=share",
      "muscles": ["Side Delts"]
    },
    {
      "name": "SHOULDER PRESS - كتف امامي",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description":
          "ثبت الكتف للخلف والأسفل، ادفع للأعلى بدون قفل كامل للمرفق، وانزل حتى يكون الكوع تحت مستوى الكتف بقليل.",
      "benefits": "يقوي الكتف الأمامي ويرفع القوة في تمارين الدفع.",
      "youtube": "https://youtube.com/shorts/VcA5Nwcm2HU?feature=share",
      "muscles": ["Front Delts", "Triceps"]
    },
    {
      "name": "كتف خلفي - REVERSE PEC DEC FLY",
      "group": "الأكتاف",
      "isHome": false,
      "equipment": ["Pec Deck"],
      "goals": ["بناء العضلات", "تحسين الوضعية"],
      "description":
          "اجلس مع صدر ملاصق للوسادة (أو بالعكس حسب الجهاز). ابدأ بذراعين أمامك، افتح للخارج مع عصر الكتف الخلفي، وارجع ببطء بدون اندفاع.",
      "benefits":
          "يقوي الكتف الخلفي ويحسن وضعية الكتف ويقلل تقوس الأكتاف للأمام.",
      "youtube": "https://youtube.com/shorts/Dia6g3EsExY?feature=share",
      "muscles": ["Rear Delts", "Upper Back"]
    },

    // ---------- تراي ----------
    {
      "name": "تراي - TRICEPS OVERHEAD EXTENSION",
      "group": "تراي",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["بناء العضلات"],
      "description":
          "ثبت المرفقين قريبين من الرأس، مد الذراع للأعلى حتى الاستقامة، ثم ارجع ببطء مع بقاء العضد ثابت.",
      "benefits": "يستهدف الرأس الطويل للترايسبس ويزيد حجم الذراع من الخلف.",
      "youtube": "https://youtube.com/shorts/DH72qp9S1rA?feature=share",
      "muscles": ["Triceps"]
    },
    {
      "name": "تراي بوش داون - TRICEPS PUSHDOWN",
      "group": "تراي",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["بناء العضلات", "تحسين اللياقة العامة"],
      "description":
          "اثبت المرفقين بجانب الجسم، ادفع للأسفل حتى تمد الذراع بالكامل مع عصر الترايسبس، ثم اطلع ببطء بدون تحريك الكتف.",
      "benefits": "يعزل الترايسبس ويقوي الدفع في البنش والضغط.",
      "youtube": "https://youtube.com/shorts/tchrIsm-U1w?feature=share",
      "muscles": ["Triceps"]
    },

    // ---------- باي ----------
    {
      "name": "باي كيبل كيرل - BICEPS CABLE CURL",
      "group": "باي",
      "isHome": false,
      "equipment": ["Cable"],
      "goals": ["بناء العضلات"],
      "description":
          "اثبت المرفقين بجانب الجسم، ارفع للأعلى حتى أقصى انقباض، ثم انزل ببطء مع شد مستمر من الكيبل.",
      "benefits": "توتر مستمر على البايسبس ويساعد على تضخيم الذراع.",
      "youtube": "https://youtube.com/shorts/QG2kDLdD97c?feature=share",
      "muscles": ["Biceps"]
    },
    {
      "name": "باي كيرل - PREACHER CURL",
      "group": "باي",
      "isHome": false,
      "equipment": ["Machine"],
      "goals": ["بناء العضلات"],
      "description":
          "ثبت الذراع على مسند الواعظ، ارفع ببطء بدون رفع الكتف، ثم انزل بتحكم حتى تمد الذراع.",
      "benefits": "يعزل البايسبس ويقلل الغش ويقوي الجزء السفلي من الحركة.",
      "youtube": "https://youtube.com/shorts/QLJdFc_VNKI?feature=share",
      "muscles": ["Biceps"]
    },
  ];

  /// التوليد: يكرّر كل تمرين أساسي عبر المستويات والتنويعات التقنية (يُستخدم فقط إذا فتحت وضع التوليد)
  static List<Exercise> generate() {
    final List<Exercise> out = [];
    int counter = 1;

    for (final b in _base) {
      for (final level in levels) {
        for (final mod in _techMods) {
          final id = "EX${counter++}";
          final baseName = b["name"] as String;
          final name = "$baseName - $mod ($level)";
          out.add(
            Exercise(
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
            ),
          );
        }
      }
    }
    return out;
  }

  /// مكتبة بدون تكرار — تُرجع كل تمرين مرة واحدة كما هو في _base.
  static List<Exercise> generateLibrary() {
    final List<Exercise> out = [];
    int counter = 1;

    for (final b in _base) {
      final baseName = b["name"] as String;
      out.add(
        Exercise(
          id: "LIB${counter++}",
          name: baseName,
          baseName: baseName,
          group: b["group"] as String,
          isHome: b["isHome"] as bool,
          level: (b["level"] as String?) ?? "—",
          equipment: List<String>.from(b["equipment"] as List),
          goals: List<String>.from(b["goals"] as List),
          description: b["description"] as String,
          benefits: b["benefits"] as String,
          youtube: b["youtube"] as String,
          muscles: List<String>.from(b["muscles"] as List),
        ),
      );
    }
    return out;
  }
}
