enum SubscriptionStatus { none, active, pastDue, canceled }

class TrainerPlan {
  final String trainerId;
  final String planId; // id عند مزوّد الدفع
  final String title;
  final int amountHalalas; // 100 = 1 SAR
  final String interval; // "month" | "year"
  const TrainerPlan({
    required this.trainerId,
    required this.planId,
    required this.title,
    required this.amountHalalas,
    required this.interval,
  });
}

class UserSubscription {
  final String userId;
  final String trainerId;
  final String subscriptionId; // id عند مزوّد الدفع
  final SubscriptionStatus status;
  final DateTime? currentPeriodEnd;
  const UserSubscription({
    required this.userId,
    required this.trainerId,
    required this.subscriptionId,
    required this.status,
    this.currentPeriodEnd,
  });
}

class PayoutOnboardingStatus {
  final bool isCompleted;
  final String? externalDashboardUrl;
  const PayoutOnboardingStatus(
      {required this.isCompleted, this.externalDashboardUrl});
}
