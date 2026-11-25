import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized Firestore instance - use this instead of creating new instances
final firestoreProvider = FirebaseFirestore.instance;

/// Convenience extension for common Firestore operations
extension FirestoreHelpers on FirebaseFirestore {
  /// Get a reference to the users collection
  CollectionReference<Map<String, dynamic>> get users => collection('users');

  /// Get a reference to the posts collection
  CollectionReference<Map<String, dynamic>> get posts => collection('posts');

  /// Get a reference to the stories collection
  CollectionReference<Map<String, dynamic>> get stories => collection('stories');

  /// Get a reference to the chats collection
  CollectionReference<Map<String, dynamic>> get chats => collection('chats');
}
