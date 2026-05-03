// lib/support/firestore_posts_repo_adapter.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../community/models.dart';

class FirestorePostsRepoAdapter {
  final _fs = FirebaseFirestore.instance;

  Stream<List<Post>> watchFeed({int limit = 100}) {
    return _fs.collection('posts')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((qs) => qs.docs
          .map((d) {
            final data = d.data();
            // Merge id into data for Post.fromJson()
            final map = {'id': d.id, ...data};
            try {
              return Post.fromJson(map);
            } catch (_) {
              // If mapping fails due to model differences, drop this doc to avoid runtime errors.
              return null;
            }
          })
          .whereType<Post>()
          .toList());
  }

  Future<void> deletePost(String postId) async {
    final ref = _fs.collection('posts').doc(postId);
    for (final sub in const ['comments', 'likes']) {
      final snaps = await ref.collection(sub).get();
      for (final d in snaps.docs) { await d.reference.delete(); }
    }
    await ref.delete();
  }
}
