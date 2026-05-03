// ai_helper.dart - اقتراحات ذكية حسب نوع الرجيم والهدف والوقت

class AiHelper {
  static String getSuggestion({
    required String regimenName,
    required String goal,
    bool isFasting = false,
  }) {
    final now = DateTime.now();
    final hour = now.hour;
    final isMorning = hour >= 6 && hour <= 11;
    final isEvening = hour >= 18 && hour <= 23;

    if (regimenName.contains("صيام")) {
      if (isFasting) {
        return "🕐 أنت في وقت الصيام الآن. يمكنك شرب الماء، الشاي الأخضر أو القهوة السوداء دون سكر.";
      } else {
        return "🍽️ وقت الإفطار! جرّب تناول بروتين عالي وألياف للحفاظ على الشبع.";
      }
    }

    if (regimenName.contains("البروتين")) {
      return "💪 لأن هدفك ${goal == 'بناء العضلات' ? 'هو بناء عضلات' : 'يستفيد من البروتين'}, تناول صدور دجاج، عدس، أو بيض بعد التمرين مهم جدًا.";
    }

    if (regimenName.contains("الطاقة")) {
      return isMorning
          ? "🌅 صباح النشاط! ابدأ يومك بشوفان وموز مع زبدة الفول السوداني."
          : "🌙 مساءً؟ خذ وجبة خفيفة مثل زبادي بالفواكه لرفع الحيوية.";
    }

    if (regimenName.contains("الدهون")) {
      return "🧈 قلل الزيوت الثقيلة. استبدلها بزيت الزيتون أو الشوي بدل القلي.";
    }

    if (regimenName.contains("نباتي")) {
      return "🥦 تأكد أنك تحصل على بروتين من الحمص، الفول، أو الكينوا اليوم.";
    }

    if (regimenName.contains("السكر")) {
      return "🚫 حاول تتجنب العصائر الصناعية اليوم، وبدّلها بماء أو فواكه طازجة.";
    }

    return "✨ استمر، كل يوم جديد يقربك من هدفك!";
  }
}
