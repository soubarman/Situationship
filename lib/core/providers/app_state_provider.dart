import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../models/chat_model.dart';
import '../models/comment_model.dart';
import '../models/community_model.dart';
import '../models/notification_model.dart';
import 'firebase_auth_provider.dart';
import 'firestore_provider.dart';

// ─── Auth State ──────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<bool> {
  AuthNotifier() : super(false);

  void login() => state = true;
  void logout() => state = false;
}

final authProvider = StateNotifierProvider<AuthNotifier, bool>(
  (ref) => AuthNotifier(),
);

// ─── User Data Stream ─────────────────────────────────────────────────────────

final userDataStreamProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  final db = firestoreProvider;

  return authState.when(
    data: (user) {
      if (user == null) {
        return Stream.value(null);
      }
      return db.collection('users').doc(user.uid).snapshots().map((doc) {
        if (!doc.exists) {
          final userModel = UserModel(
            id: user.uid,
            name: user.displayName ?? user.email?.split('@').first ?? 'User',
            email: user.email ?? '',
            age: 18,
            avatarUrl: user.photoURL,
            interests: [],
            isVerified: false,
            isOnline: true,
            coins: 100,
          );
          // Fire-and-forget so the stream doesn't hang if network is blocked
          db.collection('users').doc(user.uid).set(userModel.toMap(), SetOptions(merge: true));
          return userModel;
        }
        return UserModel.fromMap(doc.data()!);
      });
    },
    loading: () => const Stream.empty(),
    error: (err, stack) {
      return Stream.value(null);
    },
  );
});

final otherUserProvider = StreamProvider.family<UserModel?, String>((ref, userId) {
  return firestoreProvider.collection('users').doc(userId).snapshots().map((doc) {
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!);
  });
});

// ─── Current User ─────────────────────────────────────────────────────────────

// The Source of Truth: Watches the Firestore stream and provides the current user data.
// Defaults to an empty template if the stream is loading or null.
final currentUserProvider = Provider<UserModel>((ref) {
  final userProfileAsync = ref.watch(userDataStreamProvider);
  final authState = ref.watch(authStateChangesProvider);
  final uid = authState.asData?.value?.uid;

  return userProfileAsync.maybeWhen(
    data: (user) {
      if (user != null) return user;
      // If doc doesn't exist yet, return template with the correct UID
      return UserModel.currentUser.copyWith(id: uid ?? '');
    },
    orElse: () => UserModel.currentUser.copyWith(id: uid ?? ''),
  );
});

// ─── Real-Time Firestore Posts ───────────────────────────────────────────────

const int _postsPageSize = 20;

final postsStreamProvider = StreamProvider<List<PostModel>>((ref) {
  return firestoreProvider
      .collection('posts')
      .orderBy('createdAt', descending: true)
      .limit(_postsPageSize) // Limit to prevent loading all posts
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) => PostModel.fromMap(doc.data())).toList();
      })
      .handleError((err) {
        throw err;
      });
});

// Pagination state
class PostsPaginationNotifier extends StateNotifier<AsyncValue<List<PostModel>>> {
  final Ref ref;
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;

  PostsPaginationNotifier(this.ref) : super(const AsyncValue.loading()) {
    loadInitialPosts();
  }

  bool get hasMore => _hasMore;

  Future<void> loadInitialPosts() async {
    state = const AsyncValue.loading();
    try {
      final snapshot = await firestoreProvider
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(_postsPageSize)
          .get();

      final posts = snapshot.docs.map((doc) => PostModel.fromMap(doc.data())).toList();
      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMore = snapshot.docs.length >= _postsPageSize;
      state = AsyncValue.data(posts);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;

    final currentPosts = state.value ?? [];
    state = AsyncValue.data(currentPosts); // Keep current data while loading more

    try {
      final snapshot = await firestoreProvider
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_postsPageSize)
          .get();

      final newPosts = snapshot.docs.map((doc) => PostModel.fromMap(doc.data())).toList();
      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMore = snapshot.docs.length >= _postsPageSize;

      state = AsyncValue.data([...currentPosts, ...newPosts]);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    _lastDoc = null;
    _hasMore = true;
    await loadInitialPosts();
  }
}

final postsPaginationProvider =
    StateNotifierProvider<PostsPaginationNotifier, AsyncValue<List<PostModel>>>(
  (ref) => PostsPaginationNotifier(ref),
);

class PostsNotifier extends StateNotifier<List<PostModel>> {
  PostsNotifier() : super([]);

  void addPost(PostModel post) {
    state = [post, ...state];
  }

  void toggleLike(String postId, String userId) async {
    // Optimistic update
    state = state.map((p) {
      if (p.id == postId) {
        final likes = List<String>.from(p.likes);
        if (likes.contains(userId)) {
          likes.remove(userId);
        } else {
          likes.add(userId);
        }
        return p.copyWith(likes: likes);
      }
      return p;
    }).toList();
    // Persist to Firestore
    final docRef = firestoreProvider.collection('posts').doc(postId);
    final doc = await docRef.get();
    if (doc.exists) {
      final likes = List<String>.from(doc.data()?['likes'] ?? []);
      if (likes.contains(userId)) {
        likes.remove(userId);
      } else {
        likes.add(userId);
      }
      await docRef.update({'likes': likes});
    }
  }

  void reactToPost(String postId, String userId, String emoji) async {
    // Optimistic update
    state = state.map((p) {
      if (p.id == postId) {
        final newReactions = Map<String, String>.from(p.reactions);
        // Toggle off if same emoji, otherwise set
        if (newReactions[userId] == emoji) {
          newReactions.remove(userId);
        } else {
          newReactions[userId] = emoji;
        }
        return p.copyWith(reactions: newReactions);
      }
      return p;
    }).toList();

    // Persist to Firestore
    final docRef = firestoreProvider.collection('posts').doc(postId);
    final doc = await docRef.get();
    if (doc.exists) {
      final reactions = Map<String, String>.from(doc.data()?['reactions'] ?? {});
      if (reactions[userId] == emoji) {
        reactions.remove(userId);
      } else {
        reactions[userId] = emoji;
      }
      await docRef.update({'reactions': reactions});
    }
  }

  void incrementCommentCount(String postId) {
    firestoreProvider.collection('posts').doc(postId).update({
      'commentCount': FieldValue.increment(1),
    });
  }

  void decrementCommentCount(String postId) {
    firestoreProvider.collection('posts').doc(postId).update({
      'commentCount': FieldValue.increment(-1),
    });
  }

  Future<void> deletePost(String postId) async {
    state = state.where((p) => p.id != postId).toList();
    try {
      await firestoreProvider.collection('posts').doc(postId).delete();
    } catch (e) {
      debugPrint('Failed to delete post: $e');
    }
  }

  Future<void> editPost(
    String postId, {
    required String caption,
    String? mood,
    String? imageUrl,
    String? musicTrack,
    String? musicArtist,
  }) async {
    state = state.map((p) {
      if (p.id == postId) {
        return p.copyWith(
          caption: caption,
          mood: mood,
          imageUrl: imageUrl,
          musicTrack: musicTrack,
          musicArtist: musicArtist,
          isEdited: true,
        );
      }
      return p;
    }).toList();

    try {
      await firestoreProvider.collection('posts').doc(postId).update({
        'caption': caption,
        'mood': mood,
        'imageUrl': imageUrl,
        'musicTrack': musicTrack,
        'musicArtist': musicArtist,
        'isEdited': true,
      });
    } catch (e) {
      debugPrint('Failed to edit post: $e');
    }
  }

  Future<void> togglePinPost(String postId, bool pinState) async {
    // Find the userId of the post being toggled
    String? userId;
    for (var p in state) {
      if (p.id == postId) {
        userId = p.userId;
        break;
      }
    }

    if (pinState && userId != null) {
      // Unpin all other posts of this user locally and in Firestore
      state = state.map((p) {
        if (p.userId == userId && p.id != postId && p.isPinned) {
          firestoreProvider.collection('posts').doc(p.id).update({'isPinned': false}).catchError((e) {
            debugPrint('Failed to unpin other post: $e');
          });
          return p.copyWith(isPinned: false);
        }
        return p;
      }).toList();
    }

    state = state.map((p) {
      if (p.id == postId) {
        return p.copyWith(isPinned: pinState);
      }
      return p;
    }).toList();

    try {
      await firestoreProvider.collection('posts').doc(postId).update({
        'isPinned': pinState,
      });
    } catch (e) {
      debugPrint('Failed to toggle pin post: $e');
    }
  }

  Future<void> updatePostPrivacy(String postId, String privacy) async {
    state = state.map((p) {
      if (p.id == postId) {
        return p.copyWith(privacy: privacy);
      }
      return p;
    }).toList();

    try {
      await firestoreProvider.collection('posts').doc(postId).update({
        'privacy': privacy,
      });
    } catch (e) {
      debugPrint('Failed to update post privacy: $e');
    }
  }
}

final postsProvider = StateNotifierProvider<PostsNotifier, List<PostModel>>(
  (ref) => PostsNotifier(),
);

// ─── Real-Time Firestore Stories ─────────────────────────────────────────────

const int _storiesPageSize = 20;

final storiesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return firestoreProvider
      .collection('stories')
      .where('expiresAt', isGreaterThan: DateTime.now().millisecondsSinceEpoch)
      .orderBy('expiresAt', descending: true)
      .limit(_storiesPageSize) // Limit to prevent loading all stories
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) => doc.data()).toList();
      })
      .handleError((err) {
        throw err;
      });
});

// Paginated stories for infinite scroll
class StoriesPaginationNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;

  StoriesPaginationNotifier() : super(const AsyncValue.loading()) {
    loadInitialStories();
  }

  bool get hasMore => _hasMore;

  Future<void> loadInitialStories() async {
    state = const AsyncValue.loading();
    try {
      final snapshot = await firestoreProvider
          .collection('stories')
          .where('expiresAt', isGreaterThan: DateTime.now().millisecondsSinceEpoch)
          .orderBy('expiresAt', descending: true)
          .limit(_storiesPageSize)
          .get();

      final stories = snapshot.docs.map((doc) => doc.data()).toList();
      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMore = snapshot.docs.length >= _storiesPageSize;
      state = AsyncValue.data(stories);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading) return;

    final currentStories = state.value ?? [];
    state = AsyncValue.data(currentStories);

    try {
      final snapshot = await firestoreProvider
          .collection('stories')
          .where('expiresAt', isGreaterThan: DateTime.now().millisecondsSinceEpoch)
          .orderBy('expiresAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_storiesPageSize)
          .get();

      final newStories = snapshot.docs.map((doc) => doc.data()).toList();
      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMore = snapshot.docs.length >= _storiesPageSize;

      state = AsyncValue.data([...currentStories, ...newStories]);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    _lastDoc = null;
    _hasMore = true;
    await loadInitialStories();
  }
}

final storiesPaginationProvider =
    StateNotifierProvider<StoriesPaginationNotifier, AsyncValue<List<Map<String, dynamic>>>>(
  (ref) => StoriesPaginationNotifier(),
);

// ─── Discovery (Match Queue) ────────────────────────────────────────────────

const int _discoveryPageSize = 30;

// Paginated discovery provider
class DiscoveryNotifier extends StateNotifier<AsyncValue<List<UserModel>>> {
  final Ref ref;
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  String? _currentUserId;

  DiscoveryNotifier(this.ref) : super(const AsyncValue.loading()) {
    // Wait for auth to be ready before loading, then reload on auth changes
    ref.listen<AsyncValue>(authStateChangesProvider, (_, next) {
      if (next.hasValue) {
        _currentUserId = next.asData?.value?.uid;
        _loadInitial();
      }
    }, fireImmediately: true);
  }

  bool get hasMore => _hasMore;

  Future<void> _loadInitial() async {
    // If auth not ready yet, skip
    if (ref.read(authStateChangesProvider).isLoading) return;

    state = const AsyncValue.loading();
    try {
      final snapshot = await firestoreProvider
          .collection('users')
          .limit(_discoveryPageSize)
          .get();

      final following = ref.read(currentUserProvider).following;
      final users = snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data()))
          .where((u) => u.id != _currentUserId)
          .toList();

      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMore = snapshot.docs.length >= _discoveryPageSize;
      state = AsyncValue.data(users);
    } catch (e, st) {
      debugPrint('Discovery load error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || state.isLoading || _currentUserId == null) return;

    final currentUsers = state.value ?? [];
    state = AsyncValue.data(currentUsers);

    try {
      final snapshot = await firestoreProvider
          .collection('users')
          .startAfterDocument(_lastDoc!)
          .limit(_discoveryPageSize)
          .get();

      final following = ref.read(currentUserProvider).following;
      final newUsers = snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data()))
          .where((u) => u.id != _currentUserId)
          .toList();

      _lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMore = snapshot.docs.length >= _discoveryPageSize;

      state = AsyncValue.data([...currentUsers, ...newUsers]);
    } catch (e, st) {
      debugPrint('Discovery loadMore error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    _lastDoc = null;
    _hasMore = true;
    await _loadInitial();
  }
}

final discoveryProvider =
    StateNotifierProvider<DiscoveryNotifier, AsyncValue<List<UserModel>>>(
  (ref) => DiscoveryNotifier(ref),
);

// Legacy compatibility - wraps new paginated provider
class MatchQueueNotifier extends StateNotifier<List<UserModel>> {
  final Ref _ref;

  MatchQueueNotifier(this._ref) : super([]) {
    // Listen to paginated discovery provider
    _ref.listen<AsyncValue<List<UserModel>>>(discoveryProvider, (_, next) {
      next.whenData((users) {
        if (state.isEmpty) {
          state = users;
        } else {
          final currentIds = state.map((u) => u.id).toSet();
          final brandNew = users.where((u) => !currentIds.contains(u.id)).toList();
          if (brandNew.isNotEmpty) {
            state = [...state, ...brandNew];
          }
        }
      });
    }, fireImmediately: true);
  }

  void reset() {
    _ref.read(discoveryProvider.notifier).refresh();
  }

  void removeFirst() {
    if (state.isNotEmpty) state = state.sublist(1);
  }

  void applyFilters({
    required double maxDistance,
    required double minAge,
    required double maxAge,
  }) {
    // Filter current loaded users (for real filtering, use server-side queries)
    state = state.where((u) => u.age >= minAge && u.age <= maxAge).toList();
  }

  bool get hasMore => _ref.read(discoveryProvider).valueOrNull?.isNotEmpty ?? false;

  void loadMore() {
    _ref.read(discoveryProvider.notifier).loadMore();
  }
}

final matchQueueProvider =
    StateNotifierProvider<MatchQueueNotifier, List<UserModel>>(
  (ref) => MatchQueueNotifier(ref),
);

// ─── Feed & Layout State ──────────────────────────────────────────────────────

final feedFilterProvider = StateProvider<String>((ref) => 'all');

final filteredPostsProvider = Provider<List<PostModel>>((ref) {
  final streamPosts = ref.watch(postsStreamProvider).asData?.value ?? [];
  final localPosts = ref.watch(postsProvider);
  final communities = ref.watch(communitiesProvider).asData?.value ?? [];

  // Identify private communities (Admin Approval Required / Private)
  final privateCommunityIds = communities
      .where((c) => c.isOnlyAdminApproved == true)
      .map((c) => c.id)
      .toSet();

  // Merge optimistic local posts with stream posts, preventing duplicates
  final List<PostModel> posts = [];
  final Set<String> seenIds = {};
  
  for (var p in [...localPosts, ...streamPosts]) {
    if (!seenIds.contains(p.id)) {
      posts.add(p);
      seenIds.add(p.id);
    }
  }

  // First level filter: Exclude private community posts entirely from the general feeds
  var result = posts.where((p) {
    if (p.communityId != null && p.communityId!.isNotEmpty) {
      return !privateCommunityIds.contains(p.communityId);
    }
    return true;
  }).toList();

  // Exclude hidden posts
  final hiddenIds = ref.watch(hiddenPostsProvider);
  result = result.where((p) => !hiddenIds.contains(p.id)).toList();

  final filter = ref.watch(feedFilterProvider);

  // Second level filter: Tab specific rules
  if (filter == 'all') {
    // Standard feed only: completely exclude any posts belonging to a community
    result = result.where((p) => p.communityId == null || p.communityId!.isEmpty).toList();
  } else if (filter == 'following') {
    // Show only posts from users the current user follows
    final currentUser = ref.watch(currentUserProvider);
    result = result.where((p) => currentUser.following.contains(p.userId)).toList();
  } else if (filter == 'communities') {
    // Show only community posts (which are public / not private)
    result = result.where((p) => p.communityId != null && p.communityId!.isNotEmpty).toList();
  }

  // Sort results
  if (filter == 'trending') {
    // Trending: Sort descending by combined likes, reactions, and comments
    result.sort((a, b) {
      final scoreA = a.likes.length + a.commentCount + a.reactions.length;
      final scoreB = b.likes.length + b.commentCount + b.reactions.length;
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }
      return b.createdAt.compareTo(a.createdAt); // Secondary tie-breaker by date
    });
  } else {
    // Always newest-first for other feeds (pinned posts should not float to top of global feed)
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  return result;
});

// Whether the posts stream is still in its initial loading state
final postsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(postsStreamProvider).isLoading;
});

// ─── Comments & Messaging (Mocking for now to avoid logic bloat) ───────────────

class CommentsNotifier extends StateNotifier<List<CommentModel>> {
  final String postId;

  CommentsNotifier(this.postId) : super([]) {
    firestoreProvider
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      try {
        state = snap.docs.map((doc) => CommentModel.fromMap(doc.data())).toList();
      } catch (e) {
        print('Error parsing comments: $e');
      }
    }, onError: (e) {
      print('Comments listener error: $e');
    });
  }

  Future<void> addComment(CommentModel comment) async {
    // Optimistic update
    state = [...state, comment];
    
    try {
      await firestoreProvider
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(comment.id)
          .set(comment.toMap());
    } catch (e) {
      print('Failed to add comment: $e');
      // Rollback if it failed
      state = state.where((c) => c.id != comment.id).toList();
    }
  }

  void toggleLike(String commentId, String userId) async {
    final docRef = firestoreProvider
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);
        
    final doc = await docRef.get();
    if (doc.exists) {
      final likes = List<String>.from(doc.data()?['likes'] ?? []);
      if (likes.contains(userId)) {
        likes.remove(userId);
      } else {
        likes.add(userId);
      }
      await docRef.update({'likes': likes});
    }
  }

  Future<void> deleteComment(String commentId) async {
    // Optimistic update
    state = state.where((c) => c.id != commentId).toList();
    
    try {
      await firestoreProvider
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .delete();
    } catch (e) {
      debugPrint('Failed to delete comment: $e');
    }
  }
}

final commentsProvider =
    StateNotifierProvider.family<CommentsNotifier, List<CommentModel>, String>(
  (ref, postId) => CommentsNotifier(postId),
);

class ChatsNotifier extends StateNotifier<List<ChatModel>> {
  final Ref ref;
  StreamSubscription? _subscription;

  ChatsNotifier(this.ref) : super([]) {
    // Use ref.listen to react to auth changes reliably
    ref.listen<AsyncValue>(authStateChangesProvider, (_, next) {
      final user = next.asData?.value;
      if (user != null) {
        setupListener(user.uid);
      } else {
        _subscription?.cancel();
        state = [];
      }
    }, fireImmediately: true);
  }

  void setupListener(String uid) {
    _subscription?.cancel();
    _subscription = firestoreProvider
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final List<ChatModel> validChats = [];
      for (var doc in snap.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data());
          
          // ─── Dynamic Other-User Details Resolution ───
          if (data.containsKey('senderId') && data.containsKey('receiverId')) {
            if (uid == data['senderId']) {
              data['otherUserId'] = data['receiverId'];
              data['otherUserName'] = data['receiverName'] ?? 'User';
              data['otherUserAvatar'] = data['receiverAvatar'];
            } else {
              data['otherUserId'] = data['senderId'];
              data['otherUserName'] = data['senderName'] ?? 'User';
              data['otherUserAvatar'] = data['senderAvatar'];
            }
          } else {
            // Backward compatibility swap if static otherUserId equals the current user
            if (data['otherUserId'] == uid) {
              final participants = List<String>.from(data['participants'] ?? []);
              final correctOtherId = participants.firstWhere((p) => p != uid, orElse: () => uid);
              data['otherUserId'] = correctOtherId;
              data['otherUserName'] = 'Situationship Match';
            }
          }

          // If it is a confession and the current user is the receiver, hide sender identity unless revealed
          final isConf = (data['isConfession'] ?? false) || 
                         (data['lastMessage'] ?? '').toString().toLowerCase().contains('confession');
          final revealSt = data['revealStatus'];
          if (isConf && uid != data['senderId'] && revealSt != 'revealed') {
            data['otherUserName'] = 'ANONYMOUS';
            data['otherUserAvatar'] = 'anonymous_mask';
            data['isConfession'] = true;
          }

          validChats.add(ChatModel.fromMap(data));
        } catch (e) {
          print('Error parsing chat ${doc.id}: $e');
        }
      }
      validChats.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      state = validChats;
    }, onError: (e) {
      print('Chats listener error: $e');
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addChat(ChatModel chat, String currentUserId) async {
    final chatMap = chat.toMap();
    chatMap['participants'] = [currentUserId, chat.otherUserId];
    await firestoreProvider.collection('chats').doc(chat.id).set(chatMap);
  }

  void updateChatStatus(String chatId, String status) {
    final Map<String, dynamic> updates = {'status': status};
    if (status == 'accepted') {
      updates['acceptedAt'] = DateTime.now().millisecondsSinceEpoch;
    }
    firestoreProvider.collection('chats').doc(chatId).update(updates);
  }

  void markRead(String chatId) {
    firestoreProvider.collection('chats').doc(chatId).update({'unreadCount': 0});
  }

  void updateLastMessage(String chatId, String message, DateTime time) {
    firestoreProvider.collection('chats').doc(chatId).update({
      'lastMessage': message,
      'lastMessageTime': time.millisecondsSinceEpoch,
    });
  }

  Future<void> deleteChat(String chatId) async {
    // Optimistic local state update
    state = state.where((c) => c.id != chatId).toList();

    try {
      final db = firestoreProvider;
      
      // 1. Delete all messages inside subcollection
      final messagesSnap = await db.collection('chats').doc(chatId).collection('messages').get();
      final batch = db.batch();
      for (var doc in messagesSnap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // 2. Delete the chat document
      await db.collection('chats').doc(chatId).delete();
    } catch (e) {
      debugPrint('Failed to delete chat: $e');
    }
  }
}

final chatsProvider = StateNotifierProvider<ChatsNotifier, List<ChatModel>>(
  (ref) => ChatsNotifier(ref),
);

class ChatMessagesNotifier extends StateNotifier<List<MessageModel>> {
  final String chatId;

  ChatMessagesNotifier(this.chatId) : super([]) {
    firestoreProvider
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      state = snap.docs.map((doc) => MessageModel.fromMap(doc.data())).toList();
    }, onError: (e) {
      print('Messages listener error: $e');
    });
  }

  Future<void> addMessage(MessageModel message) async {
    try {
      await firestoreProvider
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(message.id)
          .set(message.toMap());
    } catch (e) {
      print('Firebase error adding message: $e');
      throw e;
    }
  }

  Future<void> addReply(String text, String senderId) async {
    final reply = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: senderId,
      text: text,
      createdAt: DateTime.now(),
      isRead: false,
    );
    try {
      await firestoreProvider
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(reply.id)
          .set(reply.toMap());
    } catch (e) {
      print('Firebase error adding reply: $e');
      throw e;
    }
  }
}

final chatMessagesNotifierProvider = StateNotifierProvider.family<
    ChatMessagesNotifier, List<MessageModel>, String>(
  (ref, chatId) => ChatMessagesNotifier(chatId),
);

final isTypingProvider = StateProvider<bool>((ref) => false);
const List<String> autoReplies = [
  "Haha that's so cute 😊",
  'Okay wow, I love that ✨',
  "No way!! That's literally me 😂",
  'Ugh yes, finally someone gets it 🙏',
];

// ─── Social Actions (Follow/Unfollow) ────────────────────────────────────────

class SocialNotifier extends StateNotifier<bool> {
  SocialNotifier() : super(false);

  Future<void> toggleFollow({
    required String currentUserId,
    required String targetUserId,
    required bool isCurrentlyFollowing,
  }) async {
    try {
      final batch = firestoreProvider.batch();
      final currentUserRef = firestoreProvider.collection('users').doc(currentUserId);
      final targetUserRef = firestoreProvider.collection('users').doc(targetUserId);

      if (isCurrentlyFollowing) {
        // Unfollow
        batch.update(currentUserRef, {
          'following': FieldValue.arrayRemove([targetUserId])
        });
        batch.update(targetUserRef, {
          'followers': FieldValue.arrayRemove([currentUserId])
        });
      } else {
        // Follow
        batch.update(currentUserRef, {
          'following': FieldValue.arrayUnion([targetUserId])
        });
        batch.update(targetUserRef, {
          'followers': FieldValue.arrayUnion([currentUserId])
        });
      }

      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> toggleCommunityJoin({
    required String currentUserId,
    required String communityId,
    required bool isCurrentlyJoined,
    required bool isOnlyAdminApproved,
    required List<String> pendingApprovals,
  }) async {
    if (currentUserId.isEmpty) {
      throw Exception('User not logged in — cannot join community.');
    }
    if (communityId.isEmpty) {
      throw Exception('Invalid community ID.');
    }
    try {
      final db = firestoreProvider;
      final userRef = db.collection('users').doc(currentUserId);
      final communityRef = db.collection('communities').doc(communityId);
      final batch = db.batch();

      if (isCurrentlyJoined) {
        batch.set(userRef, {
          'joinedCommunities': FieldValue.arrayRemove([communityId])
        }, SetOptions(merge: true));
        batch.set(communityRef, {
          'memberCount': FieldValue.increment(-1),
          'memberAvatars': FieldValue.arrayRemove([currentUserId]),
        }, SetOptions(merge: true));
      } else {
        if (pendingApprovals.contains(currentUserId)) {
          // Cancel pending request
          batch.set(communityRef, {
            'pendingApprovals': FieldValue.arrayRemove([currentUserId]),
          }, SetOptions(merge: true));
        } else if (isOnlyAdminApproved) {
          // Add to pending approvals
          batch.set(communityRef, {
            'pendingApprovals': FieldValue.arrayUnion([currentUserId]),
          }, SetOptions(merge: true));
        } else {
          // Join instantly
          batch.set(userRef, {
            'joinedCommunities': FieldValue.arrayUnion([communityId])
          }, SetOptions(merge: true));
          batch.set(communityRef, {
            'memberCount': FieldValue.increment(1),
            'memberAvatars': FieldValue.arrayUnion([currentUserId]),
          }, SetOptions(merge: true));
        }
      }
      await batch.commit();
    } catch (e) {
      print('Error toggling community join: $e');
      rethrow; // Let UI handle it
    }
  }

  Future<bool> spendCoins({
    required String userId,
    required int amount,
  }) async {
    try {
      final userRef = firestoreProvider.collection('users').doc(userId);
      final doc = await userRef.get();
      if (!doc.exists) return false;

      final currentCoins = doc.data()?['coins'] ?? 100;
      if (currentCoins < amount) return false;

      await userRef.update({
        'coins': currentCoins - amount,
      });
      return true;
    } catch (e) {
      print('Error spending coins: $e');
      return false;
    }
  }
}

final socialProvider = StateNotifierProvider<SocialNotifier, bool>((ref) {
  return SocialNotifier();
});

// ─── Discovery Filters State ─────────────────────────────────────────────────

final filterMinAgeProvider = StateProvider<double>((ref) => 18);
final filterMaxAgeProvider = StateProvider<double>((ref) => 35);
final filterMaxDistanceProvider = StateProvider<double>((ref) => 50);

// ─── Communities Provider ────────────────────────────────────────────────────

/// One-shot seeder — call this once from app init or on first load.
/// Uses set(merge:true) so it won't overwrite real memberCount data.
Future<void> seedDefaultCommunities() async {
  final db = firestoreProvider;
  final snapshot = await db.collection('communities').limit(1).get();
  if (snapshot.docs.isNotEmpty) return; // Already seeded

  final batch = db.batch();
  for (final comm in CommunityModel.defaults) {
    final docRef = db.collection('communities').doc(comm.id);
    batch.set(docRef, comm.toMap(), SetOptions(merge: true));
  }
  await batch.commit();
}

final communitiesProvider = StreamProvider<List<CommunityModel>>((ref) {
  final db = firestoreProvider;

  // Seed communities once (fire-and-forget) without blocking the stream
  seedDefaultCommunities().catchError((e) => debugPrint('Community seed error: $e'));

  return db.collection('communities').snapshots().map((snapshot) {
    if (snapshot.docs.isEmpty) {
      // Return defaults while Firestore write is in-flight
      final sorted = List<CommunityModel>.from(CommunityModel.defaults);
      sorted.sort((a, b) => a.name.compareTo(b.name));
      return sorted;
    }
    final list = snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return CommunityModel.fromMap(data);
    }).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  });
});

final communityPostsStreamProvider = StreamProvider.family<List<PostModel>, String>((ref, communityId) {
  return firestoreProvider
      .collection('posts')
      .where('communityId', isEqualTo: communityId)
      .snapshots()
      .map((snapshot) {
        final list = snapshot.docs.map((doc) => PostModel.fromMap(doc.data())).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
});

final communityMessagesStreamProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, communityId) {
  return firestoreProvider
      .collection('communities')
      .doc(communityId)
      .collection('messages')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
});

Future<void> sendCommunityMessage({
  required String communityId,
  required String senderId,
  required String senderName,
  required String? senderAvatar,
  required String text,
}) async {
  if (text.trim().isEmpty) return;
  final db = firestoreProvider;
  final messageId = db.collection('communities').doc(communityId).collection('messages').doc().id;
  await db.collection('communities').doc(communityId).collection('messages').doc(messageId).set({
    'id': messageId,
    'senderId': senderId,
    'senderName': senderName,
    'senderAvatar': senderAvatar,
    'text': text.trim(),
    'createdAt': DateTime.now().millisecondsSinceEpoch,
    'type': 'text',
  });
}

final notificationsStreamProvider = StreamProvider<List<NotificationModel>>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  final uid = authState.asData?.value?.uid;
  if (uid == null) return Stream.value([]);

  return firestoreProvider
      .collection('notifications')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map((snapshot) {
        final list = snapshot.docs.map((doc) => NotificationModel.fromMap(doc.data())).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
});

Future<void> sendNotification({
  required String userId,
  required String senderId,
  required String senderName,
  required String? senderAvatar,
  required String type,
  required String title,
  required String body,
}) async {
  final db = firestoreProvider;
  final notificationId = db.collection('notifications').doc().id;
  final notification = NotificationModel(
    id: notificationId,
    userId: userId,
    senderId: senderId,
    senderName: senderName,
    senderAvatar: senderAvatar,
    type: type,
    title: title,
    body: body,
    createdAt: DateTime.now(),
    isRead: false,
  );
  await db.collection('notifications').doc(notificationId).set(notification.toMap());
}

Future<void> markNotificationAsRead(String notificationId) async {
  await firestoreProvider.collection('notifications').doc(notificationId).update({
    'isRead': true,
  });
}

Future<void> markAllNotificationsAsRead(String userId) async {
  final db = firestoreProvider;
  final snapshots = await db.collection('notifications').where('userId', isEqualTo: userId).where('isRead', isEqualTo: false).get();
  final batch = db.batch();
  for (var doc in snapshots.docs) {
    batch.update(doc.reference, {'isRead': true});
  }
  await batch.commit();
}

final hiddenPostsProvider = StateProvider<List<String>>((ref) => []);

