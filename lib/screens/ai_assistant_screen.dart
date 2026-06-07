import 'package:flutter/material.dart';

import '../shared/premium_gate.dart';
import '../shared/premium_feature.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  _AiAssistantScreenState createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  String response = "";
  bool loading = false;

  void askAI(String question) async {
    setState(() {
      loading = true;
      response = "";
    });

    // محاكاة رد الذكاء الاصطناعي
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      loading = false;
      response =
          "🤖 الذكاء الاصطناعي: يبدو أن أكلك يحتوي على تنوع جيد! استمر! 💪";
    });

    // إذا فعلياً عندك API:
    // final res = await http.post(... إلى ChatGPT أو غيره)
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumGate(
      feature: PremiumFeature.smartCoach,
      child: Scaffold(
      appBar: AppBar(title: const Text("اسأل الذكاء الاصطناعي")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: "اكتب سؤالك...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  askAI(_controller.text.trim());
                }
              },
              child: const Text("إرسال"),
            ),
            const SizedBox(height: 24),
            if (loading) const CircularProgressIndicator(),
            if (response.isNotEmpty)
              Text(
                response,
                style: const TextStyle(fontSize: 16, color: Colors.deepPurple),
              ),
          ],
        ),
      ),
    ),
    );
  }
}
