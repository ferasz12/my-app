import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/changelog_page.dart';

class WhatsNewService {
  const WhatsNewService._();

  static const String _seenVersionKey = 'wazen_whats_new_seen_version_build_v2';

  static Future<String> _currentVersionBuildKey() async {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim().isEmpty ? '0.0.0' : info.version.trim();
    final build = info.buildNumber.trim().isEmpty ? '0' : info.buildNumber.trim();
    return '$version+$build';
  }

  static Future<String> currentVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim().isEmpty ? '0.0.0' : info.version.trim();
    final build = info.buildNumber.trim();
    if (build.isEmpty) return 'الإصدار $version';
    return 'الإصدار $version • build $build';
  }

  static Future<bool> shouldShowForCurrentVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _currentVersionBuildKey();
    final seen = prefs.getString(_seenVersionKey);
    return seen != current;
  }

  static Future<void> markCurrentVersionSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _currentVersionBuildKey();
    await prefs.setString(_seenVersionKey, current);
  }

  /// تعرض صفحة "ما الجديد" مرة واحدة فقط لكل إصدار/بيلد.
  /// استدعها بعد دخول المستخدم للشاشة الرئيسية، عشان ما تظهر فوق الأونبوردنغ.
  static Future<void> showIfNeeded(BuildContext context) async {
    final show = await shouldShowForCurrentVersion();
    if (!show || !context.mounted) return;

    final label = await currentVersionLabel();
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangelogPage(
          fromUpdatePrompt: true,
          versionLabel: label,
        ),
      ),
    );

    await markCurrentVersionSeen();
  }
}
