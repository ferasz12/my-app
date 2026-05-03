// lib/features/users/ui/user_profile_page.dart
// صفحة بروفايل بفخامة أعلى لتطبيق صحي:
// - خلفية متدرجة بألوان هادئة
// - هيدر كبير للصورة والاسم واليوزر
// - شريط للألقاب والشارات (الإنجازات)
// - بطاقة للنبذة (البايو)
// - بطاقة لحسابات التواصل
//
// تم الإبقاء على نفس المنطق بالكامل:
// - الاستماع لوثيقة users/{uid}
// - قراءة bio من الجذر users/{uid}.bio مع fallback اختياري من profile/basic (قراءة فقط)
// - قراءة social من الجذر users/{uid}.social مع fallback اختياري من profile/social (قراءة فقط)
// - نفس Hero tag للصورة: 'profile_photo_$uid'

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class UserProfilePage extends StatelessWidget {
  final String uid;
  const UserProfilePage({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final rootDoc = FirebaseFirestore.instance.collection('users').doc(uid);
    final basicRef = FirebaseFirestore.instance.doc('users/$uid/profile/basic');
    final socialRef = FirebaseFirestore.instance.doc('users/$uid/profile/social');

    return Directionality(
      textDirection: TextDirection.ltr,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: rootDoc.snapshots(),
        builder: (context, rootSnap) {
          final exists = rootSnap.hasData && rootSnap.data!.exists;
          final root = exists
              ? (rootSnap.data!.data() ?? const <String, dynamic>{})
              : const <String, dynamic>{};

          final displayName = (root['name'] ?? root['displayName'] ?? '').toString().trim();
          final username = (root['username'] ?? '').toString().trim();
          final photoUrl = (root['photoUrl'] as String?)?.trim();
          final avatarSize = ((root['avatarSize'] as num?)?.toDouble() ?? 72).clamp(72, 128).toDouble();

          // الإنجازات: اللقب + الإيموجي
          final achievements =
              (root['achievements'] as Map<String, dynamic>?) ??
                  const <String, dynamic>{};
          final currentTitle =
              (achievements['title'] ?? '').toString().trim();
          final badgeEmojis = ((achievements['badgeEmojis'] as List?) ??
                  const <dynamic>[])
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList();

          final appTitle = displayName.isNotEmpty
              ? displayName
              : (username.isNotEmpty ? '@$username' : 'الملف الشخصي');

          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.10),
                    Theme.of(context).colorScheme.surface,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    _ProfileAppBar(title: appTitle),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ProfileHeaderCard(
                              uid: uid,
                              photoUrl: photoUrl,
                              displayName: displayName,
                              username: username,
                              avatarSize: avatarSize,
                            ),
                            const SizedBox(height: 16),
                            if (currentTitle.isNotEmpty ||
                                badgeEmojis.isNotEmpty)
                              _AchievementsRibbon(
                                currentTitle: currentTitle,
                                badgeEmojis: badgeEmojis,
                              ),
                            const SizedBox(height: 16),

                            // ===== البايو (Legacy root: users/{uid}.bio) =====
                            Builder(
                              builder: (context) {
                                final rootBio =
                                    (root['bio'] as String?)?.trim();
                                if (rootBio != null && rootBio.isNotEmpty) {
                                  return _InfoSectionCard(
                                    icon: Icons.info_outline,
                                    title: 'نبذة',
                                    child: Text(
                                      rootBio,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  );
                                }

                                // fallback اختياري للقراءة فقط (توافق خلفي) من profile/basic
                                return StreamBuilder<
                                    DocumentSnapshot<Map<String, dynamic>>>(
                                  stream: basicRef.snapshots(),
                                  builder: (context, basicSnap) {
                                    final basic = basicSnap.data?.data();
                                    final bio =
                                        (basic?['bio'] as String?)?.trim();
                                    if (bio == null || bio.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return _InfoSectionCard(
                                      icon: Icons.info_outline,
                                      title: 'نبذة',
                                      child: Text(
                                        bio,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),

                            // ===== حسابات السوشيال (Legacy root: users/{uid}.social) =====
                            Builder(
                              builder: (context) {
                                Widget buildSocialFromMap(
                                    Map<String, dynamic> social) {
                                  final ig =
                                      (social['instagram'] as String?)?.trim();
                                  final sc =
                                      (social['snapchat'] as String?)?.trim();
                                  final tk =
                                      (social['tiktok'] as String?)?.trim();

                                  final entries = <_SocialEntry>[];
                                  if (ig != null && ig.isNotEmpty) {
                                    entries.add(_SocialEntry(
                                      platform: 'Instagram',
                                      platformKey: 'instagram',
                                      raw: ig,
                                      display: '@$ig',
                                      icon: FontAwesomeIcons.instagram,
                                    ));
                                  }
                                  if (sc != null && sc.isNotEmpty) {
                                    entries.add(_SocialEntry(
                                      platform: 'Snapchat',
                                      platformKey: 'snapchat',
                                      raw: sc,
                                      display: '@$sc',
                                      icon: FontAwesomeIcons.snapchatGhost,
                                    ));
                                  }
                                  if (tk != null && tk.isNotEmpty) {
                                    entries.add(_SocialEntry(
                                      platform: 'TikTok',
                                      platformKey: 'tiktok',
                                      raw: tk,
                                      display: '@$tk',
                                      icon: FontAwesomeIcons.tiktok,
                                    ));
                                  }

                                  if (entries.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  return _InfoSectionCard(
                                    icon: Icons.alternate_email,
                                    title: 'حسابات التواصل',
                                    child: Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: entries
                                          .map((e) => _SocialChip(entry: e))
                                          .toList(),
                                    ),
                                  );
                                }

                                final rootSocial = (root['social'] is Map)
                                    ? Map<String, dynamic>.from(
                                        root['social'] as Map)
                                    : null;

                                if (rootSocial != null &&
                                    rootSocial.isNotEmpty) {
                                  return buildSocialFromMap(rootSocial);
                                }

                                // fallback اختياري للقراءة فقط (توافق خلفي) من البنية الجديدة
                                return StreamBuilder<
                                    DocumentSnapshot<Map<String, dynamic>>>(
                                  stream: socialRef.snapshots(),
                                  builder: (context, socialSnap) {
                                    final social = socialSnap.data?.data() ??
                                        const <String, dynamic>{};
                                    return buildSocialFromMap(social);
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// شريط علوي بسيط بدل AppBar الكلاسيكي
class _ProfileAppBar extends StatelessWidget {
  final String title;
  const _ProfileAppBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Tooltip(
            message: 'رجوع',
            child: BackButton(
              color: cs.onSurface,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
            ),
          ),
          const SizedBox(width: 56), // مساحة تعادل حجم زر الرجوع للطرف الآخر
        ],
      ),
    );
  }
}

/// الكرت الرئيسي: الصورة + الاسم + اليوزر
class _ProfileHeaderCard extends StatelessWidget {
  final String uid;
  final String? photoUrl;
  final String displayName;
  final String username;
  final double avatarSize;

  const _ProfileHeaderCard({
    required this.uid,
    required this.photoUrl,
    required this.displayName,
    required this.username,
    required this.avatarSize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = displayName.isNotEmpty ? displayName : 'مستخدم';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final url = (photoUrl ?? '').trim();
              if (url.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _FullScreenImageViewer(
                    heroTag: 'profile_photo_$uid',
                    imageUrl: url,
                  ),
                  fullscreenDialog: true,
                ),
              );
            },
            child: Hero(
              tag: 'profile_photo_$uid',
              child: _ProfilePhoto(photoUrl: photoUrl, size: avatarSize),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                ),
                const SizedBox(height: 4),
                if (username.isNotEmpty) ...[
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementsRibbon extends StatelessWidget {
  final String currentTitle;
  final List<String> badgeEmojis;

  const _AchievementsRibbon({
    required this.currentTitle,
    required this.badgeEmojis,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined,
              color: cs.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              currentTitle.isNotEmpty ? currentTitle : 'إنجازات',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
            ),
          ),
          if (badgeEmojis.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(
              spacing: 6,
              children: badgeEmojis
                  .take(6)
                  .map(
                    (e) => Text(
                      e,
                      style: const TextStyle(fontSize: 18),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// كرت لقسم (نبذة / حسابات تواصل / ... )
class _InfoSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _InfoSectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SocialEntry {
  final String platform; // Display name
  final String platformKey; // instagram | snapchat | tiktok
  final String raw; // Username or full URL
  final String display; // What to show to user
  final IconData icon;

  const _SocialEntry({
    required this.platform,
    required this.platformKey,
    required this.raw,
    required this.display,
    required this.icon,
  });

  String _normalizeHandle(String raw) {
    var h = raw.trim();
    if (h.isEmpty) return '';
    final lower = h.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return h;
    if (lower.startsWith('www.')) return 'https://$h';
    if (h.startsWith('@')) h = h.substring(1).trim();
    return h;
  }

  Uri? toUri() {
    final h = _normalizeHandle(raw);
    if (h.isEmpty) return null;

    final lower = h.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return Uri.tryParse(h);
    }

    switch (platformKey) {
      case 'instagram':
        return Uri.tryParse('https://www.instagram.com/$h');
      case 'snapchat':
        return Uri.tryParse('https://www.snapchat.com/add/$h');
      case 'tiktok':
        return Uri.tryParse('https://www.tiktok.com/@$h');
      default:
        return null;
    }
  }
}

class _SocialChip extends StatelessWidget {
  final _SocialEntry entry;
  const _SocialChip({required this.entry});

  Future<void> _open(BuildContext context) async {
    final uri = entry.toUri();
    if (uri == null) return;

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canOpen = entry.toUri() != null;

    return InkWell(
      onTap: canOpen ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(entry.icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              entry.display,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
            ),
            if (canOpen) ...[
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded,
                  size: 16, color: cs.onSurfaceVariant.withOpacity(0.9)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfilePhoto extends StatelessWidget {
  final String? photoUrl;
  final double size;

  const _ProfilePhoto({required this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = (photoUrl ?? '').trim();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surfaceVariant.withOpacity(0.35),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: ClipOval(
        child: url.isEmpty
            ? Icon(Icons.person, size: size * 0.55, color: cs.onSurfaceVariant)
            : Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
                errorBuilder: (context, error, stack) => Icon(
                  Icons.broken_image,
                  color: cs.onSurfaceVariant,
                  size: size * 0.55,
                ),
              ),
      ),
    );
  }
}

/// عارض صورة بملء الشاشة مع تكبير/تصغير (Pinch Zoom)
///
/// - يدعم السحب والتكبير
/// - زر إغلاق (X) بتصميم زجاجي بسيط
class _FullScreenImageViewer extends StatelessWidget {
  final String heroTag;
  final String imageUrl;

  const _FullScreenImageViewer({
    required this.heroTag,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 0.85,
                    maxScale: 4.0,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stack) => const Icon(
                        Icons.broken_image,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: _GlassIconButton(
                  icon: Icons.close,
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'إغلاق',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.white.withOpacity(0.12),
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  icon,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}