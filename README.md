# 💫 Mindate — Gen Z Social + Dating Platform

> **Vibe. Match. Connect.** — A premium Flutter app combining Instagram-style feeds, Tinder-style swiping, and real-time chat.

![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart)
![Firebase](https://img.shields.io/badge/Firebase-Ready-FFCA28?logo=firebase)
![Riverpod](https://img.shields.io/badge/Riverpod-2.x-7C3AED)

---

## 🎯 Features

| Feature | Status |
|---------|--------|
| 🏠 Instagram-style feed with stories | ✅ |
| 💝 Tinder-style swipe matching | ✅ |
| 🎉 Match success screen with animation | ✅ |
| 💬 Real-time chat with typing indicators | ✅ |
| 👤 User profile with posts grid | ✅ |
| ✏️ Edit profile with interests | ✅ |
| 📸 Create post with image picker | ✅ |
| ❤️ Double-tap to like animation | ✅ |
| 🌙 Dark mode support | ✅ |
| 🔔 Push notifications (FCM) | 🔧 Ready |
| 🔐 Firebase Auth | 🔧 Ready |
| 🗄️ Firestore database | 🔧 Ready |

---

## 📁 Project Structure

```
mindate/
├── lib/
│   ├── main.dart                     # App entry point
│   ├── core/
│   │   ├── constants/app_constants.dart
│   │   ├── models/
│   │   │   ├── user_model.dart
│   │   │   ├── post_model.dart
│   │   │   └── chat_model.dart
│   │   ├── router/app_router.dart    # GoRouter config
│   │   └── theme/app_theme.dart      # Design system
│   ├── features/
│   │   ├── auth/
│   │   │   └── screens/
│   │   │       ├── splash_screen.dart
│   │   │       ├── login_screen.dart
│   │   │       └── signup_screen.dart
│   │   ├── shell/
│   │   │   └── main_shell.dart       # Bottom nav shell
│   │   ├── feed/
│   │   │   ├── screens/feed_screen.dart
│   │   │   └── widgets/
│   │   │       ├── post_card.dart
│   │   │       └── stories_row.dart
│   │   ├── match/
│   │   │   ├── screens/
│   │   │   │   ├── match_screen.dart
│   │   │   │   └── match_success_screen.dart
│   │   │   └── widgets/swipe_card.dart
│   │   ├── chat/
│   │   │   └── screens/
│   │   │       ├── chats_screen.dart
│   │   │       └── chat_detail_screen.dart
│   │   ├── profile/
│   │   │   └── screens/
│   │   │       ├── profile_screen.dart
│   │   │       └── edit_profile_screen.dart
│   │   └── post/
│   │       └── screens/create_post_screen.dart
│   └── shared/
│       └── widgets/gradient_button.dart
├── android/
├── ios/
├── pubspec.yaml
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `>=3.0.0` — [Install Flutter](https://docs.flutter.dev/get-started/install)
- Dart SDK `>=3.0.0`
- Android Studio or VS Code
- Firebase account (optional for demo mode)

### 1. Clone & Install

```bash
# Navigate to the project
cd mindate

# Install dependencies
flutter pub get

# Run code generation (for Riverpod)
dart run build_runner build --delete-conflicting-outputs
```

### 2. Run the App

```bash
# Run on Android
flutter run -d android

# Run on iOS (Mac required)
flutter run -d ios

# Run on Chrome (Web)
flutter run -d chrome

# Run in debug mode with hot reload
flutter run
```

---

## 🔥 Firebase Setup

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project → Name it **Mindate**
3. Enable **Google Analytics**

### Step 2: Add Flutter App

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase
flutterfire configure
```

This generates `lib/firebase_options.dart` automatically.

### Step 3: Enable Services

In Firebase Console:

| Service | Steps |
|---------|-------|
| **Authentication** | Authentication → Sign-in Methods → Enable Email/Password & Google |
| **Firestore** | Firestore Database → Create Database → Start in test mode |
| **Storage** | Storage → Get Started → Default rules |
| **Cloud Messaging** | Messaging → pre-configured |

### Step 4: Uncomment Firebase in `main.dart`

```dart
// Uncomment these lines in lib/main.dart:
import 'firebase_options.dart';

await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

### Step 5: Firestore Rules (Production)

```plaintext
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    match /posts/{postId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth.uid == resource.data.userId;
    }
    match /chats/{chatId} {
      allow read, write: if request.auth.uid in resource.data.participants;
    }
    match /messages/{messageId} {
      allow read: if request.auth != null;
      allow create: if request.auth.uid == request.resource.data.senderId;
    }
  }
}
```

---

## 🏗️ State Management

This app uses **Riverpod 2.x**:

```dart
// Reading state
final posts = ref.watch(feedPostsProvider);

// Updating state
ref.read(feedPostsProvider.notifier).update((posts) {
  return posts.map((p) => p.id == id ? p.copyWith(likes: newLikes) : p).toList();
});

// Providers
final feedPostsProvider = StateProvider<List<PostModel>>((ref) => PostModel.mockPosts);
```

---

## 🎨 Design System

### Colors
```dart
AppTheme.primaryBlue   = Color(0xFF6ECBF5)  // Soft blue
AppTheme.primaryGreen  = Color(0xFF7EEECB)  // Mint green
AppTheme.accentPurple  = Color(0xFFB8A9FF)  // Lavender
AppTheme.accentPink    = Color(0xFFFFB8D9)  // Rose
AppTheme.success       = Color(0xFF4ADE80)  // Online green
AppTheme.error         = Color(0xFFFF6B8A)  // Soft red
```

### Typography
Using **Google Fonts – Outfit** for all text. Premium weight system:
- Display: `w800` for headings, `-1.5` letter spacing
- Body: `w400` with `1.6` line height
- Labels: `w600`, `+0.5` letter spacing

---

## 📱 Build for Production

### Android APK/AAB

```bash
# Build release APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

### iOS IPA

```bash
# Build for iOS (requires macOS + Xcode)
flutter build ios --release

# Open in Xcode to archive
open ios/Runner.xcworkspace
```

### Web

```bash
# Build optimized web bundle
flutter build web --release --web-renderer canvaskit

# Serve locally
cd build/web && python -m http.server 8080
```

---

## 🧠 Architecture Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| State Management | Riverpod 2.x | Type-safe, testable, compile-time safety |
| Navigation | GoRouter | Deep linking, shell routes, type-safe |
| Backend | Firebase | Real-time, auth + storage in one SDK |
| Fonts | Google Fonts (Outfit) | Premium Gen Z aesthetic |
| Images | Cached Network Image | Performance + offline caching |

---

## 🔧 Performance Optimizations

- `CachedNetworkImage` for all profile photos and posts
- `ListView.builder` for virtualized scrolling
- `RepaintBoundary` on animated widgets
- `const` constructors everywhere possible
- Shimmer loading placeholders
- `60fps` animations using proper `AnimationController` patterns

---

## 📋 Next Steps

- [ ] Wire up Firebase Auth (email + Google)
- [ ] Replace mock data with Firestore streams
- [ ] Implement FCM push notifications
- [ ] Add real image picker (camera/gallery)
- [ ] Add video/reel support with `chewie`
- [ ] Implement real-time chat with Firestore listeners
- [ ] Add profile verification badge system
- [ ] Deploy to Google Play & App Store

---

## 🤝 Contributing

1. Fork the repo
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push: `git push origin feature/amazing-feature`
5. Open a Pull Request

---

*Built with ❤️ and Flutter*
