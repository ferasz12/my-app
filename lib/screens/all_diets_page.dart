import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/diet_model.dart';
import '../providers/diet_provider.dart';
import 'regimen_screen.dart';

class AllDietsPage extends StatelessWidget {
  const AllDietsPage({super.key});

  List<DietModel> getAllUniqueDiets() {
    final Map<String, List<DietModel>> allGoalsAndDiets = {
      'إنقاص الوزن': [
        DietModel(
            title: 'رجيم السعرات المنخفضة',
            description: 'يساعدك على تقليل السعرات بذكاء.'),
        DietModel(
            title: 'رجيم الكيتو',
            description: 'يعتمد على الدهون الصحية وتقليل الكربوهيدرات.'),
        DietModel(
            title: 'الصيام المتقطع',
            description: 'نمط غذائي يعتمد على أوقات محددة للأكل.'),
        DietModel(
            title: 'رجيم اللو كارب',
            description: 'يقلل من الكربوهيدرات لزيادة حرق الدهون.')
      ],
      'زيادة الوزن': [
        DietModel(
            title: 'رجيم عالي السعرات',
            description: 'مصمم لزيادة الوزن بشكل صحي.'),
        DietModel(
            title: 'رجيم عالي البروتين',
            description: 'يساعد على بناء الكتلة العضلية.'),
        DietModel(
            title: 'رجيم بناء العضلات',
            description: 'يدعم التمارين والتغذية لزيادة العضلات.')
      ],
      'الحفاظ على الوزن': [
        DietModel(
            title: 'رجيم متوازن',
            description: 'يحافظ على استقرار الوزن والصحة.'),
        DietModel(
            title: 'رجيم البحر الأبيض المتوسط',
            description: 'غني بالخضار والدهون الصحية.'),
        DietModel(
            title: 'رجيم السعرات المحسوبة',
            description: 'يركز على التوازن الدقيق في السعرات.')
      ],
      'بناء العضلات': [
        DietModel(
            title: 'رجيم عالي البروتين',
            description: 'يوفر الكمية الكافية لبناء العضلات.'),
        DietModel(title: 'رجيم رياضي', description: 'مصمم لدعم الأداء البدني.'),
        DietModel(
            title: 'رجيم السعرات المرتفعة',
            description: 'يدعم النمو العضلي بكميات طاقة أكبر.')
      ],
      'تحسين اللياقة العامة': [
        DietModel(
            title: 'رجيم متوازن', description: 'يدعم النشاط والطاقة اليومية.'),
        DietModel(
            title: 'رجيم رياضي', description: 'مصمم لتحسين الأداء والقدرة.'),
        DietModel(
            title: 'رجيم عالي الطاقة',
            description: 'غني بالعناصر المحفزة للطاقة.')
      ],
      'خفض الدهون': [
        DietModel(
            title: 'رجيم الكيتو',
            description: 'يركز على حرق الدهون باستخدام الدهون.'),
        DietModel(
            title: 'رجيم اللو كارب',
            description: 'يقلل الكربوهيدرات لحرق أسرع للدهون.'),
        DietModel(
            title: 'الصيام المتقطع', description: 'يساهم في تحسين حرق الدهون.')
      ],
      'الصيام المتقطع': [
        DietModel(
            title: 'نظام 16:8',
            description: 'صيام 16 ساعة وتناول الطعام خلال 8 ساعات.'),
        DietModel(
            title: 'نظام 5:2', description: 'أيام صيام خفيفة وأيام طعام عادي.'),
        DietModel(
            title: 'رجيم منخفض الكربوهيدرات',
            description: 'يساعد الصيام في خفض السكر والوزن.')
      ],
      'نمط حياة صحي': [
        DietModel(
            title: 'رجيم متوازن', description: 'يغطي جميع العناصر الغذائية.'),
        DietModel(
            title: 'رجيم نباتي', description: 'يعتمد على مصادر نباتية صحية.'),
        DietModel(
            title: 'رجيم البحر المتوسط',
            description: 'غني بالخضار والدهون المفيدة.'),
        DietModel(
            title: 'رجيم خالٍ من المعالجات', description: 'بدون أطعمة مصنعة.')
      ],
      'خفض ضغط الدم': [
        DietModel(title: 'رجيم DASH', description: 'صمم خصيصًا لخفض ضغط الدم.'),
        DietModel(
            title: 'رجيم البحر الأبيض المتوسط',
            description: 'مفيد لصحة القلب.'),
        DietModel(
            title: 'رجيم منخفض الصوديوم',
            description: 'يقلل من احتباس السوائل والضغط.')
      ],
      'زيادة النشاط اليومي': [
        DietModel(
            title: 'رجيم عالي الطاقة',
            description: 'يدعم النشاط المكثف طوال اليوم.'),
        DietModel(
            title: 'رجيم متوازن', description: 'يمنحك الطاقة دون تحميل زائد.'),
        DietModel(title: 'رجيم رياضي', description: 'مصمم لأداء بدني أعلى.')
      ],
      'رفع الطاقة والحيوية': [
        DietModel(
            title: 'رجيم غني بالفيتامينات',
            description: 'يركز على العناصر المحفزة للطاقة.'),
        DietModel(
            title: 'رجيم متكامل', description: 'يغطي احتياجك من العناصر كلها.'),
        DietModel(
            title: 'رجيم قليل السكريات',
            description: 'لثبات الطاقة دون ارتفاعات وانخفاضات.')
      ],
      'تحسين الصحة العامة': [
        DietModel(title: 'رجيم متوازن', description: 'يدعم الجسم بالكامل.'),
        DietModel(
            title: 'رجيم نباتي', description: 'يحسن الصحة القلبية والهضم.'),
        DietModel(
            title: 'رجيم البحر الأبيض المتوسط',
            description: 'ثبتت فائدته العامة.'),
        DietModel(
            title: 'رجيم خالٍ من الدهون المتحولة',
            description: 'يقلل المخاطر الصحية.')
      ],
      'ضبط مستوى السكر': [
        DietModel(
            title: 'رجيم منخفض السكر',
            description: 'يتحكم في مستوى السكر في الدم.'),
        DietModel(
            title: 'رجيم اللو كارب',
            description: 'يساعد في تحسين حساسية الإنسولين.'),
        DietModel(title: 'رجيم مخصص للسكري', description: 'مصمم لمرضى السكري.')
      ],
      'اتباع رجيم نباتي': [
        DietModel(
            title: 'رجيم نباتي صارم',
            description: 'يبتعد كليًا عن المنتجات الحيوانية.'),
        DietModel(
            title: 'رجيم نباتي متوازن',
            description: 'يغطي احتياجك من مصادر نباتية.'),
        DietModel(
            title: 'رجيم نباتي عالي البروتين',
            description: 'لمن يريد بناء جسم نباتيًا.')
      ]
    };

    final allDiets = allGoalsAndDiets.values.expand((e) => e).toList();
    final unique = <String, DietModel>{};
    for (var diet in allDiets) {
      unique[diet.title] = diet;
    }
    return unique.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final diets = getAllUniqueDiets();
    return Scaffold(
      appBar: AppBar(title: const Text('جميع الأنظمة الغذائية')),
      body: ListView.builder(
        itemCount: diets.length,
        itemBuilder: (context, index) {
          final diet = diets[index];
          return Card(
            margin: const EdgeInsets.all(10),
            child: ListTile(
              title: Text(diet.title),
              subtitle: Text(diet.description ?? ''),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Provider.of<DietProvider>(context, listen: false)
                    .selectDiet(diet);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => RegimenScreen()),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
