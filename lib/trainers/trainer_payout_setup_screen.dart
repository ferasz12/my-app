import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'models_subscriptions.dart';
import 'payments_gateway.dart';

class TrainerPayoutSetupScreen extends StatefulWidget {
  final PaymentsGateway gateway;
  final String trainerId, email;
  const TrainerPayoutSetupScreen(
      {super.key,
      required this.gateway,
      required this.trainerId,
      required this.email});
  @override
  State<TrainerPayoutSetupScreen> createState() =>
      _TrainerPayoutSetupScreenState();
}

class _TrainerPayoutSetupScreenState extends State<TrainerPayoutSetupScreen> {
  final _ibanCtrl = TextEditingController();
  PayoutOnboardingStatus? status;
  bool loading = false;
  String? error;

  Future<void> _submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      status = await widget.gateway.createOrResumeTrainerOnboarding(
        trainerId: widget.trainerId,
        trainerEmail: widget.email,
        trainerIban: _ibanCtrl.text.trim(),
      );
    } catch (e) {
      error = e.toString();
    } finally {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    _ibanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعداد استلام الأرباح')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اربط حسابك البنكي لاستلام أرباح اشتراكاتك',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
                controller: _ibanCtrl,
                decoration: const InputDecoration(labelText: 'IBAN')),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: loading ? null : _submit,
                child: Text(loading ? 'جارٍ...' : 'أكمل الربط')),
            if (status != null) ...[
              const SizedBox(height: 12),
              Text(status!.isCompleted
                  ? 'تم الربط بنجاح'
                  : 'بحاجة لإكمال خطوات'),
              if (status!.externalDashboardUrl != null)
                TextButton(
                    onPressed: () =>
                        launchUrlString(status!.externalDashboardUrl!),
                    child: const Text('إكمال من لوحة المزوّد')),
            ],
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child:
                      Text(error!, style: const TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
