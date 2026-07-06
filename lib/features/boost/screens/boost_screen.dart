import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/post_model.dart';
import '../models/boost_constants.dart';
import '../providers/boost_provider.dart';

class BoostScreen extends ConsumerStatefulWidget {
  final PostModel post;

  const BoostScreen({super.key, required this.post});

  static void show(BuildContext context, PostModel post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BoostScreen(post: post),
    );
  }

  @override
  ConsumerState<BoostScreen> createState() => _BoostScreenState();
}

class _BoostScreenState extends ConsumerState<BoostScreen> {
  int _currentStep = 0; // 0: Scope, 1: Duration, 2: Confirm
  String _selectedScope = 'local'; // 'local', 'regional', 'extended'
  String _selectedTier = 'standard'; // 'standard', 'premium' (mini/standard mapped)
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  int get _calculatedCost {
    int base = 0;
    if (_selectedScope == 'local') {
      base = _selectedTier == 'standard' ? BoostConstants.localStandardCost : BoostConstants.localMiniCost;
    } else if (_selectedScope == 'regional') {
      base = _selectedTier == 'standard' ? BoostConstants.regionalStandardCost : BoostConstants.regionalMiniCost;
    } else if (_selectedScope == 'extended') {
      base = _selectedTier == 'standard' ? BoostConstants.extendedStandardCost : BoostConstants.extendedMiniCost;
    }
    return base;
  }

  Duration get _calculatedDuration {
    return _selectedTier == 'standard' ? BoostConstants.standardDuration : BoostConstants.miniDuration;
  }

  Future<void> _processBoost() async {
    final user = ref.read(currentUserProvider);

    // Guard: enough coins
    final cost = _calculatedCost;
    if (user.coins < cost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Not enough coins. You need $cost coins but have ${user.coins}.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);

    final errorMessage = await ref.read(boostPurchaseProvider.notifier).purchaseBoost(
      contentId: widget.post.id,
      contentType: widget.post.isReel ? 'take' : (widget.post.imageUrl != null ? 'photo' : 'general_post'),
      boostScope: _selectedScope,
      boostTier: _selectedTier,
      duration: _calculatedDuration,
      coinCost: cost,
      reachMultiplier: _selectedTier == 'standard' ? BoostConstants.standardReachMultiplier : BoostConstants.premiumReachMultiplier,
    );

    setState(() => _isProcessing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage == null ? 'Your post is boosted! ⚡' : 'Boost failed: $errorMessage'),
          backgroundColor: errorMessage == null ? AppTheme.primaryBlue : Colors.red,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(currentUserProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(isDark, user.coins),
          Expanded(
            child: [
              _buildStep1Scope(isDark, user),
              _buildStep2Duration(isDark),
              _buildStep3Confirm(isDark),
            ][_currentStep.clamp(0, 2)],
          ),
          _buildFooter(isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, int coins) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (_currentStep > 0 && !_isProcessing)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _currentStep--),
                ),
              const Text(
                'Boost Post',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.monetization_on, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text(
                  '$coins',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1Scope(bool isDark, dynamic user) {
    // Meets eligibility if they have followers or enough total likes on their posts
    final meetsThreshold = user.followers.length >= BoostConstants.minFollowersThreshold
        || user.likedBy.length >= BoostConstants.minLikesThreshold;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _buildPreview(isDark),
        const SizedBox(height: 32),
        const Text('Select Radius Scope', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _scopeCard('local', 'Local Boost (0-5 km)', 'Boost to users within a 5 km radius of your location.', true, isDark),
        const SizedBox(height: 12),
        _scopeCard('regional', 'Regional Boost (5-15 km)', 'Boost to users within a 15 km radius of your location.', meetsThreshold, isDark),
        const SizedBox(height: 12),
        _scopeCard('extended', 'Extended Boost (15-50 km)', 'Boost to users within a 50 km radius of your location.', meetsThreshold, isDark),
      ],
    );
  }

  Widget _scopeCard(String id, String title, String desc, bool enabled, bool isDark) {
    final isSelected = _selectedScope == id;
    return GestureDetector(
      onTap: enabled ? () => setState(() => _selectedScope = id) : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : (isDark ? AppTheme.darkCard : Colors.white),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : (isDark ? AppTheme.darkBorder : Colors.black12),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: enabled ? null : Colors.grey)),
                      if (!enabled) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.lock, size: 14, color: Colors.grey),
                      ]
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(desc, style: TextStyle(fontSize: 12, color: enabled ? AppTheme.textSecondary : Colors.grey)),
                  if (!enabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Text('Requires 50+ total likes or 10+ followers', style: TextStyle(fontSize: 10, color: Colors.red)),
                    ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppTheme.primaryBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Duration(bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const Text('Select Tier & Duration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _tierCard('mini', 'Mini Boost', '30 Minutes', isDark),
        const SizedBox(height: 12),
        _tierCard('standard', 'Standard Boost', '2 Hours', isDark),
      ],
    );
  }

  Widget _tierCard(String id, String title, String duration, bool isDark) {
    final isSelected = _selectedTier == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedTier = id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : (isDark ? AppTheme.darkCard : Colors.white),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : (isDark ? AppTheme.darkBorder : Colors.black12),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(duration, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppTheme.primaryBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3Confirm(bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const Text('Confirm Purchase', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.black12),
          ),
          child: Column(
            children: [
              _summaryRow('Scope', _selectedScope.toUpperCase() == 'LOCAL' ? 'LOCAL (0-5 km)' : (_selectedScope.toUpperCase() == 'REGIONAL' ? 'REGIONAL (5-15 km)' : 'EXTENDED (15-50 km)')),
              const Divider(height: 24),
              _summaryRow('Duration', _calculatedDuration.inMinutes == 30 ? '30 Minutes' : '2 Hours'),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Cost', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Row(
                    children: [
                      const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text('$_calculatedCost', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.amber)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPreview(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              image: widget.post.imageUrl != null
                  ? DecorationImage(image: NetworkImage(widget.post.imageUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: widget.post.imageUrl == null ? const Icon(Icons.text_fields, color: Colors.grey) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Post Preview', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  widget.post.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
        top: 12,
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: _isProcessing
              ? null
              : () {
                  if (_currentStep < 2) {
                    setState(() => _currentStep++);
                  } else {
                    _processBoost();
                  }
                },
          child: _isProcessing
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(
                  _currentStep < 2 ? 'Continue' : 'Boost Now',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
        ),
      ),
    );
  }
}
