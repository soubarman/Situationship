import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/utils/location_helper.dart';
import '../../spotlight/widgets/spotlight_feed_section.dart';

// ─── Data & Constants ────────────────────────────────────────────────────────

const _vibeLabels = [
  'chronically online',
  'delulu optimist',
  'golden hour type',
  'quiet storm energy',
  'soft chaos era',
  'night owl mood',
  'main character vibes',
  'romanticizes everything',
  'feral but cute',
  'soft launch era',
];

const _sampleQuotes = [
  '"jazz or lo-fi at 2am?"',
  '"bookshop wanderer"',
  '"slow breakfast, no plans"',
  '"deep talks at 2am"',
  '"laughs at my own jokes"',
  '"emotionally available (mostly)"',
  '"chaotic but make it cute"',
  '"feral but cute"',
];

const _reactionPhrases = [
  'ok we see you',
  'taste 🤌',
  'good pick ✨',
  'locked in 🔒',
  'vibe match ⚡',
  'sheesh 🔥',
  'valid fr fr 🤝',
  'we love to see it',
  'no debate 💅',
  'certified banger 🎯',
  'immaculate vibe 💫',
  'they\'re the one fr',
  'chemistry check 💖',
  '10/10 no notes 📝',
  'main character energy 🌟',
  'rizz certified 🏆',
  'instant click 🔗',
];

const _grayscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0,      0,      0,      1, 0,
];

String _vibeFor(UserModel u) =>
    _vibeLabels[u.id.hashCode.abs() % _vibeLabels.length];

String _quoteFor(UserModel u) {
  final bio = u.bio?.trim();
  if (bio != null && bio.isNotEmpty && bio != 'Loading...' && bio != 'User' && bio.length > 5) {
    final short = bio.length > 28 ? '${bio.substring(0, 26)}...' : bio;
    return '"$short"';
  }
  if (u.interests.isNotEmpty) {
    return '"into ${u.interests.take(2).join(' & ')}"';
  }
  return _sampleQuotes[u.id.hashCode.abs() % _sampleQuotes.length];
}

// ─── Main Widget ──────────────────────────────────────────────────────────────

class DiscoverTab extends ConsumerStatefulWidget {
  final List<UserModel> users;
  final double? deviceLat;
  final double? deviceLon;
  final Future<void> Function(UserModel liked, {UserModel? pairedWith}) onLike;
  final void Function(UserModel user) onSkip;

  const DiscoverTab({
    super.key,
    required this.users,
    this.deviceLat,
    this.deviceLon,
    required this.onLike,
    required this.onSkip,
  });

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab>
    with TickerProviderStateMixin {
  int _round = 1;
  static const int _totalRounds = 5;
  String? _chosenId;
  String? _currentReaction;
  bool _isAnimating = false;

  // Spotlight countdown
  late Timer _spotlightTimer;
  int _spotlightSecondsLeft = 7 * 60 + 39;

  // Entry animation (new pair slides up)
  late AnimationController _entryController;
  late Animation<double> _entryFade;
  late Animation<Offset> _leftSlide;
  late Animation<Offset> _rightSlide;

  // Exit animation (nah / after pick: cards fly out)
  late AnimationController _exitController;
  late Animation<Offset> _leftExit;
  late Animation<Offset> _rightExit;
  late Animation<double> _exitFade;
  bool _isExiting = false;

  // Pick glow animation
  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  // Reaction badge animation
  late AnimationController _reactionController;
  late Animation<double> _reactionScale;

  @override
  void initState() {
    super.initState();

    // Entry: left card from bottom-left, right from bottom-right, staggered
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _leftSlide = Tween<Offset>(begin: const Offset(-0.08, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic));
    _rightSlide = Tween<Offset>(begin: const Offset(0.08, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryController, curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic)));

    // Exit: left flies left, right flies right
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _leftExit = Tween<Offset>(begin: Offset.zero, end: const Offset(-1.2, 0))
        .animate(CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic));
    _rightExit = Tween<Offset>(begin: Offset.zero, end: const Offset(1.2, 0))
        .animate(CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic));
    _exitFade = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _exitController, curve: const Interval(0.5, 1.0)));

    // Glow pulse on pick
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _glowController, curve: Curves.easeOutBack));

    // Reaction badge pop
    _reactionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _reactionScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _reactionController, curve: Curves.elasticOut));

    _entryController.forward();

    _spotlightTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _spotlightSecondsLeft > 0) {
        setState(() => _spotlightSecondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _exitController.dispose();
    _glowController.dispose();
    _reactionController.dispose();
    _spotlightTimer.cancel();
    super.dispose();
  }

  List<UserModel> get _pair {
    if (widget.users.isEmpty) return [];
    if (widget.users.length == 1) return [widget.users[0]];
    return [widget.users[0], widget.users[1]];
  }

  String get _spotlightTime {
    final m = (_spotlightSecondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_spotlightSecondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _choose(UserModel chosen) async {
    if (_chosenId != null || _isAnimating) return;
    HapticFeedback.mediumImpact();

    final phrase = _reactionPhrases[Random().nextInt(_reactionPhrases.length)];

    _glowController.reset();
    _reactionController.reset();
    setState(() {
      _chosenId = chosen.id;
      _currentReaction = phrase;
      _isAnimating = true;
    });

    _glowController.forward();
    _reactionController.forward();

    // Give user time to see the celebration, abbreviation bubble, and glowing lime border
    await Future.delayed(const Duration(milliseconds: 700));
    final other = _pair.where((u) => u.id != chosen.id).firstOrNull;
    await widget.onLike(chosen, pairedWith: other);

    setState(() => _isExiting = true);
    await _exitController.forward();
    if (mounted) {
      _exitController.reset();
      _entryController.reset();
      _reactionController.reset();
      setState(() {
        _chosenId = null;
        _currentReaction = null;
        _isAnimating = false;
        _isExiting = false;
        _round = min(_round + 1, _totalRounds);
      });
      _entryController.forward();
    }
  }

  Future<void> _nah() async {
    if (_isAnimating) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isAnimating = true;
      _isExiting = true;
    });

    final currentPair = List<UserModel>.from(_pair);
    for (final u in currentPair) {
      widget.onSkip(u);
    }

    await _exitController.forward();
    if (mounted) {
      _exitController.reset();
      _entryController.reset();
      setState(() {
        _chosenId = null;
        _currentReaction = null;
        _isAnimating = false;
        _isExiting = false;
        _round = min(_round + 1, _totalRounds);
      });
      _entryController.forward();
    }
  }

  Future<void> _takeBoth() async {
    if (_isAnimating) return;
    final currentUser = ref.read(currentUserProvider);
    if (!currentUser.hasActiveSubscription) {
      HapticFeedback.lightImpact();
      showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.75),
        isScrollControlled: true,
        builder: (_) => const _PremiumModal(),
      );
      return;
    }

    // User is subscribed: Take Both!
    HapticFeedback.heavyImpact();
    setState(() {
      _isAnimating = true;
      _currentReaction = 'took both 👑';
    });

    _reactionController.reset();
    _reactionController.forward();

    final pairToLike = List<UserModel>.from(_pair);
    for (final u in pairToLike) {
      await widget.onLike(u);
    }

    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() {
        _isExiting = true;
      });
      await _exitController.forward();
      if (mounted) {
        _exitController.reset();
        _entryController.reset();
        setState(() {
          _chosenId = null;
          _currentReaction = null;
          _isAnimating = false;
          _isExiting = false;
          _round = min(_round + 1, _totalRounds);
        });
        _entryController.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final pair = _pair;
    if (pair.isEmpty) return _buildEmptyState();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 6),
            _buildSubline(),
            const SizedBox(height: 16),
            _buildFaceOffCards(currentUser, pair),
            const SizedBox(height: 16),
            _buildActionButtons(),
            const SizedBox(height: 14),
            _buildProgressBar(),
            const SizedBox(height: 18),
            _buildWeeklySpotlightHeader(),
            const SizedBox(height: 8),
            const SpotlightFeedSection(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RichText(
          text: const TextSpan(children: [
            TextSpan(
              text: 'the ',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            TextSpan(
              text: 'faceof!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: Color(0xFFFF2D87),
                letterSpacing: -0.5,
              ),
            ),
          ]),
        ),
        const Spacer(),
        _RoundBadge(round: _round),
      ],
    );
  }

  Widget _buildSubline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(children: [
            TextSpan(
              text: 'two pulled up. ',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            TextSpan(
              text: "who's the vibe?",
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFA3E635),
                fontStyle: FontStyle.italic,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 3),
        Row(children: [
          const Text('✌️', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(
            'two fingers on both pics = take both',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45),
              fontWeight: FontWeight.w500,
            ),
          ),
        ]),
      ],
    );
  }

  // ─── FaceOff Cards ────────────────────────────────────────────────────────────

  Widget _buildFaceOffCards(UserModel currentUser, List<UserModel> pair) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth;
        // 10px spacing between cards
        final halfW = (availableW - 10) / 2;
        // Responsive portrait ratio (1 : 1.48) so cards maintain ideal proportions
        final cardHeight = (halfW * 1.48).clamp(240.0, 315.0);

        Widget buildLeft() => SlideTransition(
          position: _isExiting ? _leftExit : _leftSlide,
          child: FadeTransition(
            opacity: _isExiting ? _exitFade : _entryFade,
            child: _FaceOffCard(
              user: pair[0],
              currentUser: currentUser,
              deviceLat: widget.deviceLat,
              deviceLon: widget.deviceLon,
              isChosen: _chosenId == pair[0].id,
              isOther: _chosenId != null && _chosenId != pair[0].id,
              glowAnim: _glowAnim,
              onTap: () => _choose(pair[0]),
              onLongPress: () => context.push('/profile/view/${pair[0].id}'),
            ),
          ),
        );

        Widget buildRight() => pair.length > 1
            ? SlideTransition(
                position: _isExiting ? _rightExit : _rightSlide,
                child: FadeTransition(
                  opacity: _isExiting ? _exitFade : _entryFade,
                  child: _FaceOffCard(
                    user: pair[1],
                    currentUser: currentUser,
                    deviceLat: widget.deviceLat,
                    deviceLon: widget.deviceLon,
                    isChosen: _chosenId == pair[1].id,
                    isOther: _chosenId != null && _chosenId != pair[1].id,
                    glowAnim: _glowAnim,
                    onTap: () => _choose(pair[1]),
                    onLongPress: () => context.push('/profile/view/${pair[1].id}'),
                  ),
                ),
              )
            : const SizedBox.shrink();

        return SizedBox(
          height: cardHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0, top: 0, bottom: 0, width: halfW,
                child: buildLeft(),
              ),
              if (pair.length > 1)
                Positioned(
                  right: 0, top: 0, bottom: 0, width: halfW,
                  child: buildRight(),
                ),
              if (pair.length > 1)
                Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _chosenId != null ? 0.0 : 1.0,
                    child: _VsBadge(anim: _entryFade),
                  ),
                ),
              // Reaction Abbreviation Popup ("ok we see you", etc.)
              if (_currentReaction != null)
                Center(
                  child: ScaleTransition(
                    scale: _reactionScale,
                    child: _ReactionBubble(text: _currentReaction!),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─── Action Buttons ───────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Compact Nah button
        _NahButton(onTap: _nah),
        const SizedBox(width: 10),
        // Expanded glowing Take Both button with lime dot indicator
        Expanded(
          child: _TakeBothButton(onTap: _takeBoth),
        ),
      ],
    );
  }

  // ─── Progress Bar ─────────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    final progress = (_round - 1) / _totalRounds;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(height: 3, color: Colors.white.withValues(alpha: 0.1)),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  height: 3,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFF2D87), Color(0xFF8B5CF6)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'streak check — don\'t fumble it now',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_round - 1}/$_totalRounds',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFD8B4FE),
                  ),
                ),
                const SizedBox(width: 4),
                const Text('🔥', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ─── Weekly Spotlight Header ──────────────────────────────────────────────────

  Widget _buildWeeklySpotlightHeader() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/spotlight');
      },
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF166534),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.5), width: 1.2),
            boxShadow: [
              BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.25), blurRadius: 12),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _PulsingDot(),
            const SizedBox(width: 7),
            const Text(
              'WEEKLY SPOTLIGHT',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF4ADE80), letterSpacing: 0.7),
            ),
          ]),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
            ),
            child: Text(
              'resets $_spotlightTime',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white.withValues(alpha: 0.35)),
        ]),
      ]),
    );
  }

  // ─── Empty State ──────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)]),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFFEC4899).withValues(alpha: 0.4), blurRadius: 20)],
            ),
            child: const Center(child: Text('🏆', style: TextStyle(fontSize: 34))),
          ),
          const SizedBox(height: 22),
          const Text(
            "you've seen them all!",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.3),
          ),
          const SizedBox(height: 8),
          Text(
            "Round complete. More faces drop soon.\nDon't fumble the streak.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.45), height: 1.5),
          ),
        ]),
      ),
    );
  }
}

// ─── Reaction Bubble (e.g. "ok we see you") ───────────────────────────────────

class _ReactionBubble extends StatelessWidget {
  final String text;
  const _ReactionBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.065, // ~-3.7 degrees tilt, exactly like image 2
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF2E93), Color(0xFFC084FC)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white, width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2E93).withValues(alpha: 0.55),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF160826), // Deep dark plum/black text matching Image 2
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

// ─── Round Badge ─────────────────────────────────────────────────────────────────

class _RoundBadge extends StatefulWidget {
  final int round;
  const _RoundBadge({required this.round});

  @override
  State<_RoundBadge> createState() => _RoundBadgeState();
}

class _RoundBadgeState extends State<_RoundBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  int _displayed = 0;

  @override
  void initState() {
    super.initState();
    _displayed = widget.round;
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _scale = Tween<double>(begin: 1.0, end: 1.3)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
  }

  @override
  void didUpdateWidget(_RoundBadge old) {
    super.didUpdateWidget(old);
    if (widget.round != old.round) {
      _ctrl.forward(from: 0).then((_) {
        if (mounted) setState(() => _displayed = widget.round);
        _ctrl.reverse();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.5), width: 1.2),
          boxShadow: [
            BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3), blurRadius: 10),
          ],
        ),
        child: Text(
          'RD ${_displayed.toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Color(0xFFD8B4FE),
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// ─── VS Badge ───────────────────────────────────────────────────────────────────

class _VsBadge extends StatelessWidget {
  final Animation<double> anim;
  const _VsBadge({required this.anim});

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.4, end: 1.0)
          .animate(CurvedAnimation(parent: anim, curve: Curves.elasticOut)),
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF2D87), Color(0xFFF59E0B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF0D0717), width: 3.0),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF2D87).withValues(alpha: 0.55),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'vs',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Nah Button ───────────────────────────────────────────────────────────────────

class _NahButton extends StatefulWidget {
  final VoidCallback onTap;
  const _NahButton({required this.onTap});

  @override
  State<_NahButton> createState() => _NahButtonState();
}

class _NahButtonState extends State<_NahButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) => _ctrl.reverse(),
        onTapCancel: () => _ctrl.reverse(),
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF140D22),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  'nah',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Take Both Button ─────────────────────────────────────────────────────────────

class _TakeBothButton extends StatefulWidget {
  final VoidCallback onTap;
  const _TakeBothButton({required this.onTap});

  @override
  State<_TakeBothButton> createState() => _TakeBothButtonState();
}

class _TakeBothButtonState extends State<_TakeBothButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) => _ctrl.reverse(),
        onTapCancel: () => _ctrl.reverse(),
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scale,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF2E93), Color(0xFFC084FC)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(21),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF2E93).withValues(alpha: 0.40),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFF160826),
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'take both',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF160826),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              // Tiny vibrant lime dot on top right
              Positioned(
                top: 4,
                right: 6,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFFA3E635),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFA3E635).withValues(alpha: 0.8),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── FaceOff Card ────────────────────────────────────────────────────────────────

class _FaceOffCard extends StatefulWidget {
  final UserModel user;
  final UserModel currentUser;
  final bool isChosen;
  final bool isOther;
  final double? deviceLat;
  final double? deviceLon;
  final Animation<double> glowAnim;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FaceOffCard({
    required this.user,
    required this.currentUser,
    required this.isChosen,
    required this.isOther,
    this.deviceLat,
    this.deviceLon,
    required this.glowAnim,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_FaceOffCard> createState() => _FaceOffCardState();
}

class _FaceOffCardState extends State<_FaceOffCard> with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressScale;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _pressScale = Tween<double>(begin: 1.0, end: 0.97).animate(_pressCtrl);
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final vibe = _vibeFor(widget.user);
    final quote = _quoteFor(widget.user);
    final distance = LocationHelper.getDistanceKm(
      lat1: widget.deviceLat,
      lon1: widget.deviceLon,
      loc1: widget.currentUser.location,
      loc2: widget.user.location,
      id1: widget.currentUser.id,
      id2: widget.user.id,
    );

    // Compute scale: hover slightly lifts up, chosen scales to 1.03, other shrinks to 0.94
    double targetScale = 1.0;
    if (widget.isChosen) {
      targetScale = 1.03;
    } else if (widget.isOther) {
      targetScale = 0.94;
    } else if (_isHovered) {
      targetScale = 1.03;
    }

    return MouseRegion(
      cursor: widget.isOther ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) {
        if (!widget.isOther && !widget.isChosen && mounted) {
          setState(() => _isHovered = true);
        }
      },
      onExit: (_) {
        if (mounted) {
          setState(() => _isHovered = false);
        }
      },
      child: GestureDetector(
        onTap: widget.isOther ? null : widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: widget.isOther ? null : (_) => _pressCtrl.forward(),
        onTapUp: widget.isOther ? null : (_) => _pressCtrl.reverse(),
        onTapCancel: () => _pressCtrl.reverse(),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 280),
          opacity: widget.isOther ? 0.32 : 1.0,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 260),
            scale: targetScale,
            curve: Curves.easeOutCubic,
            child: ScaleTransition(
              scale: _pressScale,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Photo with Grayscale filter when other card is picked
                    widget.isOther
                        ? ColorFiltered(
                            colorFilter: const ColorFilter.matrix(_grayscaleMatrix),
                            child: _buildImage(),
                          )
                        : _buildImage(),

                    // Bottom gradient overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.02),
                              Colors.black.withValues(alpha: 0.88),
                            ],
                            stops: const [0.38, 0.58, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Hover outline glow (when hovered but not chosen)
                    if (_isHovered && !widget.isChosen && !widget.isOther)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFE879F9).withValues(alpha: 0.7),
                              width: 2.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE879F9).withValues(alpha: 0.35),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Neon Lime Green Glow Border when chosen (matches Image 2 exactly)
                    if (widget.isChosen)
                      AnimatedBuilder(
                        animation: widget.glowAnim,
                        builder: (context, _) => Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFFA3E635), // Neon lime / chartreuse
                                width: 3.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFA3E635).withValues(alpha: widget.glowAnim.value * 0.75),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (!_isHovered)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                              width: 1,
                            ),
                          ),
                        ),
                      ),

                    // Top Right Heart Badge when chosen (matches Image 2)
                    if (widget.isChosen)
                      Positioned(
                        top: 14,
                        right: 14,
                        child: AnimatedBuilder(
                          animation: widget.glowAnim,
                          builder: (context, _) => Transform.scale(
                            scale: widget.glowAnim.value,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFE879F9), Color(0xFFC084FC)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE879F9).withValues(alpha: 0.6),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFF1E0A30), // Black / deep plum heart
                                  size: 19,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Info overlay at bottom (matches Image 2)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Name & age
                          RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(children: [
                              TextSpan(
                                text: widget.user.name.toLowerCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              TextSpan(
                                text: ' /${widget.user.age}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 2),
                          // Quote
                          Text(
                            quote,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                              fontStyle: FontStyle.italic,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          // Vibe pill + Distance
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Sleek dark pill for vibe
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.14),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    vibe,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_on_rounded,
                                    size: 9.5,
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$distance mi',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withValues(alpha: 0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    return CachedNetworkImage(
      imageUrl: widget.user.avatarUrl ?? 'https://i.pravatar.cc/600?u=${widget.user.id}',
      fit: BoxFit.cover,
      alignment: const Alignment(0, -0.2),
      memCacheWidth: 600,
      placeholder: (_, __) => _placeholder(),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1033), Color(0xFF2D1B56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(child: Icon(Icons.person_rounded, size: 44, color: Colors.white24)),
    );
  }
}

// ─── Pulsing dot for spotlight header ─────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.3).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          color: const Color(0xFF4ADE80),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: const Color(0xFF4ADE80).withValues(alpha: 0.8), blurRadius: 7)],
        ),
      ),
    );
  }
}

// ─── Premium Modal ───────────────────────────────────────────────────────────────

class _PremiumModal extends ConsumerWidget {
  const _PremiumModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPadding),
        decoration: BoxDecoration(
          color: const Color(0xFF130D22),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
            // Crown icon
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  colors: [Color(0xFFEC4899), Color(0xFF9333EA)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEC4899).withValues(alpha: 0.5),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'premium only',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'take both is a premium feature. get unlimited\nrounds & pick both contenders in every faceoff.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.60),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Unlock button -> routes to wallet
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).pop();
                context.push('/wallet');
              },
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEC4899), Color(0xFFD946EF)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'unlock premium in wallet',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Quick 24H Trial Pass Activation
            GestureDetector(
              onTap: () async {
                HapticFeedback.mediumImpact();
                final expiry = DateTime.now().add(const Duration(days: 1));
                try {
                  if (user.id.isNotEmpty) {
                    await firestoreProvider.collection('users').doc(user.id).update({
                      'isSubscribed': true,
                      'subscriptionExpiry': Timestamp.fromDate(expiry),
                    });
                  }
                  ref.invalidate(userDataStreamProvider);
                } catch (e) {
                  debugPrint('Trial pass error: $e');
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('🎉 24H Premium Pass Activated! You can now Take Both!'),
                      backgroundColor: const Color(0xFFFF2D87),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFA3E635)),
                    SizedBox(width: 4),
                    Text(
                      'ACTIVATE 24H TRIAL PASS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFA3E635),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Maybe later
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'MAYBE LATER',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.35),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),);
  }
}
