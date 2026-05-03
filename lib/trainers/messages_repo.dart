// lib/trainers/messages_repo.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MessageRequest {
  final String id; // uuid
  final String trainerId; // id المدرب (يفضّل uid)
  final String fromUserId; // uid صاحب الطلب
  final String text; // نص الاستفسار
  final DateTime createdAt;
  final String status; // 'open' | 'approved' | 'rejected'

  MessageRequest({
    required this.id,
    required this.trainerId,
    required this.fromUserId,
    required this.text,
    required this.createdAt,
    required this.status,
  });

  factory MessageRequest.fromJson(Map<String, dynamic> j) => MessageRequest(
        id: j['id'],
        trainerId: j['trainerId'],
        fromUserId: j['fromUserId'],
        text: j['text'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt']),
        status: j['status'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trainerId': trainerId,
        'fromUserId': fromUserId,
        'text': text,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'status': status,
      };
}

class MessagesRepo {
  static const _kRequests = 'trainer_message_requests';

  Future<List<MessageRequest>> listForTrainer(String trainerId,
      {String status = ''}) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kRequests);
    if (raw == null) return [];
    final all = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(MessageRequest.fromJson)
        .toList();
    final mine = all.where((r) => r.trainerId == trainerId).toList();
    if (status.isEmpty) return mine;
    return mine.where((r) => r.status == status).toList();
  }

  Future<void> _save(List<MessageRequest> all) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kRequests, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<void> updateStatus(String requestId, String newStatus) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kRequests);
    if (raw == null) return;
    final all = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(MessageRequest.fromJson)
        .toList();
    final i = all.indexWhere((r) => r.id == requestId);
    if (i == -1) return;
    final r = all[i];
    all[i] = MessageRequest(
      id: r.id,
      trainerId: r.trainerId,
      fromUserId: r.fromUserId,
      text: r.text,
      createdAt: r.createdAt,
      status: newStatus,
    );
    await _save(all);
  }

  /// للاستخدام لاحقاً في شاشة المستخدم: إنشاء طلب جديد
  Future<void> createRequest(MessageRequest request) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kRequests);
    final all = raw == null
        ? <MessageRequest>[]
        : (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(MessageRequest.fromJson)
            .toList();
    all.add(request);
    await _save(all);
  }

  Future<void> deleteRequest(String id) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kRequests);
    if (raw == null) return;
    final all = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(MessageRequest.fromJson)
        .toList();
    all.removeWhere((r) => r.id == id);
    await _save(all);
  }
}
