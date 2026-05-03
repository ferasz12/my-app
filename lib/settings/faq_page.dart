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
    // البدء والحساب
    _FaqItem(
      category: 'البدء والحساب',
      q: 'كيف أنشئ حسابًا أو أسجّل الدخول؟',
      a: 'من شاشة البداية اختر "إنشاء حساب" أو "تسجيل الدخول". يمكنك التسجيل بالبريد وكلمة المرور، أو عبر Apple / Google (إذا كانت مفعّلة على جهازك).',
    ),
    _FaqItem(
      category: 'البدء والحساب',
      q: 'نسيت كلمة المرور، ماذا أفعل؟',
      a: 'من شاشة تسجيل الدخول اضغط "نسيت كلمة المرور؟" ثم أدخل بريدك لاستلام رابط إعادة التعيين.',
    ),
    _FaqItem(
      category: 'البدء والحساب',
      q: 'كيف أغيّر بياناتي (الوزن/الطول/العمر/النشاط)؟',
      a: 'ادخل إلى "بياناتي" أو "الملف الشخصي" ثم عدّل القيم واحفظ. سيتم تحديث أهداف السعرات/الماكروز بحسب الإعدادات داخل التطبيق.',
    ),

    // الأهداف والسعرات
    _FaqItem(
      category: 'الأهداف والسعرات',
      q: 'كيف يحسب وازن السعرات والماكروز؟',
      a: 'وازن يحدد هدفك اليومي بناءً على بياناتك (العمر/الوزن/الطول/النشاط) وهدفك (تنشيف/زيادة/ثبات). النتائج إرشادية وليست بديلاً عن استشارة مختص.',
    ),
    _FaqItem(
      category: 'الأهداف والسعرات',
      q: 'كيف أغيّر هدفي (تنشيف/زيادة/ثبات)؟',
      a: 'اذهب إلى "بياناتي" أو "الهدف" وعدّل الهدف ثم احفظ. ستتحدث الأهداف اليومية تلقائيًا.',
    ),

    // تسجيل الطعام والتحليل
    _FaqItem(
      category: 'تسجيل الطعام والتحليل',
      q: 'كيف أسجّل وجبة؟',
      a: 'من التغذية اضغط زر (+) ثم اختر الطريقة المناسبة: تصوير الوجبة، تحليل نصّي (اكتب الوجبة)، مسح باركود، أو إدخال يدوي.',
    ),
    _FaqItem(
      category: 'تسجيل الطعام والتحليل',
      q: 'كيف يعمل تحليل الصورة؟',
      a: 'صوّر الوجبة بوضوح وفي إضاءة جيدة، ثم (إن وُجد) اكتب توضيح مثل: "الشاهي بدون سكر" أو "استخدمت حليب قليل الدسم". بعدها اضغط "تحليل".',
    ),
    _FaqItem(
      category: 'تسجيل الطعام والتحليل',
      q: 'لماذا أحيانًا يرجع التحليل 0 سعرات أو ماكروز؟',
      a: 'قد يحدث ذلك بسبب زاوية/إضاءة غير واضحة أو نقص تفاصيل الوجبة. جرّب: (1) إعادة التصوير بإضاءة أفضل، (2) إضافة توضيح قبل التحليل، (3) كتابة الوجبة نصيًا بدل الصورة، (4) إدخالها يدويًا إذا كانت وجبة خاصة/غير شائعة.',
    ),
    _FaqItem(
      category: 'تسجيل الطعام والتحليل',
      q: 'هل نتائج الذكاء الاصطناعي دقيقة 100%؟',
      a: 'نتائج التحليل تقديرية وقد تختلف حسب طريقة الطبخ والحجم والمكونات. الأفضل دائمًا التأكد من الكمية (الجرامات/الملعقة/الكوب) عند الحاجة للدقة العالية.',
    ),
    _FaqItem(
      category: 'تسجيل الطعام والتحليل',
      q: 'كيف أضيف الوجبة بعد التحليل؟',
      a: 'بعد ظهور النتائج اضغط زر "إضافة الوجبة" ليتم تسجيلها ضمن يومك، ويمكنك تعديل القيم قبل الحفظ إذا لزم.',
    ),

    // الباركود والمنتجات
    _FaqItem(
      category: 'الباركود والمنتجات',
      q: 'الباركود لا يجد منتجًا، ماذا أفعل؟',
      a: 'جرّب إعادة المسح مع إضاءة أقوى والتأكد من نظافة العدسة. إذا لم يوجد المنتج، استخدم الإدخال اليدوي أو إضافة منتج (إن كانت متاحة) ليتم مراجعته وإتاحته لاحقًا.',
    ),
    _FaqItem(
      category: 'الباركود والمنتجات',
      q: 'هل يمكنني تعديل قيم منتج باركود؟',
      a: 'إذا كان المنتج من قاعدة بيانات عامة فقد لا يمكن تعديله مباشرة. يمكنك إدخاله يدويًا كوجبة خاصة بك للحصول على قيمك الدقيقة.',
    ),

    // الماء والإشعارات
    _FaqItem(
      category: 'الماء والإشعارات',
      q: 'كيف أفعّل تذكيرات شرب الماء؟',
      a: 'افتح تبويب "الماء" ثم فعّل التذكيرات واختر النوع/عدد المرات. تأكد أيضًا من تفعيل إشعارات وازن من إعدادات الجهاز.',
    ),
    _FaqItem(
      category: 'الماء والإشعارات',
      q: 'لا تصلني الإشعارات أو تصل متأخرة، ما السبب؟',
      a: 'تحقق من: (1) تفعيل الإشعارات من النظام، (2) عدم تفعيل وضع التركيز/عدم الإزعاج، (3) السماح بالتنبيهات والظهور على شاشة القفل، (4) تحديث المنطقة الزمنية في الجهاز، (5) إيقاف توفير الطاقة إن كان يمنع الإشعارات.',
    ),

    // الوزن والتقارير
    _FaqItem(
      category: 'الوزن والتقارير',
      q: 'كيف أسجّل وزني وأتابع التغيير؟',
      a: 'اذهب إلى تبويب "الوزن" واضغط (+) لإضافة قراءة جديدة. ستظهر القراءات في الرسم البياني ويمكنك متابعة الاتجاهات بسهولة.',
    ),
    _FaqItem(
      category: 'الوزن والتقارير',
      q: 'كيف أطلع تقرير PDF؟',
      a: 'من تبويب التتبع/الوزن اضغط خيار "تقرير PDF" (إن وُجد) وسيتم توليد ملف يمكنك حفظه أو مشاركته.',
    ),
    _FaqItem(
      category: 'الوزن والتقارير',
      q: 'أضفت قراءة بالخطأ، كيف أحذفها؟',
      a: 'من سجل القراءات اضغط القراءة ثم اختر "حذف". إذا كانت المزامنة السحابية مفعلة فسيتم حذفها من جميع الأجهزة.',
    ),

    // الصيام
    _FaqItem(
      category: 'الصيام',
      q: 'كيف أبدأ صيامًا وأتابع المراحل؟',
      a: 'من تبويب "الصيام" اختر نوع الصيام ثم اضغط "ابدأ". سيعرض لك وازن الوقت المتبقي ومراحل الصيام بشكل مرئي.',
    ),
    _FaqItem(
      category: 'الصيام',
      q: 'كيف أوقف الصيام أو أعدّل نوعه؟',
      a: 'من نفس تبويب الصيام اضغط "إنهاء" أو غيّر نوع الصيام قبل البدء. يمكنك حفظ سجل صيامك للمتابعة.',
    ),

    // التمارين والجدولة
    _FaqItem(
      category: 'التمارين والجدولة',
      q: 'كيف أختار جدول تمارين؟',
      a: 'انتقل إلى "جدولي الرياضي" ثم اختر خطة جاهزة أو أنشئ جدولًا مناسبًا لهدفك. بعد الاختيار سيظهر جدولك مع الجلسات المقترحة.',
    ),
    _FaqItem(
      category: 'التمارين والجدولة',
      q: 'كيف أسجل جلسة تمرين؟',
      a: 'من جدولك اضغط "ابدأ" ثم "إنهاء" عند الانتهاء. ستُحفظ الجلسة ضمن سجل التمارين ويمكن مراجعتها لاحقًا.',
    ),

    // المدرب الذكي
    _FaqItem(
      category: 'المدرب الذكي',
      q: 'ما هو "مدرب وازن الذكي"؟',
      a: 'ميزة دردشة تعطيك نصائح مبنية على بياناتك وتقدمك داخل التطبيق (مثل الماء/الماكروز/الوزن). النصائح عامة وإرشادية وليست تشخيصًا طبيًا.',
    ),

    // الاشتراكات والمدفوعات
    _FaqItem(
      category: 'الاشتراكات والمدفوعات',
      q: 'هل التطبيق مجاني؟',
      a: 'يوفر وازن مزايا أساسية مجانًا، ومزايا متقدمة عبر اشتراك شهري/سنوي. ستظهر الأسعار بوضوح قبل الدفع ويمكن إدارة الاشتراك من المتجر.',
    ),
    _FaqItem(
      category: 'الاشتراكات والمدفوعات',
      q: 'كيف أستعيد مشترياتي (Restore Purchases)؟',
      a: 'من صفحة الاشتراك اضغط "استعادة المشتريات". تأكد أنك تستخدم نفس حساب Apple/Google الذي اشتركت به.',
    ),
    _FaqItem(
      category: 'الاشتراكات والمدفوعات',
      q: 'اشتركت لكن ما تفعلت المزايا',
      a: 'جرّب "استعادة المشتريات" وأعد فتح التطبيق. إذا استمرت المشكلة، أرسل لنا لقطة من صفحة الاشتراك وتاريخ العملية من المتجر.',
    ),
    _FaqItem(
      category: 'الاشتراكات والمدفوعات',
      q: 'كيف ألغي الاشتراك أو أطلب استرجاع مبلغ؟',
      a: 'إلغاء الاشتراك يتم من إعدادات متجر Apple/Google. طلب الاسترجاع يكون عبر المتجر أيضًا حسب سياساتهم.',
    ),

    // الخصوصية والبيانات
    _FaqItem(
      category: 'الخصوصية والبيانات',
      q: 'هل يتم حفظ صوري عند تحليل الوجبة؟',
      a: 'يعالج التطبيق الصورة بهدف التحليل وإرجاع النتائج. قد تُحفظ بعض البيانات اللازمة لتقديم الخدمة وتحسينها حسب سياسة الخصوصية. يمكنك دائمًا استخدام التحليل النصّي أو الإدخال اليدوي.',
    ),
    _FaqItem(
      category: 'الخصوصية والبيانات',
      q: 'كيف يتعامل وازن مع بياناتي؟',
      a: 'نحترم خصوصيتك ونستخدم بياناتك لتشغيل الميزات (حساب الأهداف، التقارير، المزامنة) وتحسين التجربة. راجع "سياسة الخصوصية" داخل التطبيق للتفاصيل.',
    ),
    _FaqItem(
      category: 'الخصوصية والبيانات',
      q: 'كيف أحذف حسابي وبياناتي؟',
      a: 'من "تواصل معنا" داخل التطبيق اطلب حذف الحساب. سنعالج الطلب وفق المتطلبات القانونية وقد نحتفظ بسجلات محدودة للامتثال.',
    ),

    // المزامنة والأجهزة
    _FaqItem(
      category: 'المزامنة والأجهزة',
      q: 'هل تتزامن بياناتي بين الأجهزة؟',
      a: 'إذا سجّلت الدخول بنفس الحساب وكانت المزامنة السحابية مفعلة، ستظهر بياناتك على أي جهاز تسجّل فيه.',
    ),

    // أعطال شائعة
    _FaqItem(
      category: 'أعطال شائعة',
      q: 'لا يعمل مسح الباركود',
      a: 'امنح إذن الكاميرا من إعدادات النظام، وتأكد من الإضاءة الجيدة. إذا استمرت المشكلة، استخدم الإدخال اليدوي مؤقتًا.',
    ),
    _FaqItem(
      category: 'أعطال شائعة',
      q: 'التطبيق يعلق أو يخرج فجأة',
      a: 'جرّب تحديث التطبيق، وإعادة تشغيل الجهاز، والتأكد من وجود مساحة كافية. إذا تكرر الأمر، راسلنا من "تواصل معنا" مع وصف المشكلة ووقت حدوثها.',
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
              'لم تجد إجابتك؟ تواصل معنا من شاشة "تواصل معنا" داخل التطبيق، أو عبر البريد: support@wazensapp.com',
              style: tx.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: 'support@wazensapp.com'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ البريد: support@wazensapp.com')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('نسخ البريد'),
              ),
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
