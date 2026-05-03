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
          'نلتزم في تطبيق وازن بحماية خصوصيتك وشفافية طريقة معالجة بياناتك.',
          'توضح هذه السياسة ما نجمعه وكيف نستخدمه وخياراتك للتحكّم.',
        ],
      ),
      _SectionData(
        title: 'البيانات التي نجمعها',
        items: const [
          'بيانات الحساب: الاسم، البريد الإلكتروني، صورة الملف الشخصي (إن وُجدت).',
          'بيانات اللياقة والتغذية: سجلات الماء، الوزن، الوجبات/الماكروز، الجداول، جلسات التمرين.',
          'بيانات فنية: نوع الجهاز وإصدار النظام ومعرّفات الإشعار (لدفع التنبيهات) وسجلات أعطال.',
          'محتوى المجتمع: المنشورات والتعليقات والرسائل الخاصة داخل التطبيق.',
          'الصور الاختيارية: مثل صور الوجبات أو الصورة الرمزية (تُرفع عند موافقتك).',
        ],
      ),
      _SectionData(
        title: 'كيفية استخدام البيانات',
        items: const [
          'تقديم الميزات الأساسية: تتبّع القياسات، التذكيرات، المجتمع، وتوليد تقارير التقدّم.',
          'تحسين التجربة: اقتراح خطط مناسبة لهدفك، وتخصيص المحتوى والإشعارات.',
          'الأمان ومنع إساءة الاستخدام: اكتشاف النشاط غير الاعتيادي وحماية الحسابات.',
          'الدعم الفني وحلّ الأعطال: تحليل الأعطال وتحسين الأداء.',
        ],
      ),
      _SectionData(
        title: 'أساس المعالجة القانوني',
        items: const [
          'تنفيذ العقد: تشغيل الحساب والميزات التي تطلبها.',
          'الموافقة: مثل تفعيل المزامنة السحابية أو الإشعارات أو مشاركة الموقع.',
          'المصلحة المشروعة: تحسين الأمان والأداء مع احترام حقوقك.',
        ],
      ),
      _SectionData(
        title: 'مكان التخزين وفترات الاحتفاظ',
        items: const [
          'محليًا على جهازك لبعض البيانات لتسريع الاستخدام بلا إنترنت.',
          'على خدمات سحابية موثوقة عند التفعيل (مثل قواعد بيانات/تخزين ملفات).',
          'نحتفظ بالبيانات ما دامت لازمة لتقديم الخدمة أو وفق متطلبات قانونية، ثم نحذفها أو نُجهّلها.',
        ],
      ),
      _SectionData(
        title: 'مشاركة البيانات',
        items: const [
          'لا نبيع بياناتك لطرف ثالث.',
          'قد نشارك معلومات محدودة مع مزوّدي خدمات (استضافة/تحليلات/إشعارات) بموجب اتفاقيات حماية البيانات.',
          'في حال الضرورة القانونية أو لحماية حقوقنا والمستخدمين قد نشارك معلومات وفق القانون.',
        ],
      ),
      _SectionData(
        title: 'الأذونات والميزات الاختيارية',
        items: const [
          'الكاميرا/المعرض: لمسح باركود الطعام أو إضافة صور (اختياري ويمكن سحبه من إعدادات النظام).',
          'الموقع: لاقتراح صالات رياضية قريبة (اختياري).',
          'الإشعارات: للتذكير بالماء والوجبات والتمارين (يمكن إيقافها في أي وقت).',
        ],
      ),
      _SectionData(
        title: 'تحليلات وذكاء اصطناعي',
        items: const [
          'قد نستخدم تحليلات استخدام عامة ومجهّلة لتحسين الأداء والميزات.',
          'مساعد الذكاء الاصطناعي يعتمد على مدخلاتك لتقديم تقديرات غير طبية.',
        ],
      ),
      _SectionData(
        title: 'حقوقك',
        items: const [
          'الوصول والتصحيح: يمكنك عرض وتعديل معظم بياناتك من داخل التطبيق.',
          'الحذف: اطلب حذف حسابك وبياناتك من شاشة “تواصل معنا”.',
          'سحب الموافقة: يمكنك إيقاف الأذونات (الموقع/الكاميرا/الإشعارات) من إعدادات النظام.',
        ],
      ),
      _SectionData(
        title: 'الأطفال',
        items: const [
          'الخدمة موجّهة لمستخدمين بعمر 16+ أو وفق الأنظمة المحلية إن كانت أعلى.',
          'في حال اكتشفنا حسابًا لا يستوفي العمر الأدنى، سنقوم بإزالته.',
        ],
      ),
      _SectionData(
        title: 'النقل الدولي للبيانات',
        items: const [
          'قد تتم معالجة البيانات على خوادم خارج بلدك. نحرص على تطبيق حماية مناسبة ومتوافقة مع القوانين ذات الصلة.',
        ],
      ),
      _SectionData(
        title: 'التحديثات على السياسة',
        items: const [
          'قد نُحدّث هذه السياسة من وقت لآخر. سنخطرك داخل التطبيق عند تغييرات جوهرية.',
          'استمرارك في الاستخدام بعد التحديث يعني قبولك للسياسة المحدّثة.',
        ],
      ),
      _SectionData(
        title: 'التواصل',
        items: const [
          'للاستفسارات أو طلبات الحقوق، راسلنا عبر شاشة “تواصل معنا” داخل التطبيق.',
        ],
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
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
                    'آخر تحديث: سبتمبر 2025',
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
