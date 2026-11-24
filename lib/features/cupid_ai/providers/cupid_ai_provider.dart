import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:situationship/core/models/user_model.dart';
import 'package:situationship/core/providers/app_state_provider.dart';
import 'package:situationship/core/providers/firestore_provider.dart';
import 'package:situationship/core/ai/on_device_nlu_engine.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/services/like_service.dart';

class CupidChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final List<CupidMatchResult> matches;
  final NLUIntentResult? parsedIntent;
  final bool isThinking;

  const CupidChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.matches = const [],
    this.parsedIntent,
    this.isThinking = false,
  });

  CupidChatMessage copyWith({
    String? id,
    bool? isUser,
    String? text,
    DateTime? timestamp,
    List<CupidMatchResult>? matches,
    NLUIntentResult? parsedIntent,
    bool? isThinking,
  }) {
    return CupidChatMessage(
      id: id ?? this.id,
      isUser: isUser ?? this.isUser,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      matches: matches ?? this.matches,
      parsedIntent: parsedIntent ?? this.parsedIntent,
      isThinking: isThinking ?? this.isThinking,
    );
  }
}

class CupidAIState {
  final List<CupidChatMessage> messages;
  final bool isThinking;
  final List<String> suggestedChips;
  final Set<String> actionedUserIds; // users liked/superliked in session
  final Set<String> shownUserIds; // real users already presented in this conversation
  final NLUIntentResult? lastActiveIntent; // last non-pagination intent

  const CupidAIState({
    required this.messages,
    this.isThinking = false,
    this.suggestedChips = const [
      'Artistic & Creative',
      'Indie & Vinyl Records',
      'Cozy Coffee & Books',
      'Night Owl Vibes',
      'Spontaneous Road Trips',
      'Meaningful Connection',
      'Non-Smoker',
    ],
    this.actionedUserIds = const {},
    this.shownUserIds = const {},
    this.lastActiveIntent,
  });

  CupidAIState copyWith({
    List<CupidChatMessage>? messages,
    bool? isThinking,
    List<String>? suggestedChips,
    Set<String>? actionedUserIds,
    Set<String>? shownUserIds,
    NLUIntentResult? lastActiveIntent,
  }) {
    return CupidAIState(
      messages: messages ?? this.messages,
      isThinking: isThinking ?? this.isThinking,
      suggestedChips: suggestedChips ?? this.suggestedChips,
      actionedUserIds: actionedUserIds ?? this.actionedUserIds,
      shownUserIds: shownUserIds ?? this.shownUserIds,
      lastActiveIntent: lastActiveIntent ?? this.lastActiveIntent,
    );
  }
}

class CupidAINotifier extends StateNotifier<CupidAIState> {
  final Ref ref;
  final VibeMatrixMatcher _matcher = VibeMatrixMatcher();
  int _responseVariantIndex = 0;

  CupidAINotifier(this.ref)
      : super(CupidAIState(messages: [
          CupidChatMessage(
            id: 'init_welcome',
            isUser: false,
            text:
                "Welcome to Cupid Concierge 🍸\n\nTell me who you're hoping to meet — their vibe, passions, music taste, or what kind of energy makes you tick. I'll curate real profiles for you.",
            timestamp: DateTime.now(),
          )
        ]));

  /// Sends a conversational query and runs pure on-device matching over REAL users
  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    final userMsg = CupidChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      isUser: true,
      text: query,
      timestamp: DateTime.now(),
    );

    final thinkingMsgId = 'cupid_thinking_${DateTime.now().millisecondsSinceEpoch}';
    final thinkingMsg = CupidChatMessage(
      id: thinkingMsgId,
      isUser: false,
      text: 'Scanning real profiles in your community...',
      timestamp: DateTime.now(),
      isThinking: true,
    );

    // Update state with user message + thinking indicator
    state = state.copyWith(
      messages: [...state.messages, userMsg, thinkingMsg],
      isThinking: true,
    );

    // 1. Run Pure On-Device NLU Parsing
    final intent = OnDeviceNLUEngine.parse(query);

    // If query is a continuation/pagination request ("is there no more", "show more", "anyone else", "do we have any other profiles"),
    // inherit the last active intent to preserve user's vibe context.
    final effectiveIntent = (intent.isMoreOrContinuation && state.lastActiveIntent != null)
        ? state.lastActiveIntent!
        : intent;

    // 2. Fetch candidate pool (100% REAL users from Firestore and in-memory queue)
    final currentUser = ref.read(currentUserProvider);
    final candidates = await _getCandidates(currentUser.id);

    // 3. Run Pure On-Device VibeMatrix Matching Engine
    await Future.delayed(const Duration(milliseconds: 300));

    // Exclude previously actioned users AND previously shown users in this session
    final sessionExcluded = {...state.actionedUserIds, ...state.shownUserIds};

    var matches = _matcher.findMatches(
      currentUser: currentUser,
      candidates: candidates,
      intent: effectiveIntent,
      excludedIds: sessionExcluded,
      limit: 3,
    );

    // If no unshown matches remain in this pool:
    if (matches.isEmpty && candidates.isNotEmpty) {
      if (intent.isMoreOrContinuation) {
        // Pool exhausted for this query: do NOT show duplicates or fake profiles.
        // matches remains empty, and the response text will honestly inform the user.
      } else {
        // If it's a new query topic, check un-actioned candidates for this new vibe
        matches = _matcher.findMatches(
          currentUser: currentUser,
          candidates: candidates,
          intent: effectiveIntent,
          excludedIds: state.actionedUserIds,
          limit: 3,
        );
      }
    }

    // 4. Formulate Concierge Response Copy with Natural Variety
    final responseText = _formulateResponse(
      queryIntent: intent,
      effectiveIntent: effectiveIntent,
      matches: matches,
    );

    final finalizedMsg = CupidChatMessage(
      id: 'cupid_${DateTime.now().millisecondsSinceEpoch}',
      isUser: false,
      text: responseText,
      timestamp: DateTime.now(),
      matches: matches,
      parsedIntent: effectiveIntent,
      isThinking: false,
    );

    // Replace thinking indicator with finalized answer
    final updatedMessages = state.messages
        .where((m) => m.id != thinkingMsgId)
        .toList()
      ..add(finalizedMsg);

    final updatedShownIds = {
      ...state.shownUserIds,
      ...matches.map((m) => m.candidate.id),
    };

    state = state.copyWith(
      messages: updatedMessages,
      isThinking: false,
      shownUserIds: updatedShownIds,
      lastActiveIntent: intent.isMoreOrContinuation ? state.lastActiveIntent : intent,
    );
  }

  String _formulateResponse({
    required NLUIntentResult queryIntent,
    required NLUIntentResult effectiveIntent,
    required List<CupidMatchResult> matches,
  }) {
    _responseVariantIndex++;

    if (matches.isEmpty) {
      if (queryIntent.isMoreOrContinuation) {
        return "You've seen all the active profiles currently matching that vibe in your area! As more members join Situationship, they'll show up here. You can also explore a different vibe or clear the chat to start fresh.";
      }
      return "I couldn't find any active members matching those specific criteria right now. Try exploring a different vibe (like indie music, coffee dates, or night owls) to discover other members!";
    }

    if (queryIntent.isMoreOrContinuation) {
      final variants = [
        "Here's the next set of profiles matching that vibe:",
        'Here are more people curated for your energy:',
        'Found a few more profiles with great chemistry for you:',
        'Here are more connections active nearby:',
      ];
      return variants[_responseVariantIndex % variants.length];
    }

    final isMatchingUserProfile = effectiveIntent.denseVector.isEmpty;

    if (!isMatchingUserProfile &&
        effectiveIntent.naturalSummary.isNotEmpty &&
        effectiveIntent.naturalSummary != 'Open to everyone') {
      final variants = [
        'I found profiles radiating that exact ${effectiveIntent.naturalSummary} energy. Here are your top matches:',
        'Here are the top matches who embody that ${effectiveIntent.naturalSummary} vibe:',
        'Standout profiles who share your passion for ${effectiveIntent.naturalSummary}:',
      ];
      return variants[_responseVariantIndex % variants.length];
    } else if (isMatchingUserProfile) {
      final variants = [
        'I analyzed your profile, passions, and vibe. Here are the souls who naturally complement your energy right now:',
        'Based on what makes you tick, these profiles share a really natural chemistry with your lifestyle:',
        'Curated from your profile vibes — here are the top connections with great mutual chemistry:',
      ];
      return variants[_responseVariantIndex % variants.length];
    } else {
      return 'Here are the most compatible profiles curated exclusively for your vibe:';
    }
  }

  /// Handles inline profile Like
  Future<void> handleLike(UserModel candidate) async {
    final currentUser = ref.read(currentUserProvider);
    state = state.copyWith(
      actionedUserIds: {...state.actionedUserIds, candidate.id},
    );

    try {
      await LikeService.sendLike(currentUser: currentUser, targetUser: candidate);
    } catch (_) {}
  }

  /// Handles inline profile Super Like
  Future<void> handleSuperLike(UserModel candidate) async {
    final currentUser = ref.read(currentUserProvider);
    state = state.copyWith(
      actionedUserIds: {...state.actionedUserIds, candidate.id},
    );

    try {
      await LikeService.sendSuperLike(
        currentUser: currentUser,
        targetUser: candidate,
      );
    } catch (_) {}
  }

  /// Clears chat history and shown user tracking
  void clearChat() {
    state = CupidAIState(
      messages: [
        CupidChatMessage(
          id: 'init_welcome',
          isUser: false,
          text:
              "Chat cleared! Ask me anything about who you'd love to meet.",
          timestamp: DateTime.now(),
        )
      ],
      shownUserIds: const {},
      lastActiveIntent: null,
    );
  }

  /// Loads 100% REAL users exclusively from Firestore and the active app state
  Future<List<UserModel>> _getCandidates(String currentUserId) async {
    final candidateMap = <String, UserModel>{};

    // 1. Pull from currently loaded in-memory matchQueue
    try {
      final inMemory = ref.read(matchQueueProvider);
      for (final u in inMemory) {
        if (u.id.isNotEmpty && u.id != currentUserId && !u.id.startsWith('showcase_')) {
          candidateMap[u.id] = u;
        }
      }
    } catch (_) {}

    // 2. Fetch from Firestore users collection
    try {
      final snap = await firestoreProvider
          .collection('users')
          .limit(100)
          .get();

      for (final doc in snap.docs) {
        if (doc.id == currentUserId) continue;
        try {
          final data = doc.data();
          data['id'] = doc.id;
          final user = UserModel.fromMap(data);
          if (user.id.isNotEmpty && user.id != currentUserId && !user.id.startsWith('showcase_')) {
            candidateMap[user.id] = user;
          }
        } catch (_) {}
      }
    } catch (_) {}

    return candidateMap.values.toList();
  }
}

final cupidAIProvider = StateNotifierProvider.autoDispose<CupidAINotifier, CupidAIState>((ref) {
  return CupidAINotifier(ref);
});
