import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models_subscriptions.dart';
import 'payments_gateway.dart';

class TapGateway implements PaymentsGateway {
  final String apiBase; // مثال: https://api.yourapp.com/payments/tap
  final http.Client _client;
  TapGateway({required this.apiBase, http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<PayoutOnboardingStatus> createOrResumeTrainerOnboarding({
    required String trainerId,
    required String trainerEmail,
    required String trainerIban,
  }) async {
    final res = await _client.post(
      Uri.parse('$apiBase/trainers/onboarding'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'trainerId': trainerId, 'email': trainerEmail, 'iban': trainerIban}),
    );
    if (res.statusCode != 200) throw Exception('Onboarding failed');
    final d = jsonDecode(res.body);
    return PayoutOnboardingStatus(
      isCompleted: d['isCompleted'] == true,
      externalDashboardUrl: d['externalDashboardUrl'],
    );
  }

  @override
  Future<String> createTrainerPlan({
    required String trainerId,
    required String title,
    required int amountHalalas,
    required String interval,
    double platformFeePercent = 10.0,
  }) async {
    final res = await _client.post(
      Uri.parse('$apiBase/plans'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'trainerId': trainerId,
        'title': title,
        'amountHalalas': amountHalalas,
        'interval': interval,
        'platformFeePercent': platformFeePercent,
      }),
    );
    if (res.statusCode != 200) throw Exception('Plan creation failed');
    return (jsonDecode(res.body))['planId'];
  }

  @override
  Future<UserSubscription> createOrAttachSubscription({
    required String userId,
    required String trainerId,
    required String planId,
    required String userEmail,
    required String paymentMethodToken,
  }) async {
    final res = await _client.post(
      Uri.parse('$apiBase/subscriptions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'trainerId': trainerId,
        'planId': planId,
        'email': userEmail,
        'paymentMethodToken': paymentMethodToken,
      }),
    );
    if (res.statusCode != 200) throw Exception('Subscription failed');
    final d = jsonDecode(res.body);
    return UserSubscription(
      userId: userId,
      trainerId: trainerId,
      subscriptionId: d['subscriptionId'],
      status: _mapStatus(d['status']),
      currentPeriodEnd: d['currentPeriodEnd'] != null
          ? DateTime.parse(d['currentPeriodEnd'])
          : null,
    );
  }

  @override
  Future<UserSubscription> getSubscription(String subscriptionId) async {
    final res =
        await _client.get(Uri.parse('$apiBase/subscriptions/$subscriptionId'));
    if (res.statusCode != 200) throw Exception('Get subscription failed');
    final d = jsonDecode(res.body);
    return UserSubscription(
      userId: d['userId'],
      trainerId: d['trainerId'],
      subscriptionId: subscriptionId,
      status: _mapStatus(d['status']),
      currentPeriodEnd: d['currentPeriodEnd'] != null
          ? DateTime.parse(d['currentPeriodEnd'])
          : null,
    );
  }

  @override
  Future<void> cancelSubscription(String subscriptionId,
      {bool atPeriodEnd = true}) async {
    final res = await _client.post(
      Uri.parse('$apiBase/subscriptions/$subscriptionId/cancel'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'atPeriodEnd': atPeriodEnd}),
    );
    if (res.statusCode != 200) throw Exception('Cancel failed');
  }

  SubscriptionStatus _mapStatus(String s) {
    switch (s) {
      case 'active':
        return SubscriptionStatus.active;
      case 'past_due':
        return SubscriptionStatus.pastDue;
      case 'canceled':
        return SubscriptionStatus.canceled;
      default:
        return SubscriptionStatus.none;
    }
  }
}
