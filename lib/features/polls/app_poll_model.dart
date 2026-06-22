import 'package:cloud_firestore/cloud_firestore.dart';

class AppPollConfig {
  final bool enabled;
  final String pollId;
  final String title;
  final String question;
  final String description;
  final List<String> options;
  final String linkText;
  final String linkUrl;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const AppPollConfig({
    required this.enabled,
    required this.pollId,
    required this.title,
    required this.question,
    required this.description,
    required this.options,
    required this.linkText,
    required this.linkUrl,
    this.startAt,
    this.endAt,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  static DateTime? _asDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  factory AppPollConfig.fromMap(Map<String, dynamic> data) {
    final rawOptions = data['options'];
    final options = rawOptions is Iterable
        ? rawOptions
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    final updatedAt = _asDateTime(data['updatedAt']);
    final pollId = (data['pollId'] ?? '').toString().trim().isNotEmpty
        ? (data['pollId'] ?? '').toString().trim()
        : 'poll_${updatedAt?.millisecondsSinceEpoch ?? 0}';

    return AppPollConfig(
      enabled: data['enabled'] == true,
      pollId: pollId,
      title: (data['title'] ?? 'ساعدنا نطور وازن').toString().trim(),
      question: (data['question'] ?? '').toString().trim(),
      description: (data['description'] ?? '').toString().trim(),
      options: options,
      linkText: (data['linkText'] ?? '').toString().trim(),
      linkUrl: (data['linkUrl'] ?? '').toString().trim(),
      startAt: _asDateTime(data['startAt']),
      endAt: _asDateTime(data['endAt']),
      createdAt: _asDateTime(data['createdAt']),
      updatedAt: updatedAt,
      createdBy: (data['createdBy'] as String?)?.trim(),
      updatedBy: (data['updatedBy'] as String?)?.trim(),
    );
  }

  bool get hasLink => linkUrl.isNotEmpty;

  bool get withinSchedule {
    final now = DateTime.now();
    if (startAt != null && now.isBefore(startAt!)) return false;
    if (endAt != null && now.isAfter(endAt!)) return false;
    return true;
  }

  bool get isReady => question.isNotEmpty && options.length >= 2;
  bool get isActive => enabled && isReady && withinSchedule;
}

class AppPollVote {
  final String uid;
  final String pollId;
  final int optionIndex;
  final String optionText;
  final DateTime? submittedAt;

  const AppPollVote({
    required this.uid,
    required this.pollId,
    required this.optionIndex,
    required this.optionText,
    this.submittedAt,
  });

  factory AppPollVote.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return AppPollVote(
      uid: (data['uid'] ?? doc.reference.parent.parent?.id ?? '').toString(),
      pollId: (data['pollId'] ?? '').toString(),
      optionIndex: (data['optionIndex'] is num) ? (data['optionIndex'] as num).toInt() : -1,
      optionText: (data['optionText'] ?? '').toString(),
      submittedAt: AppPollConfig._asDateTime(data['submittedAt']),
    );
  }
}
