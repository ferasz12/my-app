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
        title: 'مقدمة ونطاق الاتفاقية',
        items: const [
          'آخر تحديث: 5 فبراير 2026.',
          'مرحبًا بك في تطبيق وازن. باستخدامك للتطبيق أو إنشاء حساب، فإنك توافق على هذه الشروط والأحكام بالإضافة إلى سياسة الخصوصية.',
          'إذا لم توافق على أي بند، يُرجى التوقف عن استخدام التطبيق وحذف حسابك/إزالة التطبيق.',
          'قد نوفّر ميزات مجانية وأخرى مدفوعة. قد تختلف المزايا حسب البلد/المنصة/نسخة التطبيق.',
        ],
      ),
      _SectionData(
        title: 'التعريفات',
        items: const [
          '“التطبيق/نحن”: تطبيق وازن وخدماته المرتبطة (الموقع/لوحة الإدارة إن وُجدت).',
          '“المستخدم/أنت”: أي شخص ينشئ حسابًا أو يستخدم التطبيق.',
          '“الخدمة”: جميع المزايا داخل التطبيق مثل تتبّع التغذية والماء والوزن، الصيام، التمارين، الوصفات، المجتمع، الإشعارات، وتقارير التقدّم.',
          '“الاشتراك”: المزايا المدفوعة التي يتم شراؤها عبر متجر التطبيقات (App Store) أو مزوّد معتمد.',
          '“المحتوى”: أي نص/صورة/منشور/تعليق/رسالة/ملف ترفعه أو تنشئه داخل التطبيق.',
          '“الذكاء الاصطناعي”: مزايا التحليل/المساعدة التي تعالج مدخلاتك (نصًا أو صورًا) عبر خوادمنا و/أو مزوّدي نماذج.',
        ],
      ),
      _SectionData(
        title: 'إنشاء الحساب والاستخدام',
        items: const [
          'يجب تقديم معلومات صحيحة ومحدّثة عند التسجيل، والحفاظ على سرّية بيانات الدخول.',
          'أنت مسؤول عن أي نشاط يتم عبر حسابك، بما في ذلك المحتوى الذي تنشره والإعدادات التي تفعّلها.',
          'لا يجوز استخدام التطبيق لأي غرض غير قانوني، أو لمحاولة الوصول غير المصرّح به إلى الأنظمة، أو إساءة استخدام المجتمع.',
          'العمر الأدنى للاستخدام 16 عامًا، أو وفق الأنظمة المحلية إن كانت أعلى.',
        ],
      ),
      _SectionData(
        title: 'تنبيه صحي مهم (ليست نصيحة طبية)',
        items: const [
          'النتائج وأرقام السعرات والماكروز والتوصيات داخل التطبيق تقديرية لأغراض التثقيف والمساعدة فقط.',
          'لا يُعد التطبيق أداة تشخيصية أو جهازًا طبيًا، ولا يغني عن استشارة مختصين (طبيب/أخصائي تغذية/مدرب معتمد).',
          'استشر طبيبك قبل بدء أي نظام غذائي أو رياضي، خصوصًا عند وجود حالات صحية أو حمل أو أدوية.',
          'في حالات الطوارئ الصحية اتصل بخدمات الطوارئ في بلدك فورًا.',
        ],
      ),
      _SectionData(
        title: 'الاشتراكات والدفع',
        items: const [
          'يوفّر التطبيق مزايا مدفوعة عبر اشتراك شهري/سنوي. تُعرض الأسعار والمدة قبل إتمام الشراء.',
          'التجديد تلقائي ما لم يتم الإلغاء من إعدادات متجر التطبيقات قبل موعد التجديد.',
          'قد تتوفر فترة تجريبية مجانية. عند انتهاء التجربة يتحول الاشتراك للتجديد التلقائي ما لم تُلغِه.',
          'إدارة الاشتراك (إلغاء/تغيير خطة/الفوترة) تتم عبر متجر App Store أو  حسب جهازك.',
          'الاسترداد والمرتجعات تخضع لسياسة المتجر الذي تم عبره الدفع. في حال وجود خطأ تقني واضح يمكنك التواصل معنا لدعمك.',
          'قد تتغير الأسعار أو المزايا؛ سيتم إشعارك بما يقتضيه النظام/المتجر قبل سريان أي تغيير جوهري.',
        ],
      ),
      _SectionData(
        title: 'الخصوصية والبيانات',
        items: const [
          'توضّح سياسة الخصوصية أنواع البيانات التي نجمعها وكيف نستخدمها ونشاركها وحقوقك.',
          'باستخدامك للتطبيق، فأنت تقرّ بقراءتك لسياسة الخصوصية والموافقة عليها.',
          'لا نبيع بياناتك الشخصية.',
        ],
      ),
      _SectionData(
        title: 'الأذونات والميزات الاختيارية',
        items: const [
          'قد يطلب التطبيق أذونات مثل: الإشعارات، الكاميرا، الصور، والصحة (Apple Health/Google Fit) لتفعيل ميزات معينة.',
          'يمكنك رفض الأذونات، لكن قد لا تعمل بعض الميزات (مثل مسح الباركود أو تذكيرات الماء/التمارين أو مزامنة الصحة).',
          'يمكنك تعديل الأذونات في أي وقت من إعدادات الجهاز.',
        ],
      ),
      _SectionData(
        title: 'المحتوى الذي ينشئه المستخدم والمجتمع',
        items: const [
          'أنت مسؤول عن محتواك. يُحظر نشر أي محتوى مسيء أو عنصري أو تحريضي أو ينتهك الخصوصية أو الملكية الفكرية أو يخالف الأنظمة.',
          'نحتفظ بحق إزالة المحتوى أو تقييد الحساب عند الاشتباه بمخالفة الشروط أو لحماية المستخدمين.',
          'بمجرّد نشر المحتوى، تمنحنا ترخيصًا محدودًا وغير حصري لعرضه داخل التطبيق وتشغيله لأغراض تقديم الخدمة (مثل عرض منشورات المجتمع).',
        ],
      ),
      _SectionData(
        title: 'المدرّبون/الاستشارات (إن توفّرت)',
        items: const [
          'قد يوفّر التطبيق محتوى تدريبي/إرشادي أو خططًا. هذا المحتوى معلوماتي ولا يشكّل علاقة علاجية أو ضمان نتائج.',
          'أي التزام بينك وبين طرف ثالث (مثل مدرب) يكون على مسؤوليتكما وفق شروطكما الخاصة، إن وُجد.',
        ],
      ),
      _SectionData(
        title: 'مساعد الذكاء الاصطناعي وتحليل الطعام',
        items: const [
          'قد تستخدم ميزات الذكاء الاصطناعي نصوصًا أو صورًا ترسلها (مثل صور الوجبات) لإرجاع تقديرات للمكوّنات والقرامات والماكروز.',
          'قد تتم معالجة المدخلات عبر خوادمنا و/أو مزوّدي نماذج (مثل مزوّدي ذكاء اصطناعي) لتقديم النتيجة.',
          'قد تكون النتائج غير دقيقة أو غير مناسبة لحالتك. أنت مسؤول عن التحقق قبل الاعتماد عليها، خصوصًا للحساسيات/الحمية/الأدوية.',
          'نحتفظ بحق تحسين نماذج التحليل وجودة الخدمة وفق سياسة الخصوصية.',
        ],
      ),
      _SectionData(
        title: 'الملكية الفكرية',
        items: const [
          'جميع حقوق الملكية في التطبيق، العلامة، التصميم، الواجهات، والنصوص البرمجية مملوكة لنا أو مرخّصة لنا.',
          'لا يجوز نسخ أو إعادة توزيع أو تعديل أو هندسة عكسية للتطبيق أو أي جزء منه إلا بما يسمح به النظام.',
        ],
      ),
      _SectionData(
        title: 'حدود المسؤولية',
        items: const [
          'نقدّم الخدمة “كما هي” و“حسب التوفر”. قد تتعطل بعض الميزات مؤقتًا لأسباب تقنية أو صيانة.',
          'إلى الحد الذي يسمح به النظام، لا نتحمل مسؤولية أي أضرار غير مباشرة أو تبعية ناتجة عن استخدامك للتطبيق أو اعتمادك على معلوماته.',
          'لا نضمن تحقيق نتائج صحية/رياضية محددة؛ النتائج تختلف حسب المستخدم والالتزام والظروف.',
        ],
      ),
      _SectionData(
        title: 'إنهاء الخدمة وإغلاق الحساب',
        items: const [
          'يمكنك التوقف عن استخدام التطبيق في أي وقت. قد تحتاج لإلغاء الاشتراك من المتجر لإيقاف التجديد.',
          'قد نعلّق أو نغلق حسابك عند مخالفة الشروط أو وجود مخاطر أمنية أو إساءة استخدام.',
          'يمكنك طلب حذف الحساب والبيانات عبر التواصل معنا (انظر قسم التواصل).',
        ],
      ),
      _SectionData(
        title: 'التعديلات على الشروط',
        items: const [
          'قد نحدّث هذه الشروط من وقت لآخر. سنعرض النسخة المحدّثة داخل التطبيق.',
          'استمرارك في استخدام التطبيق بعد التحديث يعني موافقتك على الشروط المحدثة.',
        ],
      ),
      _SectionData(
        title: 'القانون المنطبق وتسوية النزاعات',
        items: const [
          'تخضع هذه الشروط للأنظمة المعمول بها في المملكة العربية السعودية ما لم يُلزم نظام آخر بخلاف ذلك.',
          'في حال وجود نزاع، نسعى أولًا لحلّه وديًا عبر التواصل. إذا تعذر، يكون الاختصاص للجهات القضائية المختصة.',
        ],
      ),
      _SectionData(
        title: 'الدعم والتواصل',
        items: const [
          'للاستفسارات أو الدعم أو طلب حذف الحساب/البيانات: support@wazensapp.com',
          'قد نطلب معلومات للتحقق من هويتك قبل تنفيذ طلبات تتعلق بالبيانات.',
        ],
      ),
    ];

    return Directionality(
      textDirection: TextDirection.ltr,
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
                    'آخر تحديث: 5 فبراير 2026.',
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
