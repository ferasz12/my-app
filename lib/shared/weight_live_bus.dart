import 'dart:async';

/// نبضة موحّدة لتحديث كل صفحات التتبع فور تغيّر الوزن من أي صفحة.
class WeightLiveBus {
  WeightLiveBus._();

  static final StreamController<void> _ctrl =
      StreamController<void>.broadcast();

  static Stream<void> get stream => _ctrl.stream;

  static void ping() {
    if (!_ctrl.isClosed) _ctrl.add(null);
  }
}
