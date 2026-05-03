import 'models_subscriptions.dart';

abstract class PaymentsGateway {
  Future<PayoutOnboardingStatus> createOrResumeTrainerOnboarding({
    required String trainerId,
    required String trainerEmail,
    required String trainerIban,
  });

  Future<String> createTrainerPlan({
    required String trainerId,
    required String title,
    required int amountHalalas,
    required String interval,
    double platformFeePercent = 10.0,
  });

  Future<UserSubscription> createOrAttachSubscription({
    required String userId,
    required String trainerId,
    required String planId,
    required String userEmail,
    required String paymentMethodToken,
  });

  Future<UserSubscription> getSubscription(String subscriptionId);

  Future<void> cancelSubscription(String subscriptionId,
      {bool atPeriodEnd = true});
}
