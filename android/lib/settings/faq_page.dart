// lib/pages/faq_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  final TextEditingController _search = TextEditingController();
  String _selectedCategory = 'الكل';

  late final List<_FaqItem> _allItems = <_FaqItem>[
    // الحساب
    _FaqItem(
      category: 'الحساب',
      q: 'كيف أنشئ حسابًا أو أسجّل الدخول؟',
      a: 'من شاشة البداية اختر "إنشاء حساب" وأدخل بريدك وكلمة المرور. إذا كان لديك حساب، اختر "تسجيل الدخول".',
    ),
    _FaqItem(
      category: 'الحساب',
      q: 'نسيت كلمة المرور، ماذا أفعل؟',
      a: 'اذهب إلى شاشة تسجيل الدخول واضغط "هل نسيت كلمة المرور؟" ثم أدخل بريدك لاستلام رابط إعادة التعيين.',
    ),

    // التغذية
    _FaqItem(
      category: 'التغذية',
      q: 'كيف أسجّل وجبة وأحسب السعرات؟',
      a: 'من تبويب التغذية اضغط زر (+)، ثم اختر من قاعدة البيانات أو امسح الباركود أو أضف الوجبة يدويًا. سيحسب التطبيق السعرات والماكروز تلقائيًا.',
    ),
    _FaqItem(
      category: 'التغذية',
      q: 'كيف أغيّر الخطة/النظام الغذائي؟',
      a: 'من تبويب "الدايت" اختر الخطة المناسبة لهدفك ثم احفظ. يمكنك تعديل الهدف من الإعدادات لتحديث الاقتراحات.',
    ),
    _FaqItem(
      category: 'التغذية',
      q: 'هل يمكنني استخدام مساعد الذكاء لتقدير وجبتي؟',
      a: 'نعم. التقط صورة لوجبتك أو اكتب مكوناتها في مساعد الذكاء، وسيقدّر السعرات والماكروز بشكل تقريبي (غير طبي).',

    ),

    // الماء
    _FaqItem(
      category: 'الماء',
      q: 'كيف أفعّل تذكيرات شرب الماء؟',
      a: 'افتح تبويب "الماء" ثم فعّل التذكيرات وحدّد عدد المرات. يمكنك تعديل الإشعارات من إعدادات النظام.',
    ),
    _FaqItem(
      category: 'الماء',
      q: 'هل تُحفظ قراءات الماء بين الأجهزة؟',
      a: 'إذا فعّلت المزامنة السحابية في الإعدادات، تُرفع القراءات لحسابك وتظهر على أي جهاز تسجّل فيه.',
    ),

    // الوزن
    _FaqItem(
      category: 'الوزن',
      q: 'كيف أسجّل وزني؟',
      a: 'اذهب إلى تبويب "الوزن" واضغط (+) لإضافة قراءة جديدة. ستُعرض في الرسم البياني ويمكن استخراج تقرير PDF من نفس التبويب.',
    ),
    _FaqItem(
      category: 'الوزن',
      q: 'أضفت وزنًا بالخطأ، كيف أحذفه؟',
      a: 'من سجل القراءات اضغط على القراءة المطلوية ثم اختر "حذف". إذا كانت متزامنة سحابيًا فسيتم حذفها من جميع الأجهزة.',

    ),

    // التمارين
    _FaqItem(
      category: 'التمارين',
      q: 'كيف أختار جدول تمارين؟',
      a: 'انتقل إلى "جدولي الرياضي"، اختر الجدول من القائمة أو استخدم الاقتراح الذكي حسب هدفك. عند اختيار جدول، ستُعرض صفحة الجدول مباشرة مع إمكانية الرجوع للقائمة من شريط العنوان.',
    ),
    _FaqItem(
      category: 'التمارين',
      q: 'جلسات التمرين لا تظهر في السجل بعد الحفظ',
      a: 'تأكّد من إنهاء العداد بالضغط على "إنهاء" بعد التمرين. يحفظ التطبيق الجلسة تحت حسابك المحلي. إذا فعّلت المزامنة، ستُرفع الجلسات للسحابة وتظهر على أجهزتك الأخرى.',
    ),
    _FaqItem(
      category: 'التمارين',
      q: 'كيف أستخدم عدّاد التمرين؟',
      a: 'من "جدولي الرياضي" اضغط "ابدأ العداد" عند بداية التمرين و"إنهاء" عند الانتهاء. ستظهر المدة في شاشة "جلسات التمرين".',
    ),

    // المجتمع
    _FaqItem(
      category: 'المجتمع',
      q: 'كيف أنشر في المجتمع أو أرسل رسالة خاصة؟',
      a: 'من تبويب "المجتمع" اضغط (+) لإنشاء منشور. لرسالة خاصة، افتح بروفايل المستخدم ثم اضغط "رسالة خاصة".',
    ),

    // الاشتراكات والدفع
    _FaqItem(
      category: 'المدفوعات والاشتراكات',
      q: 'هل التطبيق مجاني؟',
      a: 'التطبيق يوفّر مزايا أساسية مجانًا ومزايا إضافية عبر اشتراك شهري/سنوي. تُعرض الأسعار قبل الدفع ويمكن الإلغاء من المتجر.',
    ),
    _FaqItem(
      category: 'المدفوعات والاشتراكات',
      q: 'أواجه مشكلة في الدفع أو تم خصم متكرر',
      a: 'تحقّق من حالة الاشتراك في متجر التطبيقات. إذا استمرت المشكلة، راسلنا من "تواصل معنا" مع رقم العملية وسنساعدك.',

    ),

    // الخصوصية والبيانات
    _FaqItem(
      category: 'الخصوصية والبيانات',
      q: 'كيف يتعامل التطبيق مع بياناتي؟',
      a: 'نحترم خصوصيتك ونستخدم بياناتك لتقديم الميزات وتحسينها. اطلع على "سياسة الخصوصية" للتفاصيل وخياراتك.',
    ),
    _FaqItem(
      category: 'الخصوصية والبيانات',
      q: 'كيف أحذف حسابي وبياناتي؟',
      a: 'من "تواصل معنا" اطلب حذف الحساب. سنعالج الطلب وفق المتطلبات القانونية وقد نحتفظ بسجلات محدودة للامتثال.',
    ),

    // أعطال شائعة
    _FaqItem(
      category: 'أعطال شائعة',
      q: 'لا يعمل مسح الباركود',
      a: 'امنح إذن الكاميرا من إعدادات النظام، وتأكد من الإضاءة الجيدة. إذا استمرت المشكلة، جرّب إدخال الوجبة يدويًا.',
    ),
    _FaqItem(
      category: 'أعطال شائعة',
      q: 'لا تصلني الإشعارات',
      a: 'تأكد من تفعيل الإشعارات داخل التطبيق ومن إعدادات النظام. أعد فتح التطبيق لتجديد صلاحيات الإشعار.',
    ),
  ];

  List<String> get _categories {
    final set = <String>{'الكل'};
    set.addAll(_allItems.map((e) => e.category));
    return set.toList();
  }

  List<_FaqItem> get _filtered {
    final q = _search.text.trim();
    final cat = _selectedCategory;
    return _allItems.where((e) {
      final inCat = (cat == 'الكل') ? true : e.category == cat;
      if (!inCat) return false;
      if (q.isEmpty) return true;
      final text = '${e.q} ${e.a}'.toLowerCase();
      return text.contains(q.toLowerCase());
    }).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = Theme.of(context).textTheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الأسئلة الشائعة')),
        body: Column(
          children: [
            // شريط البحث
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'ابحث عن سؤال…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح',
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.clear),
                        ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),

            // فلاتر الفئات
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final selected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: _categories.length,
              ),
            ),

            const SizedBox(height: 4),

            // النتائج
            Expanded(
              child: _filtered.isEmpty
                  ? _EmptyState(
                      onClearSearch: _search.text.isEmpty
                          ? null
                          : () {
                              _search.clear();
                              setState(() {});
                            },
                    )
                  : ListView.separated(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      itemCount: _filtered.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        // ذيل: دعوة للتواصل
                        if (i == _filtered.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: _ContactCard(),
                          );
                        }

                        final item = _filtered[i];
                        return _FaqTile(item: item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _FaqItem item;
  const _FaqTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        // تقليل المسافات داخل ExpansionTile
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          childrenPadding:
              const EdgeInsets.only(right: 12, left: 12, bottom: 12),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: cs.primary,
            child: Icon(Icons.help_outline, size: 18, color: cs.onPrimary),
          ),
          title: Text(
            item.q,
            style: tx.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(item.category, style: tx.bodySmall),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.a,
                    style: tx.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'نسخ الإجابة',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: '${item.q}\n\n${item.a}'));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ الإجابة')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onClearSearch;
  const _EmptyState({this.onClearSearch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_search, size: 42, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'لم نجد نتائج مطابقة',
              style: tx.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'جرّب كلمات أبسط أو اختر فئة مختلفة.',
              style: tx.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (onClearSearch != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.clear),
                label: const Text('مسح البحث'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tx = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.support_agent, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'لم تجد إجابتك؟ تواصل معنا من شاشة "تواصل معنا" داخل التطبيق وسنساعدك.',
              style: tx.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () {
              // إذا عندك صفحة تواصل، وجّه المستخدم لها هنا.
              // Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactPage()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('اذهب إلى تبويب "تواصل معنا"')),
              );
            },
            child: const Text('تواصل'),
          ),
        ],
      ),
    );
  }
}

class _FaqItem {
  final String category;
  final String q;
  final String a;
  const _FaqItem({required this.category, required this.q, required this.a});
}
