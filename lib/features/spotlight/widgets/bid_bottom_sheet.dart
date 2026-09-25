import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:situationship/core/theme/app_theme.dart';
import 'package:situationship/core/providers/app_state_provider.dart';
import '../models/spotlight_model.dart';
import '../providers/spotlight_provider.dart';

class BidBottomSheet extends ConsumerStatefulWidget {
  final SpotlightSession session;
  final List<SpotlightBid> currentBids;

  const BidBottomSheet({
    super.key,
    required this.session,
    required this.currentBids,
  });

  @override
  ConsumerState<BidBottomSheet> createState() => _BidBottomSheetState();
}

class _BidBottomSheetState extends ConsumerState<BidBottomSheet> {
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  int _bidAmount = 0;
  String? _errorText;
  int _estimatedRank = 21; // Default to out of top 20
  
  // Payment step states: 'input', 'processing', 'success'
  String _paymentStep = 'input'; 
  String _processingMessage = '';
  double _successScale = 0.0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    
    // Set initial bid amount to the minimum required bid
    final int minBid = _calculateMinBid();
    _amountController.text = minBid.toString();
    _bidAmount = minBid;
    _updateEstimatedRank(minBid);

    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int _calculateMinBid() {
    if (widget.currentBids.isEmpty) {
      return widget.session.minStartingBid; // 200 coins
    }
    
    final highestBid = widget.currentBids.first.amount;
    
    // Enforce incremental bids to beat Rank 1
    if (highestBid < 1000) return highestBid + 50;
    if (highestBid < 5000) return highestBid + 100;
    return highestBid + 250;
  }

  int _calculateMinToEnter() {
    if (widget.currentBids.length < 20) {
      return widget.session.minStartingBid; // 200 coins
    }
    
    // If board is full, must beat the 20th rank's bid
    final lastBid = widget.currentBids.last.amount;
    if (lastBid < 1000) return lastBid + 50;
    if (lastBid < 5000) return lastBid + 100;
    return lastBid + 250;
  }

  void _onAmountChanged() {
    final text = _amountController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _bidAmount = 0;
        _errorText = 'Enter a valid amount';
        _estimatedRank = 21;
      });
      return;
    }

    final amount = int.tryParse(text);
    if (amount == null || amount <= 0) {
      setState(() {
        _bidAmount = 0;
        _errorText = 'Enter a valid positive number';
        _estimatedRank = 21;
      });
      return;
    }

    final minToEnter = _calculateMinToEnter();
    final currentUser = ref.read(currentUserProvider);
    
    setState(() {
      _bidAmount = amount;
      if (amount < minToEnter) {
        _errorText = 'Minimum to enter leaderboard is $minToEnter coins';
      } else if (amount > currentUser.coins) {
        _errorText = 'Not enough coins (Balance: ${currentUser.coins})';
      } else {
        _errorText = null;
      }
      _updateEstimatedRank(amount);
    });
  }

  void _updateEstimatedRank(int amount) {
    final currentUser = ref.read(currentUserProvider);
    
    // Exclude the current user's existing bid to estimate rank correctly
    final otherBids = widget.currentBids.where((b) => b.userId != currentUser.id).toList();
    
    int rank = 1;
    for (var bid in otherBids) {
      if (amount >= bid.amount) {
        break;
      }
      rank++;
    }
    
    setState(() {
      _estimatedRank = rank;
    });
  }

  void _adjustAmount(int offset) {
    final currentVal = int.tryParse(_amountController.text) ?? 0;
    final newVal = (currentVal + offset).clamp(0, 100000);
    _amountController.text = newVal.toString();
    _focusNode.requestFocus();
  }

  Future<void> _startPaymentFlow() async {
    if (_bidAmount <= 0 || _errorText != null) return;
    
    final currentUser = ref.read(currentUserProvider);
    if (currentUser.coins < _bidAmount) {
      setState(() {
        _errorText = 'Not enough coins. Need $_bidAmount (Balance: ${currentUser.coins})';
      });
      return;
    }

    _focusNode.unfocus();
    setState(() {
      _paymentStep = 'processing';
      _processingMessage = 'Using $_bidAmount coins...';
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _processingMessage = 'Securing Spotlight Position...';
    });
    
    // Place bid in Firebase
    try {
      await ref.read(spotlightNotifierProvider).placeBid(
        sessionId: widget.session.id,
        amount: _bidAmount,
      );
      
      if (!mounted) return;
      setState(() {
        _paymentStep = 'success';
      });

      // Confetti & success animation scale up
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() {
        _successScale = 1.0;
      });

      // Stay on success screen for 2 seconds before closing
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Success! You secured Rank #$_estimatedRank in the Spotlight! 👑',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _paymentStep = 'input';
        _errorText = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _paymentStep == 'input'
              ? _buildInputUI(context, isDark)
              : _paymentStep == 'processing'
                  ? _buildProcessingUI(context, isDark)
                  : _buildSuccessUI(context, isDark),
        ),
      ),
    );
  }

  Widget _buildInputUI(BuildContext context, bool isDark) {
    final minToEnter = _calculateMinToEnter();
    final minToBeatRank1 = _calculateMinBid();
    final isMinBidSelected = _bidAmount == minToBeatRank1;

    return Padding(
      padding: EdgeInsets.only(
        left: 24.0,
        right: 24.0,
        top: 16.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.electric_bolt_rounded,
                  color: AppTheme.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bid for Spotlight',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                    ),
                    Text(
                      'Boost your profile to the top feed',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white54 : AppTheme.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // User Coins Balance Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
              ),
            ),
            child: Row(
              children: [
                const Text('🪙', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(
                  'Your Balance:',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${ref.watch(currentUserProvider).coins} coins',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/wallet');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '+ Get Coins',
                      style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // High-level stats panel (Current Rank 1 and Min required to enter)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🏆 Rank #1 Bid',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.currentBids.isNotEmpty
                            ? '🪙 ${widget.currentBids.first.amount}'
                            : 'None',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: widget.currentBids.isNotEmpty
                              ? const Color(0xFFFFD700)
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🚪 Min to Enter (#20)',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🪙 $minToEnter',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Custom Input and Rank Preview
          Stack(
            alignment: Alignment.centerRight,
            children: [
              TextField(
                controller: _amountController,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  prefixText: '🪙 ',
                  prefixStyle: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  hintText: 'Coins',
                  errorText: _errorText,
                  errorStyle: const TextStyle(color: AppTheme.error),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                ),
              ),
              if (_errorText == null && _bidAmount >= minToEnter)
                Positioned(
                  right: 16,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: _estimatedRank == 1
                          ? const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)])
                          : _estimatedRank == 2
                              ? const LinearGradient(colors: [Color(0xFFE0E0E0), Color(0xFF9E9E9E)])
                              : _estimatedRank == 3
                                  ? const LinearGradient(colors: [Color(0xFFCD7F32), Color(0xFF8B4513)])
                                  : AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        if (_estimatedRank <= 3)
                          BoxShadow(
                            color: (_estimatedRank == 1
                                    ? const Color(0xFFFFD700)
                                    : _estimatedRank == 2
                                        ? const Color(0xFFE0E0E0)
                                        : const Color(0xFFCD7F32))
                                .withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                      ],
                    ),
                    child: Text(
                      _estimatedRank <= 20 ? 'Est. Rank #$_estimatedRank' : 'Out of Top 20',
                      style: TextStyle(
                        color: _estimatedRank <= 3 ? Colors.black87 : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Preset increments selector
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PresetChip(
                  label: 'Min to Enter ($minToEnter coins)',
                  onTap: () {
                    _amountController.text = minToEnter.toString();
                  },
                  isSelected: _bidAmount == minToEnter,
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: 'Rank #1 ($minToBeatRank1 coins)',
                  onTap: () {
                    _amountController.text = minToBeatRank1.toString();
                  },
                  isSelected: isMinBidSelected,
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: '+100',
                  onTap: () => _adjustAmount(100),
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: '+500',
                  onTap: () => _adjustAmount(500),
                ),
                const SizedBox(width: 8),
                _PresetChip(
                  label: '+1,000',
                  onTap: () => _adjustAmount(1000),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Confirm Button
          ElevatedButton(
            onPressed: (_bidAmount >= minToEnter && _errorText == null) ? _startPaymentFlow : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: (_bidAmount >= minToEnter && _errorText == null)
                    ? AppTheme.primaryGradient
                    : null,
                color: (_bidAmount >= minToEnter && _errorText == null)
                    ? null
                    : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                height: 56,
                alignment: Alignment.center,
                child: Text(
                  _estimatedRank <= 20
                      ? 'Secure Rank #$_estimatedRank (Use $_bidAmount coins)'
                      : 'Place Bid ($_bidAmount coins)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingUI(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              strokeWidth: 5,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Placing Spotlight Bid',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _processingMessage,
              key: ValueKey(_processingMessage),
              textAlign: CenterTextAlignment,
              style: TextStyle(
                color: isDark ? Colors.white70 : AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🪙', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                'Deducting coins from your wallet balance',
                style: TextStyle(
                  color: isDark ? Colors.white30 : AppTheme.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const CenterTextAlignment = TextAlign.center;

  Widget _buildSuccessUI(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: _successScale,
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.success,
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 56,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Spotlight Bid Active!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your bid of 🪙 $_bidAmount coins is active.\nEstimated Spotlight Rank: #$_estimatedRank',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white70 : AppTheme.textSecondary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '🎉 YOU ARE NOW IN THE SPOTLIGHT! 🎉',
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  const _PresetChip({
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue.withOpacity(0.15)
              : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryBlue
                : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primaryBlue : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
