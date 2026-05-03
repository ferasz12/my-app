
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});
  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  String lang = 'ar';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => lang = p.getString('app_lang') ?? 'ar');
  }

  Future<void> _save(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('app_lang', value);
    setState(() => lang = value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير اللغة (قد يتطلب إعادة تشغيل)')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اللغة')),
      body: Column(
        children: [
          RadioListTile<String>(
            value: 'ar',
            groupValue: lang,
            onChanged: (v) => _save(v!),
            title: const Text('العربية'),
          ),
          RadioListTile<String>(
            value: 'en',
            groupValue: lang,
            onChanged: (v) => _save(v!),
            title: const Text('English'),
          ),
        ],
      ),
    );
  }
}
