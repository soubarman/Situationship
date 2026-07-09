import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/user_model.dart';
import '../../wallet/widgets/coin_gate_sheet.dart';
import '../../../shared/widgets/background_orbs.dart';

class VisitorsScreen extends ConsumerWidget {
  const VisitorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final db = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: '(default)',
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profile Visitors',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        children: [
          const BackgroundOrbs(),
          SafeArea(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('profile_views')
                  .where('targetId', isEqualTo: currentUser.id)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.hasData ? snapshot.data!.docs : [];
                final sortedDocs = allDocs.toList()..sort((a, b) {
                  final aTime = a.data()['viewedAt'] as int? ?? 0;
                  final bTime = b.data()['viewedAt'] as int? ?? 0;
                  return bTime.compareTo(aTime);
                });
                
                final Map<String, dynamic> uniqueVisitors = {};
                for (var doc in sortedDocs) {
                  final visitorId = doc.data()['viewerId'] as String? ?? '';
                  if (!uniqueVisitors.containsKey(visitorId)) {
                    uniqueVisitors[visitorId] = doc;
                  }
                }
                final docs = uniqueVisitors.values.toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('👻', style: TextStyle(fontSize: 64)),
                        const SizedBox(height: 16),
                        Text(
                          'No ghost views yet!',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final visitorId = data['viewerId'] as String;
                    final visitorName = data['viewerName'] as String? ?? 'User';
                    final visitorAvatar = data['viewerAvatar'] as String?;
                    
                    final isUnlocked = currentUser.hasActiveSubscription || 
                        currentUser.unlockedVisitors.contains(visitorId);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: (isUnlocked && visitorId.isNotEmpty) ? () => context.push('/profile/view/$visitorId') : (isUnlocked && visitorId.isEmpty ? () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This profile is unavailable or was deleted.'))) : null),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                                  border: Border.all(
                                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundImage: NetworkImage(
                                        isUnlocked 
                                            ? (visitorAvatar ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(visitorName)}')
                                            : 'https://ui-avatars.com/api/?name=%3F&background=252E42&color=fff'
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isUnlocked ? visitorName : 'Ghost Visitor 👻',
                                            style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          if (!isUnlocked) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Unlock to see who viewed you',
                                              style: TextStyle(
                                                color: isDark ? Colors.white54 : Colors.black54,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ]
                                        ],
                                      ),
                                    ),
                                    if (!isUnlocked)
                                      ElevatedButton(
                                        onPressed: () => _unlockGhostView(context, ref, currentUser, visitorId),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryBlue,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text('Unlock', style: TextStyle(fontWeight: FontWeight.bold)),
                                      )
                                    else
                                      const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unlockGhostView(BuildContext context, WidgetRef ref, UserModel currentUser, String visitorId) async {
    final allowed = await showCoinGate(context, ref, 'undo_ghost');
    if (!allowed) return;

    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: '(default)',
      );
      
      await db.collection('users').doc(currentUser.id).update({
        'unlockedVisitors': FieldValue.arrayUnion([visitorId]),
      });
    } catch (e) {
      debugPrint('Error unlocking visitor: $e');
    }
  }
}
