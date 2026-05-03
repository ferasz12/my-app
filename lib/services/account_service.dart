// lib/services/account_service.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AccountService {
  static final _auth = FirebaseAuth.instance;
  static final _functions = FirebaseFunctions.instance;

  /// إعادة توثيق إن طلب الخادم "requires-recent-login"
  static Future<void> _reauthenticateIfNeeded(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // لو مسجّل بجوجل/آبل: الأفضل تعيد جلب الـ credential (مثال تقريبي)
    // هنا نكتفي بمحاولة تحديث الـ token
    try {
      await user.getIdToken(true);
    } catch (_) {
      // تجاهل
    }

    // لو بريد/كلمة مرور — اطلب كلمة المرور
    if (user.providerData.any((p) => p.providerId == 'password')) {
      final pass = await _askPassword(context);
      if (pass == null) return;
      final cred = EmailAuthProvider.credential(email: user.email!, password: pass);
      await user.reauthenticateWithCredential(cred);
    }
  }

  static Future<String?> _askPassword(BuildContext context) async {
    final c = TextEditingController();
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الهوية'),
        content: TextField(
          controller: c,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'كلمة المرور'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('تأكيد')),
        ],
      ),
    );
  }

  static Future<bool> deleteMyAccount(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // تأكيد نهائي من المستخدم
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: const Text('سيتم حذف الحساب وجميع بياناتك نهائيًا. لا يمكن التراجع. هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(_, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return false;

    // قد يتطلب إعادة توثيق
    try {
      await _reauthenticateIfNeeded(context);
    } catch (_) {
      // تجاهل—الـ Cloud Function سترفض إن ما كان عنده صلاحية
    }

    // اتصال بالدالة السحابية
    final callable = _functions.httpsCallable('deleteAccount');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await callable.call(<String, dynamic>{});
      // نجاح: اطلع من التطبيق
      await _auth.signOut();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // close progress
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحذف: ${e.message ?? e.code}')),
      );
      return false;
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ غير متوقع أثناء الحذف')),
      );
      return false;
    }
  }
}
