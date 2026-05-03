// lib/settings/edit_username_page.dart
// صفحة مستقلة لتعديل اسم المستخدم (متوافقة مع قواعد اليوزر الجديدة + فحص التوفر)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/user_repository.dart';
import '../shared/friendly_errors.dart';

class EditUsernamePage extends StatefulWidget {
  const EditUsernamePage({super.key});

  @override
  State<EditUsernamePage> createState() => _EditUsernamePageState();
}

class _EditUsernamePageState extends State<EditUsernamePage> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  bool _saving = false;
  bool _checking = false;
  bool? _available; // null = not checked/invalid

  User? _user;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;

  @override
  void initState() {
    super.initState();

    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      _stream = FirebaseFirestore.instance.doc('users/${_user!.uid}').snapshots();
    }

    _ctrl.addListener(() {
      _debounce?.cancel();
      setState(() {
        _checking = true;
        _available = null;
      });
      _debounce = Timer(const Duration(milliseconds: 450), _checkAvailability);
    });

    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _checkAvailability();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _normalizeHandle(String raw) => raw.trim().toLowerCase();

  String? _usernameRuleError(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'أدخل اسم المستخدم';

    final lower = t.toLowerCase();
    if (lower.length < 5) return 'اليوزر لازم يكون ٥ أحرف أو أكثر';
    if (lower.length > 20) return 'اليوزر طويل جدًا';

    if (RegExp(r'\s').hasMatch(t)) return 'بدون مسافات';
    if (!RegExp(r'^[A-Za-z]').hasMatch(t)) return 'لازم يبدأ بحرف إنجليزي';
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(t)) return 'إنجليزي فقط (حروف/أرقام) بدون رموز';
return null;
  }

  Future<void> _checkAvailability() async {
    final user = _user ?? FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final raw = _ctrl.text.trim();
    final err = _usernameRuleError(raw);
    if (err != null) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _available = null;
      });
      return;
    }

    final handle = _normalizeHandle(raw);

    try {
      final doc = await FirebaseFirestore.instance.doc('usernames/$handle').get();
      final owner = doc.data()?['ownerUid']?.toString();
      final ok = !doc.exists || owner == user.uid;

      if (!mounted) return;
      setState(() {
        _checking = false;
        _available = ok;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _available = null;
      });
    }
  }

  Widget? _suffixIcon() {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return null;

    final err = _usernameRuleError(raw);
    if (err != null) {
      return const Icon(Icons.error_outline, color: Colors.redAccent);
    }

    if (_checking) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_available == true) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }

    if (_available == false) {
      return const Icon(Icons.cancel, color: Colors.redAccent);
    }

    return null;
  }

  String? _helperText() {
    final raw = _ctrl.text.trim();
    final err = _usernameRuleError(raw);
    if (err != null) return err;

    final k = _normalizeHandle(raw);
    final parts = <String>[];
    if (k != raw) parts.add('سيتم حفظه كـ: $k');
    if (_available == true) parts.add('متاح');
    if (_available == false) parts.add('مستخدم بالفعل');

    return parts.isEmpty ? null : parts.join(' • ');
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = _user ?? FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final raw = _ctrl.text.trim();
    final err = _usernameRuleError(raw);
    if (err != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(FriendlyErrors.message(err))));
      return;
    }

    // تأكد من التوفر
    await _checkAvailability();
    if (_available == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اسم المستخدم مستخدم بالفعل')),
        );
      }
      return;
    }

    final handle = _normalizeHandle(raw);

    setState(() => _saving = true);
    try {
      await const UserRepository().updateUsername(username: handle);

      final prefs = await SharedPreferences.getInstance();
      final emailKey = prefs.getString('currentEmail') ?? user.email ?? 'unknown_user';
      await prefs.setString('username_$emailKey', handle);
      await prefs.setString('currentUsername_$emailKey', handle);
      await prefs.setString('username_${user.uid}', handle);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث اسم المستخدم'), backgroundColor: Colors.green),
      );
      Navigator.maybePop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر التحديث: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_user == null) {
      return const Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(
          body: Center(child: Text('لا يوجد مستخدم مسجّل حالياً')),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تعديل اسم المستخدم'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ'),
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snap) {
            final username = (snap.data?.data()?['username'] ?? '').toString().trim();

            // Prefill once if empty
            if (_ctrl.text.isEmpty && username.isNotEmpty) {
              _ctrl.value = TextEditingValue(
                text: username,
                selection: TextSelection.collapsed(offset: username.length),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'اختر يوزر فريد للتطبيق',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الشروط: ٥ أحرف أو أكثر، إنجليزي فقط (حروف/أرقام/_)، بدون مسافات.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _ctrl,
                      focusNode: _focus,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixText: '@',
                        helperText: _helperText(),
                        suffixIcon: _suffixIcon(),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => _usernameRuleError(v ?? ''),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                    ),

                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_rounded),
                        label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const BackButtonIcon(),
                      label: const Text('رجوع'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}