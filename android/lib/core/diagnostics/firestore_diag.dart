import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// تشخيص Firestore: يطبع "السبب الجذري" Root Cause بطريقة واضحة.
///
/// الهدف: إذا فشلت كتابة onboarding، نعرف هل السبب:
/// - Permissions / App Check
/// - Unauthenticated
/// - Payload غير صالح (NaN/Infinity/Types)
/// - شبكة / DNS / WriteStream Internal
class FirestoreDiag {
  static final _rnd = Random();

  static String _id() =>
      '${DateTime.now().millisecondsSinceEpoch}-${_rnd.nextInt(999999)}';

  /// فحص سريع للإنترنت (DNS) — يعطي مؤشر هل الجهاز يقدر يحل دومين فايرستور.
  static Future<bool> _dnsOk({Duration timeout = const Duration(seconds: 3)}) async {
    // dart:io غير مدعوم على Web، لكن مشروعك حالياً iOS/Android.
    if (kIsWeb) return true;
    try {
      final res = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(timeout);
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// يتحقق أن القيم قابلة للتخزين في Firestore (بدون NaN/Infinity/أنواع غير مدعومة).
  static List<String> validateEncodable(Object? v, {String path = r'$'}) {
    final issues = <String>[];

    void walk(Object? x, String p) {
      if (x == null) return;

      if (x is String || x is bool || x is int) return;

      if (x is double) {
        if (x.isNaN) issues.add('INVALID_DOUBLE_NAN at $p');
        if (x.isInfinite) issues.add('INVALID_DOUBLE_INF at $p');
        return;
      }

      if (x is Timestamp || x is GeoPoint || x is DocumentReference) return;

      if (x is DateTime) return;

      if (x is FieldValue) return;

      if (x is List) {
        for (var i = 0; i < x.length; i++) {
          walk(x[i], '$p[$i]');
        }
        return;
      }

      if (x is Map) {
        for (final e in x.entries) {
          if (e.key is! String) {
            issues.add('MAP_KEY_NOT_STRING at $p (key=${e.key.runtimeType})');
          }
          walk(e.value, '$p.${e.key}');
        }
        return;
      }

      issues.add('UNSUPPORTED_TYPE ${x.runtimeType} at $p');
    }

    walk(v, path);
    return issues;
  }

  /// تشخيص كتابة باستخدام set(merge:true) (بدون dot-paths).
  static Future<void> diagnoseWrite({
    required String tag,
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> payload,
    String confirmField = 'onboardingLastWriteId',
  }) async {
    await _diagnose(
      tag: tag,
      ref: ref,
      payload: payload,
      confirmField: confirmField,
      doWrite: (writePayload) => ref.set(writePayload, SetOptions(merge: true)),
    );
  }

  /// تشخيص كتابة باستخدام update (مناسب للدوت-نوتيشن).
  static Future<void> diagnoseUpdate({
    required String tag,
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> payload,
    String confirmField = 'onboardingLastWriteId',
  }) async {
    await _diagnose(
      tag: tag,
      ref: ref,
      payload: payload,
      confirmField: confirmField,
      doWrite: (writePayload) async {
        try {
          await ref.update(writePayload);
        } on FirebaseException catch (e) {
          // إذا الوثيقة غير موجودة: أنشئها ثم أعد المحاولة
          if (e.code == 'not-found') {
            await ref.set({}, SetOptions(merge: true));
            await ref.update(writePayload);
            return;
          }
          rethrow;
        }
      },
    );
  }

  static Future<void> _diagnose({
    required String tag,
    required DocumentReference<Map<String, dynamic>> ref,
    required Map<String, dynamic> payload,
    required String confirmField,
    required Future<void> Function(Map<String, dynamic>) doWrite,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final diagId = _id();
    final t0 = DateTime.now();

    void log(String msg) => debugPrint('🧪 [FS-DIAG][$tag][$diagId] $msg');

    log('start (platform=${defaultTargetPlatform.name})');
    log('auth.uid=${uid ?? "NULL"}  ref.path=${ref.path}');

    final issues = validateEncodable(payload);
    if (issues.isNotEmpty) {
      log('❌ ROOT_CAUSE=INVALID_PAYLOAD');
      for (final s in issues) {
        log('   - $s');
      }
      return;
    } else {
      log('payload=OK(encodable)');
    }

    final dnsOk = await _dnsOk();
    log('internet_dns_ok=$dnsOk (lookup firestore.googleapis.com)');

    bool serverReadOk = false;
    try {
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      serverReadOk = true;
      final data = snap.data();
      log('server_read_ok=true exists=${snap.exists} $confirmField=${data?[confirmField]}');
    } catch (e) {
      log('server_read_ok=false server_read_error=$e');
    }

    final writeId = _id();
    final writePayload = <String, dynamic>{
      ...payload,
      confirmField: writeId,
      'diagLastAttemptAt': FieldValue.serverTimestamp(),
      'diagLastAttemptId': diagId,
    };

    log('write: sending... confirmField=$confirmField writeId=$writeId');

    try {
      await doWrite(writePayload).timeout(const Duration(seconds: 8));
      log('write_future_completed=true');
    } on FirebaseException catch (e) {
      final cause = _classifyFirebaseException(e, serverReadOk: serverReadOk, dnsOk: dnsOk);
      log('❌ ROOT_CAUSE=$cause');
      log('firebase_exception.code=${e.code}');
      log('firebase_exception.message=${e.message}');
      log('firebase_exception.toString=${e.toString()}');
      return;
    } catch (e) {
      log('❌ ROOT_CAUSE=UNKNOWN_DART_EXCEPTION');
      log('error=$e');
      return;
    }

    final ok = await _confirmOnServer(ref, confirmField, writeId);
    if (ok) {
      log('✅ SERVER_CONFIRMED ($confirmField == $writeId)');
    } else {
      log('❌ ROOT_CAUSE=NO_SERVER_ACK');
      log('يعني: الكتابة علقت محلياً (pendingWrites) لأن WriteStream/الشبكة غير مستقرة.');
    }

    log('DONE in ${DateTime.now().difference(t0).inMilliseconds}ms');
  }

  static Future<bool> _confirmOnServer(
    DocumentReference<Map<String, dynamic>> ref,
    String field,
    String expected, {
    Duration timeout = const Duration(seconds: 12),
    Duration pollEvery = const Duration(milliseconds: 700),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      try {
        final snap = await ref.get(const GetOptions(source: Source.server));
        final v = snap.data()?[field];
        if (v == expected) return true;
      } catch (_) {}
      await Future.delayed(pollEvery);
    }
    return false;
  }

  static String _classifyFirebaseException(
    FirebaseException e, {
    required bool serverReadOk,
    required bool dnsOk,
  }) {
    switch (e.code) {
      case 'permission-denied':
        return 'PERMISSION_DENIED (Rules أو AppCheck Enforcement)';
      case 'unauthenticated':
        return 'UNAUTHENTICATED (توكن غير صالح/المستخدم غير مسجّل)';
      case 'failed-precondition':
        return 'FAILED_PRECONDITION (غالباً AppCheck أو إعدادات بيئة)';
      case 'invalid-argument':
        return 'INVALID_ARGUMENT (نوع/قيمة غير مقبولة في Firestore)';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'NETWORK_UNAVAILABLE (اتصال/شبكة تمنع الوصول للسيرفر)';
      case 'internal':
        if (!dnsOk) return 'NETWORK_DNS_BLOCKED (DNS/شبكة)';
        if (!serverReadOk) {
          return 'WRITE_STREAM_INTERNAL_OFFLINE (gRPC/HTTP2 stream يطيح → Offline mode)';
        }
        return 'WRITE_STREAM_INTERNAL (stream يطيح رغم أن قراءة السيرفر أحياناً تعمل)';
      default:
        return 'FIREBASE_EXCEPTION_${e.code}';
    }
  }
}
