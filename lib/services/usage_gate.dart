import 'package:cloud_functions/cloud_functions.dart';

class UsageGateResult {
  final bool allowed;
  final String? message;

  const UsageGateResult({required this.allowed, this.message});
}

/// بوابة استخدام يومية (من السيرفر) — تمنع التجاوز حتى لو بدّل المستخدم الجهاز.
class UsageGate {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<UsageGateResult> check({
    required String action,
    bool increment = true,
    String timeZone = 'Asia/Riyadh',
  }) async {
    final callable = _functions.httpsCallable('gateUsage');
    try {
      await callable.call(<String, dynamic>{
        'action': action,
        'increment': increment,
        'timeZone': timeZone,
      });
      return const UsageGateResult(allowed: true);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        return UsageGateResult(allowed: false, message: e.message);
      }
      return UsageGateResult(
        allowed: false,
        message: e.message ?? 'تعذّر التحقق من الحد اليومي. حاول لاحقًا.',
      );
    } catch (_) {
      return const UsageGateResult(
        allowed: false,
        message: 'تعذّر التحقق من الحد اليومي. تحقق من الشبكة ثم حاول.',
      );
    }
  }
}
