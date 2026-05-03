import 'package:flutter/foundation.dart';
import '../trainers/models_subscriptions.dart';
import '../trainers/payments_gateway.dart';

class SubscriptionState extends ChangeNotifier {
  final PaymentsGateway gateway;
  UserSubscription? current;
  bool loading = false;
  String? error;

  SubscriptionState(this.gateway);

  Future<void> subscribe({
    required String userId,
    required String trainerId,
    required String planId,
    required String email,
    required String paymentMethodToken,
  }) async {
    try {
      loading = true;
      error = null;
      notifyListeners();
      current = await gateway.createOrAttachSubscription(
        userId: userId,
        trainerId: trainerId,
        planId: planId,
        userEmail: email,
        paymentMethodToken: paymentMethodToken,
      );
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
