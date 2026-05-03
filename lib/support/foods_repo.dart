
import 'package:cloud_firestore/cloud_firestore.dart';

class FoodsRepo {
  final FirebaseFirestore db;
  FoodsRepo(this.db);

  Stream<QuerySnapshot<Map<String, dynamic>>> foodsStream() =>
      db.collection('foods').orderBy('name').snapshots();
}
