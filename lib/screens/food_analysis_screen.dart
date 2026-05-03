import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class FoodAnalysisScreen extends StatefulWidget {
  const FoodAnalysisScreen({super.key});

  @override
  State<FoodAnalysisScreen> createState() => _FoodAnalysisScreenState();
}

class _FoodAnalysisScreenState extends State<FoodAnalysisScreen> {
  File? _image;
  bool _isProcessing = false;
  String? _analysisResult;

  Future<void> pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _isProcessing = true;
        _analysisResult = null;
      });

      await Future.delayed(const Duration(seconds: 2)); // مؤقت للتجربة

      // هنا يتم استدعاء الذكاء الاصطناعي لاحقًا لتحليل الصورة
      setState(() {
        _isProcessing = false;
        _analysisResult =
            "🍗 دجاج مشوي\nالسعرات: 250\nبروتين: 30g\nكارب: 10g\nدهون: 8g\nمناسبة لهدفك ✅";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تحليل الوجبة بالصورة")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: pickImage,
              icon: const Icon(Icons.camera_alt),
              label: const Text("التقط صورة للوجبة"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            if (_image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(_image!, height: 200),
              ),
            const SizedBox(height: 20),
            if (_isProcessing) const CircularProgressIndicator(),
            if (_analysisResult != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _analysisResult!,
                  style: const TextStyle(fontSize: 16, height: 1.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
