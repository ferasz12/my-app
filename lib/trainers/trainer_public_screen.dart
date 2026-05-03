import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../community/local_repos.dart'; // currentUser
import 'models.dart'; // Trainer
import 'messages_repo.dart'; // MessageRequest, MessagesRepo

// 👇 إضافات الاشتراكات
import 'package:intl/intl.dart';
import 'models_subscriptions.dart';
import 'payments_gateway.dart';
import 'payments_router.dart'; // resolveGateway()

class TrainerPublicScreen extends StatefulWidget {
  final String trainerId;
  final Trainer? trainer;

  const TrainerPublicScreen({
    super.key,
    required this.trainerId,
    this.trainer,
  });

  @override
  State<TrainerPublicScreen> createState() => _TrainerPublicScreenState();
}

class _TrainerPublicScreenState extends State<TrainerPublicScreen> {
  final _uuid = const Uuid();
  final _msgRepo = MessagesRepo();
  final _money = NumberFormat("#,##0.00", "ar_SA");

  late final PaymentsGateway _gateway;

  bool _sendingInquiry = false;

  // حالة اشتراك المستخدم الحالي مع هذا المدرب
  UserSubscription? _sub;
  bool _loadingSub = false;
  String? _subError;

  @override
  void initState() {
    super.initState();
    _gateway = resolveGateway();
    _loadMySubscription();
  }

  Future<void> _loadMySubscription() async {
    setState(() {
      _loadingSub = true;
      _subError = null;
    });
    try {
      final me = await LocalAuthRepo().currentUser();
      // في مشروعك، الأفضل تخزّن subscriptionId عندك (مثلاً في باكندك)
      // هنا نفترض أنك تقدر تجيبه عبر local repo أو API — سنضع placeholder:
      final String? subscriptionId =
          await _fetchMySubscriptionId(me.uid, widget.trainerId);
      if (subscriptionId != null) {
        _sub = await _gateway.getSubscription(subscriptionId);
      } else {
        _sub = null;
      }
    } catch (e) {
      _subError = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loadingSub = false);
      }
    }
  }

  // TODO: اربطها بباكندك — ترجّع subscriptionId الحالي إن وجد
  Future<String?> _fetchMySubscriptionId(
      String userId, String trainerId) async {
    // مؤقتًا: لا يوجد
    return null;
  }

  bool get _isActive =>
      _sub?.status == SubscriptionStatus.active ||
      _sub?.status == SubscriptionStatus.pastDue;

  @override
  Widget build(BuildContext context) {
    final t = widget.trainer;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t?.name ?? 'المدرب'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadMySubscription,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (t != null) _TrainerHeader(trainer: t, money: _money),

            const SizedBox(height: 12),

            if (_loadingSub)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(12.0),
                child: CircularProgressIndicator(),
              ))
            else ...[
              if (_subError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text('تعذر تحميل حالة الاشتراك: $_subError',
                      style: const TextStyle(color: Colors.red)),
                ),

              // ✅ إن كان المستخدم مشترك: عرض حالة الاشتراك + إدارة
              if (_isActive)
                _ActiveSubCard(sub: _sub!, onManage: _openManageSheet)

              // ❌ غير مشترك: Paywall + CTA اشتراك
              else
                _PaywallCard(
                  trainer: t,
                  money: _money,
                  onSubscribe: _subscribeFlow,
                ),
            ],

            const SizedBox(height: 12),

            // CTA: استفسر قبل الاشتراك (كما في كودك السابق)
            FilledButton.icon(
              onPressed:
                  _sendingInquiry ? null : () => _openInquirySheet(context),
              icon: const Icon(Icons.mail_outline),
              label: _sendingInquiry
                  ? const Text('جارٍ الإرسال...')
                  : const Text('استفسر قبل الاشتراك'),
            ),

            const SizedBox(height: 16),
            Text(
              _isActive
                  ? 'اشتراكك فعّال — ستظهر لك الميزات المميّزة الخاصة بهذا المدرب.'
                  : 'اشترك للوصول إلى الميزات الحصرية الخاصة بهذا المدرب.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// الخطوة العملية للاشتراك:
  /// - نجلب planId من باكندك لخطة هذا المدرب
  /// - نأخذ paymentMethodToken (من SDK حقيقي أو IAP لاحقًا)
  /// - نرسل الطلب عبر PaymentsGateway
  Future<void> _subscribeFlow() async {
    try {
      final me = await LocalAuthRepo().currentUser();

      // 1) احصل على planId من باكندك — هنا مثال/placeholder:
      final planId =
          await _getOrCreatePlanIdForTrainer(widget.trainerId, widget.trainer);

      // 2) اجلب paymentMethodToken (حاليًا bottom sheet تجريبي)
      final token = await _getPaymentTokenDemo(context);
      if (token == null) return;

      // 3) نفّذ الاشتراك
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري إنشاء الاشتراك...')),
      );

      final sub = await _gateway.createOrAttachSubscription(
        userId: me.uid,
        trainerId: widget.trainerId,
        planId: planId,
        userEmail: me.email,
        paymentMethodToken: token,
      );

      setState(() => _sub = sub);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم الاشتراك بنجاح ✅')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الاشتراك: $e')),
      );
    }
  }

  // TODO: اربطها بباكندك — إما ترجّع Plan موجود أو تنشئ Plan جديد للمدرب
  Future<String> _getOrCreatePlanIdForTrainer(
      String trainerId, Trainer? t) async {
    // مثال: استخدم السعر الشهري لو موجود، وإلا سعر افتراضي
    final int amountHalalas =
        (t?.priceMonthlyCents ?? 2900) * 1; // 29.00 SAR كمثال
    final String interval = 'month';
    final String title = 'اشتراك ${t?.name ?? "المدرب"} الشهري';

    // الأفضل: تنادي باكندك: POST /plans → يرجّع planId
    // هنا نولّد معرّف تجريبي (لن يعمل للدفع الحقيقي):
    return 'trainer_${trainerId}_monthly';
  }

  Future<String?> _getPaymentTokenDemo(BuildContext context) async {
    final controller = TextEditingController();
    final emailCtrl = TextEditingController();
    final token = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c) {
        final bottom = MediaQuery.of(c).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(c).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              const Text('بيانات الدفع (تجريبية)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                decoration:
                    const InputDecoration(labelText: 'بريدك الإلكتروني'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Payment Method Token',
                  hintText: 'ضع التوكن من SDK/Apple IAP لاحقًا',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                          c,
                          controller.text.trim().isEmpty
                              ? null
                              : controller.text.trim()),
                      child: const Text('متابعة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(c, null),
                      child: const Text('إلغاء'),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
    return token;
  }

  Future<void> _openManageSheet() async {
    if (_sub == null) return;
    final sub = _sub!;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(c).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              const Text('إدارة الاشتراك',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('الحالة: ${sub.status.name}'),
              if (sub.currentPeriodEnd != null)
                Text(
                    'ينتهي في: ${DateFormat.yMMMd("ar").add_Hm().format(sub.currentPeriodEnd!.toLocal())}'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(c);
                  await _cancelSub(sub.subscriptionId);
                },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء الاشتراك'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelSub(String subscriptionId) async {
    try {
      await _gateway.cancelSubscription(subscriptionId, atPeriodEnd: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب إلغاء الاشتراك')),
      );
      await _loadMySubscription();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الإلغاء: $e')),
      );
    }
  }

  Future<void> _openInquirySheet(BuildContext context) async {
    final controller = TextEditingController();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (c) {
        final viewInsets = MediaQuery.of(c).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: _InquirySheet(
            controller: controller,
            onSend: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(content: Text('اكتب استفسارك أولاً')));
                return;
              }
              Navigator.pop(c, true);
              await _sendInquiry(text);
            },
          ),
        );
      },
    );

    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب التواصل 🚀')),
      );
    }
  }

  Future<void> _sendInquiry(String text) async {
    setState(() => _sendingInquiry = true);
    try {
      final me = await LocalAuthRepo().currentUser();
      await _msgRepo.createRequest(
        MessageRequest(
          id: _uuid.v4(),
          trainerId: widget.trainerId,
          fromUserId: me.uid,
          text: text,
          createdAt: DateTime.now(),
          status: 'open',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الإرسال: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingInquiry = false);
    }
  }
}

class _TrainerHeader extends StatelessWidget {
  final Trainer trainer;
  final NumberFormat money;
  const _TrainerHeader({required this.trainer, required this.money});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trainer.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (trainer.bio.isNotEmpty) Text(trainer.bio),
            const SizedBox(height: 8),
            Row(
              children: [
                Chip(
                    label: Text(
                        'سعر شهري: ${money.format((trainer.priceMonthlyCents / 100))} ر.س')),
                const SizedBox(width: 8),
                Chip(
                    label: Text('تقييم: ${trainer.rating.toStringAsFixed(1)}')),
              ],
            ),
            if (trainer.specialties.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: trainer.specialties
                    .map((e) => Chip(label: Text(e)))
                    .toList(),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

class _PaywallCard extends StatelessWidget {
  final Trainer? trainer;
  final NumberFormat money;
  final VoidCallback onSubscribe;
  const _PaywallCard(
      {required this.trainer, required this.money, required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    final t = trainer;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الميزات المميّزة',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const _Feature(text: 'برامج تدريب حصرية'),
            const _Feature(text: 'مكتبة فيديوهات خاصة'),
            const _Feature(text: 'أولوية في الرد والاستشارات'),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  t != null
                      ? '${money.format((t.priceMonthlyCents / 100))} ر.س / شهر'
                      : 'سعر شهري',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onSubscribe,
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: const Text('اشترك الآن'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveSubCard extends StatelessWidget {
  final UserSubscription sub;
  final VoidCallback onManage;
  const _ActiveSubCard({required this.sub, required this.onManage});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.withOpacity(.06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اشتراكك فعّال ✅',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (sub.currentPeriodEnd != null)
              Text(
                  'تجديد تلقائي حتى: ${DateFormat.yMMMd("ar").add_Hm().format(sub.currentPeriodEnd!.toLocal())}'),
            const SizedBox(height: 10),
            Row(
              children: [
                const _Feature(text: 'فتح الميزات الحصرية'),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onManage,
                  icon: const Icon(Icons.settings),
                  label: const Text('إدارة الاشتراك'),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final String text;
  const _Feature({required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const Icon(Icons.check_circle_outline, size: 18),
      const SizedBox(width: 6),
      Expanded(child: Text(text)),
    ]);
  }
}

/// —— الاستفسار قبل الاشتراك (كما هو سابقًا) ——
class _InquirySheet extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _InquirySheet({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('استفسار قبل الاشتراك',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'اكتب رسالتك/سؤالك للمدرب...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSend,
                  icon: const Icon(Icons.send),
                  label: const Text('إرسال'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
