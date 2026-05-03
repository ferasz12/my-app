import 'package:cloud_firestore/cloud_firestore.dart';
import 'announcement_model.dart';

/// خدمة إدارة إعلان التطبيق العام (Banner)
class AnnouncementService {
  AnnouncementService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.doc('appConfig/announcement');

  /// بثّ حي للإعلان (يعيد null إذا ما فيه وثيقة)
  Stream<AnnouncementConfig?> watch() {
    return _doc.snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = Map<String, dynamic>.from(snap.data() ?? {});
      // نضمن تمرير updatedAt كما هو (Timestamp) — نموذجنا يتعامل معه
      if (snap.data()?.containsKey('updatedAt') == true) {
        data['updatedAt'] = snap.get('updatedAt');
      }
      return AnnouncementConfig.fromMap(data);
    });
  }

  /// قراءة مرة واحدة
  Future<AnnouncementConfig?> getOnce() async {
    final snap = await _doc.get();
    if (!snap.exists) return null;
    final data = Map<String, dynamic>.from(snap.data() ?? {});
    if (snap.data()?.containsKey('updatedAt') == true) {
      data['updatedAt'] = snap.get('updatedAt');
    }
    return AnnouncementConfig.fromMap(data);
  }

  /// تحديث جزئي (merge) — يضبط updatedAt تلقائيًا
  Future<void> update(Map<String, dynamic> partial) async {
    final data = <String, dynamic>{...partial};
    data['updatedAt'] = Timestamp.now();
    await _doc.set(data, SetOptions(merge: true));
  }

  /// تمكين/تعطيل سريع
  Future<void> setEnabled(bool enabled) =>
      update({'enabled': enabled});

  /// تهيئة افتراضية إذا ما كانت الوثيقة موجودة (اختياري)
  Future<void> ensureInitialized() async {
    final snap = await _doc.get();
    if (!snap.exists) {
      await _doc.set({
        'enabled': false,
        'message': '',
        'textColor': '#0F172A',
        'backgroundColor': '#ECFDF5',
        'type': 'info',
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: false));
    }
  }
}
