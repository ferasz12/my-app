import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  static const String _supportEmail = 'support@wazensapp.com';

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الرابط')),
      );
    }
  }

  Future<void> _sendSupportEmail() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final message = _messageController.text.trim();

    final subject = 'Wazen Support';
    final body = [
      'الاسم: $name',
      'البريد: $email',
      '',
      'الرسالة:',
      message,
    ].join('\n');

    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: <String, String>{
        'subject': subject,
        'body': body,
      },
    );

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح تطبيق البريد')),
      );
      return;
    }

    // Optional UX: confirm and reset.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم فتح البريد لإرسال الرسالة للدعم')),
    );
  }

  Widget _socialButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final color = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.10),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Center(
            child: FaIcon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تواصل معنا'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
              ),
              child: Row(
                children: [
                  Icon(Icons.support_agent_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'راسل فريق وازن مباشرة على:\n$_supportEmail',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () async {
                      final uri = Uri(scheme: 'mailto', path: _supportEmail);
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    child: const Text('فتح'),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Form Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'أرسل رسالة للدعم',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.start,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'الاسم',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return 'الرجاء إدخال الاسم';
                        if (v.length < 2) return 'الاسم قصير جدًا';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return 'الرجاء إدخال البريد';
                        if (!v.contains('@') || !v.contains('.')) {
                          return 'اكتب بريد صحيح';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        labelText: 'الرسالة',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return 'الرجاء كتابة الرسالة';
                        if (v.length < 10) return 'اكتب تفاصيل أكثر';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _sendSupportEmail,
                      child: const Text('إرسال إلى الدعم'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'تابعنا على مواقع التواصل',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _socialButton(
                  icon: FontAwesomeIcons.instagram,
                  tooltip: 'Instagram',
                  onTap: () => _launchUrl('https://www.instagram.com/wazen_app'),
                ),
                _socialButton(
                  icon: FontAwesomeIcons.tiktok,
                  tooltip: 'TikTok',
                  onTap: () => _launchUrl(
                      'https://www.tiktok.com/@wazenapp?_r=1&_t=ZS-938zxXWdWFA'),
                ),
                _socialButton(
                  icon: FontAwesomeIcons.xTwitter,
                  tooltip: 'X',
                  onTap: () => _launchUrl('https://x.com/wazenapp?s=11'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'ملاحظة: سيتم فتح تطبيق البريد لإرسال الرسالة.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}