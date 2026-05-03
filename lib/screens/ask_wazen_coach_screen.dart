// lib/screens/ask_wazen_coach_screen.dart
// شاشة "مدرب وازن الذكي" — دردشة + زر إرسال تقرير اليوم (مرة واحدة يوميًا).

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/premium_feature.dart';
import '../shared/premium_gate.dart';

import '../services/ask_wazen_coach_api.dart';
import '../services/ask_wazen_report.dart';

class AskWazenCoachScreen extends StatefulWidget {
  const AskWazenCoachScreen({super.key});

  @override
  State<AskWazenCoachScreen> createState() => _AskWazenCoachScreenState();
}

class _ChatMsg {
  final String role; // 'user' | 'assistant'
  final String text;
  final DateTime at;
  _ChatMsg({required this.role, required this.text, DateTime? at})
      : at = at ?? DateTime.now();
}

class _AskWazenCoachScreenState extends State<AskWazenCoachScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  final List<_ChatMsg> _msgs = [];

  bool _sending = false;
  bool _dailyLocked = false;
  String _todayYmd = DateTime.now().toIso8601String().split('T').first;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    final email =
        prefs.getString('currentEmail') ?? FirebaseAuth.instance.currentUser?.email ?? 'unknown_user';
    final ymd = DateTime.now().toIso8601String().split('T').first;
    final last = prefs.getString('ask_wazen_last_ymd_$email');

    if (!mounted) return;
    setState(() {
      _todayYmd = ymd;
      _dailyLocked = (last == ymd);

      _msgs.add(
        _ChatMsg(
          role: 'assistant',
          text:
              'أهلًا 👋\nأنا مدرب وازن الذكي.\n\n'
              'إذا تبي نصائح دقيقة حسب بياناتك (سعرات/ماكروز/ماء/نشاط/وزن/صيام) اضغط زر «إرسال تقرير اليوم».\n'
              'بعدها اسألني عن أول وجبة/خطة اليوم وأنا أرتّب لك الخيارات.',
        ),
      );
    });
  }

  void _snack(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  List<Map<String, String>> _historyForServer({int max = 12}) {
    final out = <Map<String, String>>[];
    for (final m in _msgs.reversed) {
      if (out.length >= max) break;
      if (m.role != 'user' && m.role != 'assistant') continue;
      out.insert(0, {'role': m.role, 'text': m.text});
    }
    return out;
  }

  Future<void> _sendDailyReport() async {
    if (_sending) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('سجّل الدخول أولًا لاستخدام مدرب وازن الذكي.');
      return;
    }

    if (_dailyLocked) {
      _snack('تم إرسال تقرير اليوم مسبقًا. تقدر ترسل مرة ثانية بكرة.');
      return;
    }

    _dismissKeyboard();

    setState(() {
      _sending = true;
      _msgs.add(_ChatMsg(role: 'user', text: 'أرسل تقريري اليومي الآن.'));
    });
    _scrollToBottom();

    try {
      final report = await AskWazenReportBuilder.build(days: 7);
      final reply = await AskWazenCoachApi.sendDailyReport(report: report);

      // قفل محلي (حتى لو فشل الربط مع جهاز ثاني، السيرفر يطبق القفل أيضًا)
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('currentEmail') ?? user.email ?? 'unknown_user';
      await prefs.setString('ask_wazen_last_ymd_$email', _todayYmd);

      if (!mounted) return;
      setState(() {
        _dailyLocked = true;
        _msgs.add(_ChatMsg(role: 'assistant', text: reply.isEmpty ? 'تم.' : reply));
      });
      _scrollToBottom();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = (e.message ?? '').trim();
      setState(() {
        if (e.code == 'resource-exhausted') _dailyLocked = true;
        _msgs.add(_ChatMsg(
          role: 'assistant',
          text: msg.isNotEmpty ? msg : 'تعذّر إرسال التقرير الآن. حاول لاحقًا.',
        ));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_ChatMsg(
          role: 'assistant',
          text: 'صار خطأ أثناء إرسال التقرير: $e',
        ));
      });
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendChat() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    _dismissKeyboard();

    setState(() {
      _sending = true;
      _msgs.add(_ChatMsg(role: 'user', text: text));
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final reply = await AskWazenCoachApi.chat(
        message: text,
        history: _historyForServer(max: 12),
      );
      if (!mounted) return;
      setState(() => _msgs.add(_ChatMsg(role: 'assistant', text: reply.isEmpty ? 'تمام.' : reply)));
      _scrollToBottom();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs.add(_ChatMsg(
          role: 'assistant',
          text: (e.message ?? '').trim().isNotEmpty
              ? (e.message ?? '').trim()
              : 'تعذّر إرسال الرسالة الآن (${e.code}).',
        ));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add(_ChatMsg(role: 'assistant', text: 'صار خطأ: $e')));
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _roleAvatar({required bool isMe}) {
    final theme = Theme.of(context);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMe ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black.withOpacity(0.08),
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        isMe ? Icons.person : Icons.auto_awesome_rounded,
        size: 18,
        color: isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _bubble(_ChatMsg m) {
    final isMe = m.role == 'user';
    final theme = Theme.of(context);

    final bubbleBg = isMe
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    final bubbleFg = isMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _roleAvatar(isMe: false),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: bubbleBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 6),
                  bottomRight: Radius.circular(isMe ? 6 : 18),
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 14,
                    color: Colors.black.withOpacity(0.06),
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SelectableText(
                    m.text,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: bubbleFg, height: 1.4, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fmtTime(m.at),
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: bubbleFg.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 10),
            _roleAvatar(isMe: true),
          ],
        ],
      ),
    );
  }

  Widget _dailyButton() {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dailyLocked
                  ? '✅ تم إرسال تقرير اليوم ($_todayYmd)'
                  : 'ارسل تقرير اليوم (مرة واحدة يوميًا) عشان أحلّل بياناتك وأعطيك خطة واضحة.',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: (_dailyLocked || _sending) ? null : _sendDailyReport,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.92),
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              color: Colors.black.withOpacity(0.06),
              offset: const Offset(0, -8),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textDirection: TextDirection.rtl,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: _dailyLocked
                      ? 'اسأل المدرب عن وجباتك/خطة اليوم…'
                      : 'اسأل سؤال عام… (الأفضل إرسال تقرير اليوم أولًا)',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.35)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.55), width: 1.3),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onSubmitted: (_) => _sendChat(),
              ),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, v, _) {
                final canSend = v.text.trim().isNotEmpty && !_sending;
                return IconButton.filled(
                  onPressed: canSend ? _sendChat : null,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  tooltip: 'إرسال',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg1 = theme.colorScheme.primary.withOpacity(0.08);
    final bg2 = theme.colorScheme.secondary.withOpacity(0.06);

    return PremiumGate(
      feature: PremiumFeature.coach,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('مدرب وازن الذكي'),
        centerTitle: true,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard, // اضغط فوق/على الشات لإخفاء الكيبورد
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bg1, bg2, theme.colorScheme.surface],
            ),
          ),
          child: Column(
            children: [
              _dailyButton(),
              Expanded(
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (n) {
                    if (n.direction != ScrollDirection.idle) _dismissKeyboard();
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 10),
                    itemCount: _msgs.length + (_sending ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_sending && i == _msgs.length) {
                        // مؤشر "يكتب..." بسيط أثناء الإرسال
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                          child: Row(
                            children: [
                              _roleAvatar(isMe: false),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant.withOpacity(0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    SizedBox(width: 6, height: 6, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(width: 10),
                                    Text('جاري الرد…', textDirection: TextDirection.rtl),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return _bubble(_msgs[i]);
                    },
                  ),
                ),
              ),
              _composer(),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
