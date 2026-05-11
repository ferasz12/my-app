// lib/screens/community_page.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  final List<Map<String, dynamic>> posts = [];
  final TextEditingController _captionController = TextEditingController();
  File? selectedImage;

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked != null) {
      if (!mounted) return;
      setState(() {
        selectedImage = File(picked.path);
      });
    }
  }

  void addPost() {
    if (selectedImage == null || _captionController.text.trim().isEmpty) return;
    setState(() {
      posts.insert(0, {
        'image': selectedImage,
        'caption': _captionController.text.trim(),
        'comments': <String>[]
      });
      selectedImage = null;
      _captionController.clear();
    });
    Navigator.pop(context);
  }

  void showNewPostDialog() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            selectedImage != null
                ? Image.file(
                    selectedImage!,
                    height: 150,
                    cacheWidth: 600,
                    filterQuality: FilterQuality.low,
                  )
                : ElevatedButton.icon(
                    onPressed: pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text("اختر صورة"),
                  ),
            const SizedBox(height: 10),
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(hintText: 'اكتب تعليقك هنا...'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: addPost,
              icon: const Icon(Icons.send),
              label: const Text("نشر"),
            ),
          ],
        ),
      ),
    );
  }

  void showCommentsDialog(List<String> comments) {
    final TextEditingController commentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("التعليقات"),
        content: SizedBox(
          height: 300,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children:
                      comments.map((c) => ListTile(title: Text(c))).toList(),
                ),
              ),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(hintText: "اكتب ردًا"),
              )
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (commentCtrl.text.trim().isNotEmpty) {
                setState(() => comments.add(commentCtrl.text.trim()));
                Navigator.pop(context);
              }
            },
            child: const Text("إرسال"),
          )
        ],
      ),
    ).whenComplete(commentCtrl.dispose);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("مجتمع ميزان"),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            onPressed: showNewPostDialog,
            icon: const Icon(Icons.add_comment),
            tooltip: "نشر جديد",
          )
        ],
      ),
      body: posts.isEmpty
          ? const Center(child: Text("لا توجد منشورات بعد. كن أول من ينشر!"))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post['image'] != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                          child: Image.file(
                              post['image'],
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                              cacheWidth: 900,
                              filterQuality: FilterQuality.low,
                            ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(post['caption'],
                            style: const TextStyle(fontSize: 16)),
                      ),
                      TextButton(
                        onPressed: () => showCommentsDialog(post['comments']),
                        child: Text("💬 ${post['comments'].length} تعليق"),
                      )
                    ],
                  ),
                );
              },
            ),
    );
  }
}
