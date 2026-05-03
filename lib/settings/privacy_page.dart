// lib/pages/privacy_page.dart
import 'package:flutter/material.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final sections = <_SectionData>[

      _SectionData(
        title: 'مقدّمة',
        items: const [
          'آخر تحديث: 5 فبراير 2026.',
          'نلتزم في تطبيق وازن بحماية خصوصيتك وشفافية طريقة معالجة بياناتك.',
          'توضح هذه السياسة ما نجمعه من بيانات، وكيف نستخدمه، ومع من نشاركه، وخياراتك للتحكّم.',
          'هذه السياسة جزء من شروط وأحكام الاستخدام.',
        ],
      ),
      _SectionData(
        title: 'البيانات التي نجمعها',
        items: const [
          'بيانات الحساب: الاسم، البريد الإلكتروني، رقم الهاتف (إن وُجد)، صورة الملف الشخصي (اختياري)، ومعرّفات تسجيل الدخول (Apple/Google).',
          'بيانات الصحة واللياقة التي تدخلها: الوزن، الماء، الوجبات، الماكروز، الأهداف، الصيام، الجداول، جلسات التمرين، والتقدّم.',
          'بيانات من مزامنة الصحة (اختياري): عند ربط Apple Health أو Google Fit قد نقرأ بيانات مثل الخطوات/النشاط/الوزن بحسب إذنك.',
          'الصور والوسائط (اختياري): صور الوجبات للتحليل، وصور الملف الشخصي، وأي وسائط تشاركها بالمجتمع.',
          'محتوى المجتمع: منشورات، تعليقات، رسائل، وإبلاغات عن محتوى.',
          'بيانات الاشتراك والمعاملات: حالة الاشتراك، معرّف المعاملة/المنتج، وتواريخ التجديد (لا نصل عادةً لبيانات بطاقتك؛ تتم عبر المتجر).',
          'بيانات فنية وتشغيلية: نوع الجهاز، إصدار النظام، اللغة، معرّفات الإشعارات، عنوان IP بصورة عامة، سجلات الأعطال، وبيانات الأداء.',
        ],
      ),
      _SectionData(
        title: 'كيف نستخدم بياناتك',
        items: const [
          'تقديم الخدمة الأساسية: إنشاء الحساب، حفظ السجلات، عرض التقارير، وتفعيل التذكيرات.',
          'تحليل الطعام بالذكاء الاصطناعي: معالجة الصور/النصوص لإرجاع تقديرات المكوّنات والماكروز.',
          'الاشتراكات: التحقق من حالة الاشتراك وتمكين المزايا المدفوعة ومنع الاحتيال.',
          'تحسين التجربة: تخصيص المحتوى، تحسين الأداء، إصلاح الأخطاء، وتطوير الميزات.',
          'الأمان ومنع إساءة الاستخدام: اكتشاف النشاط غير الطبيعي وحماية الحسابات والمجتمع.',
          'الدعم الفني: الرد على الاستفسارات ومعالجة الطلبات.',
        ],
      ),
      _SectionData(
        title: 'أساس المعالجة',
        items: const [
          'تنفيذ العقد: لتشغيل الحساب والميزات التي تطلبها.',
          'الموافقة: للميزات الاختيارية مثل الإشعارات، الكاميرا/الصور، ومزامنة الصحة.',
          'المصلحة المشروعة: لتحسين الأمان والجودة ومنع الاحتيال مع احترام حقوقك.',
          'الالتزام القانوني: عند طلب جهة مختصة وفق الأنظمة.',
        ],
      ),
      _SectionData(
        title: 'مكان التخزين وفترات الاحتفاظ',
        items: const [
          'قد تُخزّن البيانات محليًا على جهازك، وقد تُخزّن سحابيًا عند تفعيل المزامنة/الحساب.',
          'نحتفظ ببياناتك طالما كان حسابك نشطًا أو حسب الحاجة لتقديم الخدمة والالتزامات القانونية.',
          'يمكنك طلب حذف الحساب والبيانات. قد نحتفظ بنسخ احتياطية لفترة محدودة لأغراض الأمان والاستعادة ثم تُحذف تلقائيًا.',
        ],
      ),
      _SectionData(
        title: 'مشاركة البيانات',
        items: const [
          'لا نبيع بياناتك الشخصية.',
          'قد نشارك بيانات محدودة مع مزوّدي خدمات موثوقين لمعالجة البيانات بالنيابة عنا (مثل الاستضافة، التحليلات، الأعطال).',
          'مزودو خدمات شائعون داخل التطبيق: Firebase/Google (مصادقة، قاعدة بيانات، وظائف سحابية، تخزين، تحليلات، Crashlytics)، ومزوّدو إشعارات محلية على الجهاز.',
          'مصادر غذائية/باركود: قد نستعلم من قواعد بيانات عامة مثل OpenFoodFacts أو مصادر تغذية رسمية (مثل USDA/FoodData Central) لإكمال المعلومات.',
          'مزودو الذكاء الاصطناعي: قد تتم معالجة محتوى التحليل (نص/صورة) عبر مزوّد نماذج (مثل Google Gemini أو OpenAI أو بدائل مماثلة) لتقديم النتيجة.',
          'المدفوعات والاشتراكات: تتم عبر App Store/ وقد نتلقى فقط بيانات حالة الاشتراك/التحقق.',
          'قد نكشف بيانات إذا طُلب منا نظاميًا من جهة مختصة أو لحماية حقوقنا/المستخدمين.',
        ],
      ),
      _SectionData(
        title: 'الأذونات والميزات الاختيارية',
        items: const [
          'الإشعارات: لإرسال تذكيرات الماء/التمارين/الصيام والتنبيهات التي تفعّلها.',
          'الكاميرا/الصور: لمسح الباركود وتحليل صور الوجبات وتحديث صورة الملف الشخصي.',
          'الصحة (Apple Health/Google Fit): لقراءة/مزامنة بيانات النشاط والوزن وغيرها حسب إذنك.',
          'يمكنك سحب الموافقة أو تغيير الأذونات من إعدادات جهازك في أي وقت.',
        ],
      ),
      _SectionData(
        title: 'تحليلات وذكاء اصطناعي',
        items: const [
          'نستخدم أدوات تحليل وأعطال لتحسين الاستقرار (مثل Analytics وCrashlytics) وقد تجمع بيانات فنية غير مباشرة.',
          'عند استخدام ميزات الذكاء الاصطناعي، قد نرسل المدخلات اللازمة فقط لإتمام التحليل. لا تستخدم هذه الميزة لمشاركة معلومات حساسة جدًا.',
          'بيانات Apple Health/HealthKit لا نستخدمها للإعلانات ولا نبيعها، ولا نشاركها لأغراض تسويقية.',
        ],
      ),
      _SectionData(
        title: 'حقوقك وخياراتك',
        items: const [
          'الوصول والتصحيح: يمكنك تعديل بعض بياناتك داخل التطبيق.',
          'سحب الموافقة: يمكنك إيقاف الأذونات (إشعارات/صحة/كاميرا) من إعدادات الجهاز.',
          'الحذف: يمكنك طلب حذف الحساب والبيانات عبر التواصل معنا.',
          'الاعتراض/التقييد: يمكنك الاعتراض على بعض أنواع المعالجة وفق الأنظمة المعمول بها.',
        ],
      ),
      _SectionData(
        title: 'الأطفال',
        items: const [
          'التطبيق غير موجّه للأطفال دون 16 عامًا.',
          'إذا تبيّن لنا جمع بيانات طفل دون السن المسموح، سنحذفها عند التأكد.',
        ],
      ),
      _SectionData(
        title: 'النقل الدولي للبيانات',
        items: const [
          'قد تتم معالجة بياناتك أو تخزينها على خوادم تقع خارج بلدك بحسب مزوّدي الخدمات (مثل Google Cloud).',
          'نتخذ تدابير تعاقدية وتقنية لحماية البيانات عند النقل الدولي وفق الأنظمة.',
        ],
      ),
      _SectionData(
        title: 'التحديثات على السياسة',
        items: const [
          'قد نحدّث هذه السياسة من وقت لآخر. سنعرض النسخة المحدّثة داخل التطبيق.',
          'استمرارك في استخدام التطبيق بعد التحديث يعني اطلاعك وموافقتك على السياسة المحدثة.',
        ],
      ),
      _SectionData(
        title: 'التواصل',
        items: const [
          'للاستفسارات أو طلبات الخصوصية/الحذف: support@wazensapp.com',
          'قد نطلب معلومات للتحقق من هويتك قبل تنفيذ الطلب.',
        ],
      ),
    ];

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: const Text('سياسة الخصوصية')),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: sections.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == sections.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    'آخر تحديث: 5 فبراير 2026.',
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              );
            }

            final s = sections[index];
            final number = index + 1;

            return _PrivacySection(
              number: number,
              title: s.title,
              items: s.items,
            );
          },
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  final int number;
  final String title;
  final List<String> items;

  const _PrivacySection({
    required this.number,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عنوان مرقّم
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: cs.primary,
                  child: Text(
                    '$number',
                    style: text.labelLarge?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // عناصر القائمة (نِقاط)
            ...items.map((e) => _Bullet(text: e)).toList(),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // نقطة
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 8, left: 8),
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
          ),
          // النص
          Expanded(
            child: Text(
              text,
              style: tx.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionData {
  final String title;
  final List<String> items;
  const _SectionData({required this.title, required this.items});
}
