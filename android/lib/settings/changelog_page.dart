
import 'package:flutter/material.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ما الجديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('• v1.2.0: تحسين الأداء وإصلاح أخطاء.'),
          SizedBox(height: 8),
          Text('• v1.1.0: إضافة مركز المجتمع وصفحة المدربين.'),
          SizedBox(height: 8),
          Text('• v1.0.0: الإصدار الأول.'),
        ],
      ),
    );
  }
}
