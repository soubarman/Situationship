import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/complete_profile_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/feed/screens/feed_screen.dart';
import '../../features/feed/screens/search_screen.dart';
import '../../features/match/screens/match_screen.dart';
import '../../features/match/screens/match_success_screen.dart';
import '../../features/match/screens/community_detail_screen.dart';
import '../../features/match/screens/create_community_screen.dart';
import '../../features/chat/screens/chats_screen.dart';
import '../../features/chat/screens/chat_detail_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/user_detail_screen.dart';
import '../../features/post/screens/create_post_screen.dart';
import '../../features/feed/screens/create_story_screen.dart';
import '../../features/feed/screens/story_view_screen.dart';
import '../providers/firebase_auth_provider.dart';
import '../providers/app_state_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final authState = ref.read(authStateChangesProvider);
      final userProfile = ref.read(userDataStreamProvider);

      // 1. AUTH INITIALIZATION GUARD
      // While Firebase is still initialising, stay on splash.
      if (authState.isLoading) return '/splash';

      final isLoggedIn = authState.asData?.value != null;
      final isProtected = ['/feed', '/match', '/chats', '/profile', '/search', '/create-post', '/story'].any(
        (r) => state.matchedLocation.startsWith(r),
      );
      final isCompletingProfile = state.matchedLocation == '/complete-profile';

      // 2. AUTHENTICATION GUARD
      if (!isLoggedIn) {
        return isProtected ? '/login' : null;
      }

      // 3. PROFILE DATA LOADING GUARD (FOR LOGGED IN USERS)
      // Only proceed with redirects once we have a definitive answer from Firestore.
      // This prevents the "flash" of dummy data and premature redirection loops.
      if (userProfile.isLoading) return '/splash';

      // 4. PROFILE COMPLETION GUARD
      final user = userProfile.asData?.value;
      final isProfileIncomplete = user == null || 
          (user.bio?.isEmpty ?? true) || 
          user.avatarUrl == null;

      // Logged in & on auth / splash screens → send to feed/complete-profile.
      if (state.matchedLocation == '/login' ||
          state.matchedLocation == '/login/signup' ||
          state.matchedLocation == '/splash') {
        return isProfileIncomplete ? '/complete-profile' : '/feed';
      }

      // If logged in but profile is still incomplete, force them back to onboarding.
      if (!isCompletingProfile && isProfileIncomplete) {
        return '/complete-profile';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
        routes: [
          GoRoute(
            path: 'signup',
            name: 'signup',
            builder: (context, state) => const SignupScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/complete-profile',
        name: 'complete-profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        builder: (context, state) => const SearchScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/feed',
            name: 'feed',
            builder: (context, state) => const FeedScreen(),
          ),
          GoRoute(
            path: '/match',
            name: 'match',
            builder: (context, state) => const MatchScreen(),
            routes: [
              GoRoute(
                path: 'success',
                name: 'match-success',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>?;
                  return MatchSuccessScreen(matchData: extra ?? {});
                },
              ),
            ],
          ),
          GoRoute(
            path: '/chats',
            name: 'chats',
            builder: (context, state) => const ChatsScreen(),
            routes: [
              GoRoute(
                path: ':chatId',
                name: 'chat-detail',
                builder: (context, state) {
                  final chatId = state.pathParameters['chatId']!;
                  final extra = state.extra as Map<String, dynamic>?;
                  return ChatDetailScreen(chatId: chatId, userData: extra ?? {});
                },
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'edit',
                name: 'edit-profile',
                builder: (context, state) => const EditProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/profile/view/:userId',
        name: 'user-detail',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return UserDetailScreen(userId: userId);
        },
      ),
      GoRoute(
        path: '/community/create',
        name: 'create-community',
        builder: (context, state) => const CreateCommunityScreen(),
      ),
      GoRoute(
        path: '/community/:id',
        name: 'community-detail',
        builder: (context, state) {
          final communityId = state.pathParameters['id']!;
          return CommunityDetailScreen(communityId: communityId);
        },
      ),
      GoRoute(
        path: '/create-post',
        name: 'create-post',
        builder: (context, state) => const CreatePostScreen(),
      ),
      GoRoute(
        path: '/story/create',
        name: 'create-story',
        builder: (context, state) => const CreateStoryScreen(),
      ),
      GoRoute(
        path: '/story/view/:userId',
        name: 'story-view',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          final extra = state.extra as Map<String, dynamic>?;
          return StoryViewScreen(
            userId: userId,
            initialName: extra?['userName'],
            initialAvatar: extra?['userAvatar'],
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.error}'),
      ),
    ),
  );

  ref.listen(authStateChangesProvider, (_, __) => router.refresh());
  ref.listen(userDataStreamProvider, (_, __) => router.refresh());

  return router;
});
