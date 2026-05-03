import 'dart:async';
import 'package:flutter/material.dart';
import 'announcement_model.dart';
import 'announcement_service.dart';

// ملاحظة: لو حاب تحفظ الإخفاء محليًا بين تشغيل وآخر، أضِف shared_preferences في pubspec واستخدمه.
// هنا بخليه Session-only لتبسيط التركيب. نقدر نزوّده لاحقًا بحفظ دائم.

class GlobalAnnouncementBanner extends StatefulWidget {
  const GlobalAnnouncementBanner({super.key});

  @override
  State<GlobalAnnouncementBanner> createState() => _GlobalAnnouncementBannerState();
}

class _GlobalAnnouncementBannerState extends State<GlobalAnnouncementBanner> {
  final _svc = AnnouncementService();
  StreamSubscription<AnnouncementConfig?>? _sub;
  AnnouncementConfig? _cfg;
  bool _dismissedThisSession = false;

  @override
  void initState() {
    super.initState();
    _sub = _svc.watch().listen((c) {
      setState(() {
        _cfg = c;
        // إذا تغيّر الإعلان، نرفع الإخفاء المؤقت
        _dismissedThisSession = false;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'maintenance':
        return Icons.build_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cfg;

    if (c == null || !c.isActive || _dismissedThisSession) {
      return const SizedBox.shrink();
    }

    final style = TextStyle(
      fontFamily: (c.fontFamily?.isNotEmpty ?? false) ? c.fontFamily : null,
      fontSize: c.fontSize ?? 16,
      fontWeight: c.bold ? FontWeight.w700 : FontWeight.w500,
      fontStyle: c.italic ? FontStyle.italic : FontStyle.normal,
      color: c.textColor,
      height: 1.35,
    );

    return Material(
      color: c.backgroundColor,
      elevation: 0,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconFor(c.type), color: style.color?.withOpacity(.9)),
              const SizedBox(width: 10),
              if ((c.imageUrl ?? '').isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    c.imageUrl!,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.message, style: style),
                    if ((c.linkUrl ?? '').isNotEmpty && (c.linkText ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextButton(
                          onPressed: () {
                            // TODO: افتح الرابط داخليًا عبر الراوتر عندك أو استخدم url_launcher للرابط الخارجي
                            // مثال: launchUrlString(c.linkUrl!)
                          },
                          child: Text(
                            c.linkText!,
                            style: style.copyWith(decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'إخفاء',
                onPressed: () => setState(() => _dismissedThisSession = true),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
