import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  final String chatId;
  final dynamic me; // توافق فقط
  const ChatScreen({super.key, required this.chatId, this.me});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('الدردشة غير متاحة حالياً')),
    );
  }
}
