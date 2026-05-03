// lib/core/firestore/user_schema.dart
//
// مصدر واحد لمسارات ومفاتيح Firestore الخاصة بالمستخدم.
// الهدف: كل صفحات التطبيق تقرأ/تكتب من نفس الأماكن وبنفس المفاتيح.

class UserPaths {
  static String userDoc(String uid) => 'users/$uid';

  // subcollections/docs
  static String onboarding(String uid) => 'users/$uid/meta/onboarding';
  static String flags(String uid) => 'users/$uid/meta/flags';
  static String metrics(String uid) => 'users/$uid/meta/metrics';
  static String prefs(String uid) => 'users/$uid/meta/prefs';

  static String profileBasic(String uid) => 'users/$uid/profile/basic';
  static String profileSocial(String uid) => 'users/$uid/profile/social';

  static String usernameReservation(String handle) => 'usernames/$handle';
}

class UserKeys {
  // users/{uid}
  static const email = 'email';
  static const username = 'username';
  static const usernameLower = 'username_lower';
  static const displayName = 'displayName';
  static const photoUrl = 'photoUrl';
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';
  static const role = 'role';
  static const isBanned = 'isBanned';

  // meta/onboarding
  static const onboardingStep = 'onboardingStep';
  static const onboardingDone = 'onboardingDone';
  static const lifestyleScore = 'lifestyleScore';
  static const lifestyle = 'lifestyle';
  static const userInput = 'userInput';
  static const setGoal = 'setGoal';

  // meta/flags
  static const lifestyleAssessmentCompleted = 'lifestyleAssessmentCompleted';
  static const userDataEntered = 'userDataEntered';

  // meta/metrics
  static const activityFactor = 'activityFactor';
  static const maintenanceCalories = 'maintenanceCalories';
  static const caloriesNeeded = 'caloriesNeeded';
  static const protein = 'protein';
  static const carbs = 'carbs';
  static const fat = 'fat';

  // usernames/{handle}
  static const ownerUid = 'ownerUid';
}
