import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/data/wazen_identity_store.dart';

class UserSession {
  static Future<void> login(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await WazenIdentityStore.syncFromFirebaseUser(user, prefs: prefs);
    } else {
      final clean = email.trim().toLowerCase();
      await prefs.setString(WazenIdentityStore.kCurrentEmail, clean);
      await prefs.setString(WazenIdentityStore.kCurrentEmailAddress, clean);
      await prefs.setString(WazenIdentityStore.kCurrentStorageKey, clean);
    }
  }

  static Future<void> logout() async {
    await WazenIdentityStore.clearIdentity();
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  static Future<String?> currentEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(WazenIdentityStore.kCurrentEmailAddress) ??
        prefs.getString(WazenIdentityStore.kCurrentEmail);
  }
}
