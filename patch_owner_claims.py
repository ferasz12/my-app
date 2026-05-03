
import os, re, pathlib, sys

ROOT = os.getcwd()

def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()

def write(path, content):
    pathlib.Path(os.path.dirname(path)).mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

def backup(path):
    if not os.path.exists(path): return
    bak = path + ".bak"
    if not os.path.exists(bak):
        with open(path, "rb") as src, open(bak, "wb") as dst:
            dst.write(src.read())

def fix_support_screen():
    rel = "lib/support/support_dashboard_screen.dart"
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        print(f"[skip] {rel} not found")
        return
    backup(path)
    s = read(path)

    # Remove lines starting with \1... and stray \1 tokens
    s = re.sub(r"^\s*\\\d.*?$", "", s, flags=re.M)
    s = s.replace("\\1", "")

    # Ensure import badges_api.dart
    if "shared/badges_api.dart" not in s:
        s = re.sub(r"(import\s+['\"][^'\"]+['\"];\s*)", r"\1import 'package:my_app/shared/badges_api.dart';\n", s, count=1)

    # Ensure dart:io for File used by Image.file
    if "dart:io" not in s:
        s = "import 'dart:io';\n" + s

    # Replace standalone File(path) widget occurrences with Image.file(File(path))
    s = re.sub(r"([^A-Za-z0-9_])File\s*\(\s*([^)]+)\)", r"\1Image.file(File(\2))", s)

    # Declare _isOwner if missing
    if re.search(r"\bbool\s+_isOwner\b", s) is None:
        s = re.sub(r"(class\s+_[A-Za-z0-9_]+\s+extends\s+State<[^\>]+>\s*\{\s*)", r"\1\n  bool _isOwner = false;\n", s, count=1)

    # Replace _myBadge == BadgeType.owner with _isOwner
    s = re.sub(r"_myBadge\s*==\s*BadgeType\.owner", "_isOwner", s)
    s = re.sub(r"BadgeType\.owner\s*==\s*_myBadge", "_isOwner", s)

    write(path, s)
    print(f"[ok] fixed {rel}")

def ensure_badges_api():
    rel = "lib/shared/badges_api.dart"
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        print(f"[skip] {rel} not found; creating minimal file")
        content = """export 'package:my_app/shared/badges.dart';
export 'package:my_app/shared/user_badges_store.dart' show getBadge, setBadge, watchBadge, UserBadgesStore;
import 'package:firebase_auth/firebase_auth.dart';
Future<bool> isOwnerClaimNow({bool forceRefresh = false}) async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return false;
  final r = await u.getIdTokenResult(forceRefresh);
  return (r.claims?['role'] ?? '').toString().toLowerCase() == 'owner';
}
"""
        write(path, content)
        print(f"[ok] created {rel}")
        return

    backup(path)
    s = read(path)
    if "isOwnerClaimNow" not in s:
        s += """

import 'package:firebase_auth/firebase_auth.dart';
Future<bool> isOwnerClaimNow({bool forceRefresh = false}) async {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return false;
  final r = await u.getIdTokenResult(forceRefresh);
  return (r.claims?['role'] ?? '').toString().toLowerCase() == 'owner';
}
"""
    # ensure store export includes watchBadge
    s = re.sub(r"export\s+['\"][^'\"]*user_badges_store\.dart['\"][^;]*;", 
               "export 'package:my_app/shared/user_badges_store.dart' show getBadge, setBadge, watchBadge, UserBadgesStore;", s)

    # ensure badges export present
    if "shared/badges.dart" not in s:
        s = "export 'package:my_app/shared/badges.dart';\n" + s

    write(path, s)
    print(f"[ok] ensured {rel}")

def fix_user_badges_store():
    rel = "lib/shared/user_badges_store.dart"
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        print(f"[skip] {rel} not found; creating minimal store")
        s = """import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'badges.dart';
import 'badges_api.dart' show isOwnerClaimNow;

final _fs = FirebaseFirestore.instance;

BadgeType _from(String s){
  switch (s.toLowerCase()) {
    case 'verified': return BadgeType.verified;
    case 'coach': return BadgeType.coach;
    case 'support': return BadgeType.support;
    case 'admin': return BadgeType.admin;
    case 'owner': return BadgeType.owner;
    case 'vip': return BadgeType.vip;
    default: return BadgeType.none;
  }
}

Future<BadgeType> getBadge(String uid) async {
  final doc = await _fs.collection('users').doc(uid).get();
  final b = (doc.data()?['badge'] ?? '').toString();
  return _from(b);
}

Stream<BadgeType> watchBadge(String uid){
  return _fs.collection('users').doc(uid).snapshots().map((d){
    final b = (d.data()?['badge'] ?? '').toString();
    return _from(b);
  });
}

Future<void> setBadge(String targetUid, BadgeType badge) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) throw StateError('Not signed in');
  final ok = await isOwnerClaimNow(forceRefresh: true);
  if (!ok) throw StateError('Owner-only action');
  if (badge == BadgeType.owner) throw StateError('Cannot assign owner badge from client');
  await _fs.collection('users').doc(targetUid)
    .set({'badge': badge.name}, SetOptions(merge: true));
}

class UserBadgesStore {
  const UserBadgesStore();
  Future<BadgeType> getBadge(String uid) => getBadge(uid);
  Stream<BadgeType> watchBadge(String uid) => watchBadge(uid);
  Future<void> setBadge(String uid, BadgeType b) => setBadge(uid, b);
}
"""
        write(path, s)
        print(f"[ok] created {rel}")
        return

    backup(path)
    s = read(path)
    # Remove stray \1 tokens/lines
    s = re.sub(r"^\s*\\\d.*?$", "", s, flags=re.M)
    s = s.replace("\\1", "")

    # Ensure imports present
    if "badges_api.dart" not in s:
      s = "import 'badges_api.dart';\n" + s
    if "badges.dart" not in s:
      s = "import 'badges.dart';\n" + s
    if "cloud_firestore.dart" not in s:
      s = "import 'package:cloud_firestore/cloud_firestore.dart';\n" + s
    if "firebase_auth.dart" not in s:
      s = "import 'package:firebase_auth/firebase_auth.dart';\n" + s

    # Ensure watchBadge exists
    if "Stream<BadgeType> watchBadge(" not in s:
        s += """

Stream<BadgeType> watchBadge(String uid){
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots().map((d){
    final b = (d.data()?['badge'] ?? '').toString();
    switch (b.toLowerCase()) {
      case 'verified': return BadgeType.verified;
      case 'coach': return BadgeType.coach;
      case 'support': return BadgeType.support;
      case 'admin': return BadgeType.admin;
      case 'owner': return BadgeType.owner;
      case 'vip': return BadgeType.vip;
      default: return BadgeType.none;
    }
  });
}
"""

    # Ensure setBadge guard
    if "Owner-only action" not in s:
        s = re.sub(r"(Future<\s*void\s*>\s*setBadge\s*\([^\)]*\)\s*async\s*\{\s*)",
                   r"\1final ok = await isOwnerClaimNow(forceRefresh: true);\n  if (!ok) throw StateError('Owner-only action');\n  if (badge == BadgeType.owner) throw StateError('Cannot assign owner badge from client');\n",
                   s)

    # Fix any getBadge(me.email) -> getBadge(me.uid)
    s = s.replace("getBadge(me.email)", "getBadge(me.uid)")
    s = re.sub(r"getBadge\(\s*([A-Za-z_][A-Za-z0-9_]*)\.email\s*\)", r"getBadge(\1.uid)", s)

    write(path, s)
    print(f"[ok] fixed {rel}")

def main():
    fix_support_screen()
    ensure_badges_api()
    fix_user_badges_store()
    print("\nAll done. Rebuild your app.")

if __name__ == "__main__":
    main()
