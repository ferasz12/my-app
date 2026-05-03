// lib/core/diagnostics/firestore_payload_utils.dart
//
// Utilities to safely work with Firestore payloads.

Map<String, dynamic> deepMergeMap(Map<String, dynamic> a, Map<String, dynamic> b) {
  final out = <String, dynamic>{...a};
  for (final e in b.entries) {
    final k = e.key;
    final v = e.value;
    if (v is Map && out[k] is Map) {
      out[k] = deepMergeMap(
        Map<String, dynamic>.from(out[k] as Map),
        Map<String, dynamic>.from(v as Map),
      );
    } else {
      out[k] = v;
    }
  }
  return out;
}

/// Convert dot-path keys (e.g. "metrics.score") into nested maps.
/// Needed for SetOptions(merge:true) fallback, because update() supports dot-paths
/// but set() merge doesn't reliably accept them on all platforms.
Map<String, dynamic> expandDotKeys(Map<String, dynamic> input) {
  final out = <String, dynamic>{};

  void insert(List<String> parts, dynamic value) {
    Map<String, dynamic> cur = out;
    for (int i = 0; i < parts.length; i++) {
      final p = parts[i];
      if (i == parts.length - 1) {
        cur[p] = value;
      } else {
        final existing = cur[p];
        if (existing is Map) {
          cur = existing as Map<String, dynamic>;
        } else {
          final m = <String, dynamic>{};
          cur[p] = m;
          cur = m;
        }
      }
    }
  }

  for (final e in input.entries) {
    final k = e.key;
    final v = e.value;
    if (!k.contains('.')) {
      if (v is Map && out[k] is Map) {
        out[k] = deepMergeMap(
          Map<String, dynamic>.from(out[k] as Map),
          Map<String, dynamic>.from(v as Map),
        );
      } else {
        out[k] = v;
      }
    } else {
      insert(k.split('.'), v);
    }
  }
  return out;
}
