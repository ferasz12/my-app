import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class FontSizePage extends StatelessWidget {
  const FontSizePage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentSize = themeProvider.fontSize;

    return Scaffold(
      appBar: AppBar(title: const Text('حجم الخط')),
      body: Column(
        children: [
          RadioListTile<String>(
            title: const Text('صغير'),
            value: 'صغير',
            groupValue: currentSize,
            onChanged: (value) {
              if (value != null) themeProvider.updateFontSize(value);
            },
          ),
          RadioListTile<String>(
            title: const Text('متوسط'),
            value: 'متوسط',
            groupValue: currentSize,
            onChanged: (value) {
              if (value != null) themeProvider.updateFontSize(value);
            },
          ),
          RadioListTile<String>(
            title: const Text('كبير'),
            value: 'كبير',
            groupValue: currentSize,
            onChanged: (value) {
              if (value != null) themeProvider.updateFontSize(value);
            },
          ),
        ],
      ),
    );
  }
}
