import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/session_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_review_service.dart';

// Firebase (للحذف الشامل وتسجيل الخروج الحقيقي)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

// صفحاتك الحالية
import 'package:my_app/screens/welcome_screen.dart';
import 'package:my_app/settings/edit_email_page.dart';
import 'package:my_app/settings/edit_password_page.dart';
import 'package:my_app/settings/terms_page.dart';
import 'package:my_app/settings/privacy_page.dart';
import 'package:my_app/settings/contact_page.dart';
import 'package:my_app/settings/theme_settings_page.dart';
import 'package:my_app/settings/font_size_page.dart';

// الصفحات الجديدة
import 'package:my_app/settings/profile_page.dart';
import 'package:my_app/settings/notifications_page.dart';
import 'package:my_app/settings/language_page.dart';
import 'package:my_app/settings/sessions_page.dart';
import 'package:my_app/settings/faq_page.dart';
import 'package:my_app/settings/changelog_page.dart';

// ✅ صفحة الاشتراك
import 'package:my_app/settings/subscription_page.dart';


class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  // ======= تحسينات شكلية عامة =======
  static BoxDecoration _cardDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant),
      boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 8))],
    );
  }

  static Widget _sectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان القسم
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  static Widget _tile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    Color? titleColor,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (iconColor ?? cs.primary).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Icon(icon, color: iconColor ?? cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: titleColor ?? cs.onSurface,
                        )),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ?? const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }

  // ======= تدفق تسجيل الخروج (مُحسن) =======
  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد تسجيل الخروج'),
        content: const Text('هل أنت متأكد أنك تريد تسجيل الخروج؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirm != true) return;

    // مؤقّت تحميل
    _showBlockingLoader(context, message: 'جارٍ تسجيل الخروج...');
    try {
      await SessionManager.fullSignOut(clearFirestoreCache: true, awaitFirestoreCache: false);
    } catch (_) {}

if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // اغلاق اللودر
      // ✅ ارجع لجذر التطبيق (AuthGate) بدل دفع WelcomeScreen كـ Route مستقل
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  // ======= تدفق حذف الحساب (مع تأكيد كتابة "حذف" + حذف شامل + تسجيل خروج تلقائي) =======
  Future<void> _deleteAccount(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44, height: 5,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Text('حذف الحساب نهائيًا',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  'سيتم حذف حسابك وكل بياناتك نهائيًا من التطبيق والسحابة ولا يمكن التراجع. للمتابعة اكتب: حذف',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Form(
                  key: formKey,
                  child: TextFormField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      labelText: 'اكتب: حذف',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v ?? '').trim() == 'حذف' ? null : 'الرجاء كتابة: حذف',
                    onFieldSubmitted: (_) {
                      if (formKey.currentState?.validate() ?? false) {
                        Navigator.of(ctx).pop(true);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                        ),
                        onPressed: () {
                          if (formKey.currentState?.validate() ?? false) {
                            Navigator.of(ctx).pop(true);
                          }
                        },
                        child: const Text('حذف نهائي'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (ok != true) return;

    _showBlockingLoader(context, message: 'جارٍ حذف الحساب...');
try {
  // ✅ حذف شامل من السيرفر (يمسح: المستخدم + كل بياناته + وصفاته + منشوراته + الشات)
  final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
  final callable = functions.httpsCallable('deleteMyAccount');
  await callable.call();

  // ✅ بعد نجاح الحذف: نظّف الجلسة محليًا بسرعة (بدون حجب)
  try {
    await SessionManager.fullSignOut(clearFirestoreCache: true, awaitFirestoreCache: false);
  } catch (_) {}

  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop(); // اغلاق اللودر
    // ✅ ارجع لجذر التطبيق (AuthGate)
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/', (route) => false);
  }
} on FirebaseFunctionsException catch (e) {
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();

    String msg;
    if (e.code == 'not-found') {
      msg = 'ميزة حذف الحساب غير مفعّلة حاليًا (Function not found). '
          'تأكد أنك نشرت الدالة deleteMyAccount على نفس الـ Region (europe-west1).';
    } else {
      msg = (e.message ?? '').trim().isNotEmpty
          ? e.message!.trim()
          : 'تعذر حذف الحساب. حاول مرة أخرى.';
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
} catch (e) {
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('حدث خطأ أثناء الحذف: $e')),
    );
  }
}

  }

  static void _showBlockingLoader(BuildContext context, {required String message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  // ==== Helpers للحذف الشامل ====
  static const List<String> _knownSubcollections = <String>['meta','logs','preferences','plans','meals','progress','weights','bookmarks','notifications','tokens','intakes','water','goals'];

  

/// حذف مستندات في مجموعات عليا تعتمد على حقل uid
Future<void> _deleteTopLevelByUid(String uid) async {
  final db = FirebaseFirestore.instance;
  final List<String> topCollections = [
    'intakes', 'meals', 'weights', 'water', 'goals', 'subscriptions', 'notifications', 'logs'
  ];
  for (final colName in topCollections) {
    try {
      final q = await db.collection(colName).where('uid', isEqualTo: uid).limit(500).get();
      if (q.docs.isEmpty) continue;
      final batch = db.batch();
      for (final d in q.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      bool more = q.docs.length == 500;
      while (more) {
        final q2 = await db.collection(colName).where('uid', isEqualTo: uid).limit(500).get();
        if (q2.docs.isEmpty) { more = false; break; }
        final b2 = db.batch();
        for (final d in q2.docs) { b2.delete(d.reference); }
        await b2.commit();
        more = q2.docs.length == 500;
      }
    } catch (_) {}
  }
}
Future<void> _deleteUserFirestore(String uid) async {
    final db = FirebaseFirestore.instance;
    final userDoc = db.doc('users/$uid');

    for (final sub in _knownSubcollections) {
      final col = userDoc.collection(sub);
      await _deleteCollectionRecursive(col, batchSize: 200);
    }

    await _deleteTopLevelByUid(uid);

    // مثال لمسار معروف: users/{uid}/meta/onboarding كوثيقة داخل meta
    final metaOnboarding = userDoc.collection('meta').doc('onboarding');
    try {
      final snap = await metaOnboarding.get();
      if (snap.exists) await metaOnboarding.delete();
    } catch (_) {}

    await userDoc.delete();
  }

  Future<void> _deleteCollectionRecursive(
    CollectionReference<Map<String, dynamic>> col, {
    int batchSize = 200,
  }) async {
    Query<Map<String, dynamic>> query = col.limit(batchSize);
    while (true) {
      final snap = await query.get();
      if (snap.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < batchSize) break;
    }
  }

  Future<void> _deleteUserStorage(String uid) async {
    final storage = FirebaseStorage.instance;
    final rootRef = storage.ref('users/$uid');

    Future<void> deleteFolder(Reference ref) async {
      final list = await ref.listAll();
      for (final item in list.items) {
        try { await item.delete(); } catch (_) {}
      }
      for (final dir in list.prefixes) {
        await deleteFolder(dir);
      }
    }

    try {
      await deleteFolder(rootRef);
    } catch (_) {}
  }

  Future<void> _wipeLocalPrefs({String? uid, String? email}) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();

    for (final k in keys) {
      final lower = k.toLowerCase();
      final hasUid = uid != null && lower.contains(uid.toLowerCase());
      final hasEmail = email != null && lower.contains(email.toLowerCase());
      final looksLifestyle = lower.contains('lifestyle') ||
          lower.contains('onboarding') ||
          lower.contains('username') ||
          lower.contains('displayname') ||
          lower.contains('currentemail') ||
          lower.contains('userdataentered') ||
          lower.contains('activityfactor') ||
          lower.contains('activitylevel') ||
          lower.contains('isloggedin');

      if (hasUid || hasEmail || looksLifestyle) {
        await prefs.remove(k);
      }
    }
  }

  // ======= إجراءات أخرى =======
  Future<void> _rateApp() async {
    await AppReviewService.openReviewPage();
  }

  Future<void> _shareApp() async {
    await AppReviewService.shareApp();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ======= واجهة الشاشة (نفس الخيارات + تصميم أفخم) =======
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: const Text('إعداداتي')),
        body: ListView(
          children: [
            // -------- الملف الشخصي --------
            _sectionCard(
              context: context,
              title: 'الملف الشخصي',
              children: [
                _tile(
                  context: context,
                  icon: Icons.person,
                  title: 'تحرير الملف الشخصي',
                  subtitle: 'الاسم واليوزر والصورة والبايو والسوشيال',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  ),
                ),
                _tile(
                  context: context,
                  icon: Icons.alternate_email,
                  title: 'البريد الإلكتروني',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditEmailPage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.lock,
                  title: 'كلمة المرور',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditPasswordPage())),
                ),
              ],
            ),

            // -------- التخصيص والإشعارات --------
            _sectionCard(
              context: context,
              title: 'التخصيص والإشعارات',
              children: [
                _tile(
                  context: context,
                  icon: Icons.notifications_active,
                  title: 'الإشعارات',
                  subtitle: 'تمارين/دايت/وزن',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.language,
                  title: 'اللغة',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguagePage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.color_lens,
                  title: 'تغيير المظهر',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeSettingsPage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.text_fields,
                  title: 'حجم الخط',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FontSizePage())),
                ),
              ],
            ),

            // -------- الأمان والحساب --------
            _sectionCard(
              context: context,
              title: 'الأمان والحساب',
              children: [
                _tile(
                  context: context,
                  icon: Icons.devices_other,
                  title: 'الأجهزة والجلسات النشطة',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionsPage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.qr_code_2,
                  title: 'اشتراكي',
                  subtitle: 'إدارة الاشتراك ومسح الباركود',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionPage())),
                ),
              ],
            ),

            // -------- الدعم والسياسات --------
            _sectionCard(
              context: context,
              title: 'الدعم والسياسات',
              children: [
                _tile(
                  context: context,
                  icon: Icons.rule,
                  title: 'الشروط والأحكام',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsPage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.privacy_tip,
                  title: 'سياسة الخصوصية',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.contact_mail,
                  title: 'تواصل معنا',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactPage())),
                ),
              ],
            ),

            // -------- حول التطبيق --------
            _sectionCard(
              context: context,
              title: 'حول التطبيق',
              children: [
                _tile(
                  context: context,
                  icon: Icons.star_rate,
                  title: 'قيّم التطبيق',
                  onTap: _rateApp,
                ),
                _tile(
                  context: context,
                  icon: Icons.share,
                  title: 'مشاركة التطبيق',
                  onTap: _shareApp,
                ),
                _tile(
                  context: context,
                  icon: Icons.update,
                  title: 'ما الجديد',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangelogPage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.help_center,
                  title: 'الأسئلة الشائعة',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FaqPage())),
                ),
                _tile(
                  context: context,
                  icon: Icons.alternate_email_outlined,
                  title: 'تابعنا على الشبكات الاجتماعية',
                  subtitle: 'tiktok / X / instagram',
                  onTap: () => _openUrl('https://wazenfapp.web.app/'),

                ),
              ],
            ),

            // -------- إجراءات الحساب --------
            _sectionCard(
              context: context,
              title: 'إجراءات الحساب',
              children: [
                _tile(
                  context: context,
                  icon: Icons.logout,
                  title: 'تسجيل الخروج',
                  titleColor: Colors.red,
                  iconColor: Colors.red,
                  onTap: () => _logout(context),
                ),
                _tile(
                  context: context,
                  icon: Icons.delete_forever,
                  title: 'حذف الحساب',
                  subtitle: 'سيتم حذف كل بياناتك وسيتم تسجيل خروجك تلقائيًا',
                  titleColor: Colors.red,
                  iconColor: Colors.red,
                  onTap: () => _deleteAccount(context),
                ),
              ],
            ),

            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

