// lib/screens/goal_tab_wrapper.dart
import 'package:flutter/material.dart';
import './set_goal_page.dart'; // نفس المجلد: lib/screens/

/// يغلف صفحة تحديد الهدف كي تُعرض داخل تبويب "بياناتي"
/// ويحافظ على حالتها عند التنقل بين التبويبات.
class GoalTabWrapper extends StatefulWidget {
  const GoalTabWrapper({super.key});

  @override
  State<GoalTabWrapper> createState() => _GoalTabWrapperState();
}

class _GoalTabWrapperState extends State<GoalTabWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // نستخدم الوضع المضمّن حتى لا يظهر AppBar ولا يحصل تنقل بعد الحفظ
    return const SetGoalPage(embedded: true);
  }
}
