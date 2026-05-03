// lib/pages/terms_page.dart
import 'package:flutter/material.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final sections = <_SectionData>[
      _SectionData(
        title: 'التعريفات',
        items: const [
          '“التطبيق/نحن”: تطبيق وازن للياقة والتغذية.',
          '“المستخدم/أنت”: أي شخص ينشئ حسابًا أو يستخدم التطبيق.',
          '“الخدمة”: جميع المزايا داخل التطبيق مثل تتبّع التغذية والماء والوزن، جداول التمارين، المجتمع، ومساعد الذكاء الاصطناعي.',
        ],
      ),
      _SectionData(
        title: 'إنشاء الحساب والاستخدام',
        items: const [
          'يجب تقديم معلومات صحيحة ومحدّثة عند التسجيل، والحفاظ على سرّية بيانات الدخول.',
          'مسموح حساب شخصي واحد لكل مستخدم. يحق لنا إيقاف أو حذف أي حساب يُشتبه بإساءة استخدامه.',
          'أنت مسؤول عن أي نشاط يتم عبر حسابك.',
          'العمر الأدنى للاستخدام 16 عامًا، أو وفق الأنظمة المحلية إن كانت أعلى.',
        ],
      ),
      _SectionData(
        title: 'تنبيه صحي (ليست نصيحة طبية)',
        items: const [
          'نتائج وأرقام السعرات والماكروز والتوصيات هي تقديرية لأغراض التثقيف والمساعدة فقط.',
          'لا يعد التطبيق أداة تشخيصية أو جهازًا طبيًا. استشر طبيبك قبل البدء بأي برنامج غذائي/رياضي، خاصة إن كان لديك حالات صحية.',
          'في حالات الطوارئ الصحية اتصل بخدمات الطوارئ في بلدك فورًا.',
        ],
      ),
      _SectionData(
        title: 'الاشتراكات والدفع',
        items: const [
          'يوفّر التطبيق مزايا مدفوعة عبر اشتراك شهري أو سنوي. تُعرض الأسعار بوضوح قبل الدفع.',
          'يُجدَّد الاشتراك تلقائيًا ما لم يتم الإلغاء من متجر التطبيقات قبل موعد التجديد.',
          'عمليات الشراء داخل التطبيقات تُدار عبر متجر النظام (App Store/Google Play) أو مزوّد دفع معتمد؛ قد تُطبَّق شروطهم.',
          'سياسة الاسترداد: نتّبع سياسة المتجر الذي تم عبره الدفع. في حال خطأ تقني واضح (مثل خصم مكرر)، راسلنا وسنساعدك.',
        ],
      ),
      _SectionData(
        title: 'الخصوصية والبيانات',
        items: const [
          'نحترم خصوصيتك. تُخزَّن بياناتك محليًا على الجهاز وأيضًا على خدمات سحابية موثوقة عند تفعيل المزامنة.',
          'نستخدم البيانات لتحسين الخدمة وتقديم الميزات. لا نبيع بياناتك لطرف ثالث.',
          'قد نشارك بيانات لازمة تشغيليًا مع مزوّدي خدمة (استضافة/تحليلات) وفق اتفاقيات مُلزِمة.',
          'يمكنك طلب حذف حسابك وبياناتك عبر “تواصل معنا”. قد نحتفظ ببعض السجلات للالتزامات القانونية.',
        ],
      ),
      _SectionData(
        title: 'الأذونات',
        items: const [
          'الكاميرا/الصور: لمسح الباركود وتصوير الوجبات وصورة الملف الشخصي.',
          'الموقع: لإظهار صالات رياضية قريبة (اختياري).',
          'الإشعارات: للتذكير بالماء والوجبات والتمارين (اختياري).',
          'يمكنك إدارة الأذونات من إعدادات النظام.',
        ],
      ),
      _SectionData(
        title: 'المحتوى الذي ينشئه المستخدم والمجتمع',
        items: const [
          'تحترم المجتمع: يُمنع المحتوى المسيء أو المخالف أو المنتهك للحقوق.',
          'يحق لنا إزالة أو إخفاء أي محتوى مخالف وإيقاف الحسابات المسيئة.',
          'يبقى المستخدم مسؤولًا قانونيًا عن المحتوى الذي ينشره.',
        ],
      ),
      _SectionData(
        title: 'المدرّبون/الاستشارات (إن توفّرت)',
        items: const [
          'قد يوفّر التطبيق سوقًا للتواصل مع مدرّبين. العلاقة تتم بينك وبين المدرّب.',
          'لا نضمن نتائج التدريب أو دقّة نصائح الأطراف الخارجية. راجع الشروط/الأسعار قبل الشراء.',
        ],
      ),
      _SectionData(
        title: 'مساعد الذكاء الاصطناعي',
        items: const [
          'المخرجات تقديرية وقد تخطئ أحيانًا، ولا تُعد بديلًا عن استشارة مختص.',
          'يجب مراجعة النتائج قبل الاعتماد عليها، وخاصة في القرارات الصحية والغذائية.',
        ],
      ),
      _SectionData(
        title: 'الملكية الفكرية',
        items: const [
          'جميع الشعارات والتصاميم والأكواد وبيانات الدليل الغذائي ملك للتطبيق أو مُرخّصة له.',
          'يُحظر النسخ أو إعادة الاستخدام أو التفكيك دون إذن مكتوب.',
        ],
      ),
      _SectionData(
        title: 'حدود المسؤولية',
        items: const [
          'يُقدَّم التطبيق “كما هو”. لا نتحمّل مسؤولية أضرار مباشرة أو غير مباشرة ناجمة عن استخدام الخدمة.',
          'أقصى مسؤولية لنا –حيث يسمح القانون– لن تتجاوز الرسوم التي دفعتها خلال آخر 3 أشهر قبل المطالبة.',
        ],
      ),
      _SectionData(
        title: 'التعديلات على الشروط',
        items: const [
          'قد نعدّل هذه الشروط من وقت لآخر. سنخطرك داخل التطبيق عند وجود تغييرات جوهرية.',
          'يُعتبر استمرارك في الاستخدام بعد التعديل قبولًا للشروط المحدّثة.',
        ],
      ),
      _SectionData(
        title: 'الدعم والتواصل',
        items: const [
          'للاستفسارات أو طلبات حذف البيانات، تواصل معنا من شاشة “تواصل معنا” داخل التطبيق.',
        ],
      ),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الشروط والأحكام')),
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

            return _TermsSection(
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

class _TermsSection extends StatelessWidget {
  final int number;
  final String title;
  final List<String> items;

  const _TermsSection({
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
          // رمز نقطة
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
