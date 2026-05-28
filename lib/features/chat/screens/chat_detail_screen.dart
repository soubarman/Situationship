import 'dart:math';
import 'dart:async';
import 'dart:convert';
import '../utils/chat_js_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String chatId;
  final Map<String, dynamic> userData;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.userData,
  });

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen>
    with SingleTickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showEmoji = false;
  bool _isTypingLocal = false; // local typing state for indicator animation
  bool _isLoading = true; // Track initial load
  late AnimationController _typingController;

  int _keyboardTab = 0; // 0 for Emojis, 1 for Stickers, 2 for GIFs
  int _selectedStickerPack = 0; // 0: Emojis, 1: Animals, 2: Food, 3: Objects
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  bool _isUsingSimulatedMic = false;

  // GIPHY integration variables
  String? _customGiphyApiKey;
  String _giphySearchQuery = '';
  List<dynamic> _giphyGifs = [];
  List<dynamic> _giphyStickers = [];
  bool _giphyLoading = false;
  String? _giphyError;
  Timer? _giphyDebounce;

  static const _emojiQuickPicks = [
    '😊', '🔥', '✨', '😂', '🥺', '💫', '❤️', '🙏', '👀', '🎉', '😍', '💬',
    '👍', '🙌', '💯', '🚀', '⭐', '🎈', '🍕', '🍻', '💖', '🍿', '💡', '🎵'
  ];

  static const List<Map<String, String>> _packEmojis = [
    {'emoji': '😊', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Grinning%20Face/3D/grinning_face_3d.png'},
    {'emoji': '😂', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Face%20with%20Tears%20of%20Joy/3D/face_with_tears_of_joy_3d.png'},
    {'emoji': '😍', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Smiling%20Face%20with%20Heart-Eyes/3D/smiling_face_with_heart-eyes_3d.png'},
    {'emoji': '🥺', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Pleading%20Face/3D/pleading_face_3d.png'},
    {'emoji': '🤯', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Exploding%20Head/3D/exploding_head_3d.png'},
    {'emoji': '🤔', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Thinking%20Face/3D/thinking_face_3d.png'},
    {'emoji': '😉', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Winking%20Face/3D/winking_face_3d.png'},
    {'emoji': '🤪', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Zany%20Face/3D/zany_face_3d.png'},
  ];

  static const List<Map<String, String>> _packAnimals = [
    {'emoji': '🐱', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Cat%20Face/3D/cat_face_3d.png'},
    {'emoji': '🐶', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Dog%20Face/3D/dog_face_3d.png'},
    {'emoji': '🐼', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Panda/3D/panda_3d.png'},
    {'emoji': '🐻', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Bear/3D/bear_3d.png'},
    {'emoji': '🐰', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Rabbit%20Face/3D/rabbit_face_3d.png'},
    {'emoji': '🐨', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Koala/3D/koala_3d.png'},
    {'emoji': '🦄', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Unicorn/3D/unicorn_3d.png'},
    {'emoji': '🐵', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Monkey%20Face/3D/monkey_face_3d.png'},
  ];

  static const List<Map<String, String>> _packFood = [
    {'emoji': '🍕', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Pizza/3D/pizza_3d.png'},
    {'emoji': '🍔', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Hamburger/3D/hamburger_3d.png'},
    {'emoji': '🍟', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/French%20Fries/3D/french_fries_3d.png'},
    {'emoji': '🍩', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Donut/3D/donut_3d.png'},
    {'emoji': '🎂', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Birthday%20Cake/3D/birthday_cake_3d.png'},
    {'emoji': '🥑', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Avocado/3D/avocado_3d.png'},
    {'emoji': '🍓', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Strawberry/3D/strawberry_3d.png'},
    {'emoji': '🍦', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Soft%20Ice%20Cream/3D/soft_ice_cream_3d.png'},
  ];

  static const List<Map<String, String>> _packObjects = [
    {'emoji': '❤️', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Red%20Heart/3D/red_heart_3d.png'},
    {'emoji': '🔥', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Fire/3D/fire_3d.png'},
    {'emoji': '✨', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Sparkles/3D/sparkles_3d.png'},
    {'emoji': '🎉', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Party%20Popper/3D/party_popper_3d.png'},
    {'emoji': '🚀', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Rocket/3D/rocket_3d.png'},
    {'emoji': '🎈', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Balloon/3D/balloon_3d.png'},
    {'emoji': '👑', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Crown/3D/crown_3d.png'},
    {'emoji': '🎁', 'url': 'https://cdn.jsdelivr.net/gh/microsoft/fluentui-emoji@latest/assets/Wrapped%20Gift/3D/wrapped_gift_3d.png'},
  ];

  String _emojiToHex(String emoji) {
    if (emoji == '😊') return '1f60a';
    if (emoji == '🔥') return '1f525';
    if (emoji == '✨') return '2728';
    if (emoji == '😂') return '1f602';
    if (emoji == '🥺') return '1f97a';
    if (emoji == '💫') return '1f4ab';
    if (emoji == '❤️') return '2764';
    if (emoji == '🙏') return '1f64f';
    if (emoji == '👀') return '1f440';
    if (emoji == '🎉') return '1f389';
    if (emoji == '😍') return '1f60d';
    if (emoji == '💬') return '1f4ac';
    if (emoji == '👍') return '1f44d';
    if (emoji == '🙌') return '1f64c';
    if (emoji == '💯') return '1f4af';
    if (emoji == '🚀') return '1f680';
    if (emoji == '⭐') return '2b50';
    if (emoji == '🎈') return '1f388';
    if (emoji == '🍕') return '1f355';
    if (emoji == '🍻') return '1f37b';
    if (emoji == '💖') return '1f496';
    if (emoji == '🍿') return '1f37f';
    if (emoji == '💡') return '1f4a1';
    if (emoji == '🎵') return '1f3b5';
    return '1f600';
  }

  static const _demoImages = [
    'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=300',
    'https://images.unsplash.com/photo-1551632811-561732d1e306?w=300',
    'https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?w=300',
    'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=300',
    'https://images.unsplash.com/photo-1524250502761-1ac6f2e30d43?w=300',
    'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=300',
  ];

  @override
  void initState() {
    super.initState();
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Listen to changes in typing to dynamically toggle mic vs send icon
    _messageController.addListener(() {
      if (mounted) setState(() {});
    });

    // Scroll to bottom when messages first load
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    _loadGiphyApiKey();

    // Mark as loaded after a brief delay (simulates initial load)
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _giphyDebounce?.cancel();
    _recordTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _typingController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadGiphyApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _customGiphyApiKey = prefs.getString('giphy_api_key');
      });
      if (_customGiphyApiKey != null && _customGiphyApiKey!.isNotEmpty) {
        _fetchGiphyContent();
      }
    } catch (e) {
      print('Error loading Giphy key: $e');
    }
  }

  Future<void> _saveGiphyApiKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('giphy_api_key', key.trim());
      setState(() {
        _customGiphyApiKey = key.trim();
        _giphyError = null;
      });
      _fetchGiphyContent();
    } catch (e) {
      print('Error saving Giphy key: $e');
    }
  }

  Future<void> _fetchGiphyContent() async {
    final apiKey = _customGiphyApiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    setState(() {
      _giphyLoading = true;
      _giphyError = null;
    });

    try {
      final isGif = _keyboardTab == 2;
      final q = _giphySearchQuery.trim();
      
      final String url;
      if (q.isEmpty) {
        url = isGif
            ? 'https://api.giphy.com/v1/gifs/trending?api_key=$apiKey&limit=24&rating=pg-13'
            : 'https://api.giphy.com/v1/stickers/trending?api_key=$apiKey&limit=24&rating=pg-13';
      } else {
        url = isGif
            ? 'https://api.giphy.com/v1/gifs/search?api_key=$apiKey&q=${Uri.encodeComponent(q)}&limit=24&rating=pg-13'
            : 'https://api.giphy.com/v1/stickers/search?api_key=$apiKey&q=${Uri.encodeComponent(q)}&limit=24&rating=pg-13';
      }

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = decoded['data'] as List<dynamic>;
        setState(() {
          if (isGif) {
            _giphyGifs = list;
          } else {
            _giphyStickers = list;
          }
          _giphyLoading = false;
        });
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() {
          _giphyError = 'Unauthorized: Invalid GIPHY API key.';
          _giphyLoading = false;
        });
      } else {
        setState(() {
          _giphyError = 'Failed to load GIPHY content (Error ${response.statusCode}).';
          _giphyLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _giphyError = 'Connection failed. Please check your internet connection.';
        _giphyLoading = false;
      });
    }
  }

  void _onGiphySearchChanged(String val) {
    _giphyDebounce?.cancel();
    _giphyDebounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _giphySearchQuery = val;
      });
      _fetchGiphyContent();
    });
  }

  void _sendGif(String gifUrl) {
    HapticFeedback.lightImpact();
    final currentUser = ref.read(currentUserProvider);
    final newMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: currentUser.id,
      text: '🎬 Sent a GIF',
      imageUrl: gifUrl,
      createdAt: DateTime.now(),
      isRead: false,
      type: MessageType.image,
    );

    ref.read(chatMessagesNotifierProvider(widget.chatId).notifier).addMessage(newMessage);
    ref.read(chatsProvider.notifier).updateLastMessage(widget.chatId, '🎬 Sent a GIF', DateTime.now());
    _scrollToBottom();
  }

  Widget _buildMessagesLoadingSkeleton(bool isDark) {
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        itemCount: 5,
        itemBuilder: (context, index) {
          final isMe = index % 2 == 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: isMe ? 150 : 180,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _sendMessage([String? overrideText]) async {
    final text = (overrideText ?? _messageController.text).trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    final currentUser = ref.read(currentUserProvider);

    final newMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: currentUser.id, // use real UID
      text: text,
      createdAt: DateTime.now(),
      isRead: false,
    );

    _messageController.clear();
    _scrollToBottom();

    try {
      await ref.read(chatMessagesNotifierProvider(widget.chatId).notifier).addMessage(newMessage);
      ref.read(chatsProvider.notifier).updateLastMessage(widget.chatId, text, DateTime.now());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send message. Check Firebase Rules! \nError: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _sendImage(String imageUrl) {
    HapticFeedback.lightImpact();
    final currentUser = ref.read(currentUserProvider);
    final newMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: currentUser.id,
      text: '📸 Sent a photo',
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
      isRead: false,
      type: MessageType.image,
    );

    ref.read(chatMessagesNotifierProvider(widget.chatId).notifier).addMessage(newMessage);
    ref.read(chatsProvider.notifier).updateLastMessage(widget.chatId, '📸 Sent a photo', DateTime.now());
    _scrollToBottom();
  }

  void _sendSticker(String stickerUrl) {
    HapticFeedback.lightImpact();
    final currentUser = ref.read(currentUserProvider);
    final newMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: currentUser.id,
      text: '🎨 Sent a sticker',
      imageUrl: stickerUrl,
      createdAt: DateTime.now(),
      isRead: false,
      type: MessageType.sticker,
    );

    ref.read(chatMessagesNotifierProvider(widget.chatId).notifier).addMessage(newMessage);
    ref.read(chatsProvider.notifier).updateLastMessage(widget.chatId, '🎨 Sent a sticker', DateTime.now());
    _scrollToBottom();
  }

  void _sendVoiceNote(int duration, [String? audioUrl]) {
    if (duration == 0) return;
    HapticFeedback.lightImpact();
    final currentUser = ref.read(currentUserProvider);
    final newMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: currentUser.id,
      text: '${duration}s',
      imageUrl: audioUrl ?? 'audio_note',
      createdAt: DateTime.now(),
      isRead: false,
      type: MessageType.audio,
    );

    ref.read(chatMessagesNotifierProvider(widget.chatId).notifier).addMessage(newMessage);
    ref.read(chatsProvider.notifier).updateLastMessage(widget.chatId, '🎙️ Voice note (${duration}s)', DateTime.now());
    _scrollToBottom();
  }

  void _startRecording() async {
    HapticFeedback.heavyImpact();
    _isUsingSimulatedMic = false;
    
    try {
      final success = await startJsRecording();
      if (success == false) {
        _isUsingSimulatedMic = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎙️ Sandbox Mode: Simulated voice recording active!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Mic start recording error (falling back to simulation): $e');
      _isUsingSimulatedMic = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎙️ Sandbox Mode: Simulated voice recording active!'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _isRecording = true;
      _recordDuration = 0;
      _showEmoji = false;
    });
    
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordDuration++;
        });
      }
    });
  }

  void _cancelRecording() async {
    HapticFeedback.selectionClick();
    _recordTimer?.cancel();
    
    try {
      await stopJsRecording();
    } catch (e) {
      print('Mic cancel recording error: $e');
    }

    setState(() {
      _isRecording = false;
      _recordDuration = 0;
    });
  }

  void _stopAndSendRecording() async {
    HapticFeedback.mediumImpact();
    _recordTimer?.cancel();
    final duration = _recordDuration;
    
    setState(() {
      _isRecording = false;
      _recordDuration = 0;
    });

    if (_isUsingSimulatedMic) {
      if (duration > 0) {
        final simulatedAudioUrl = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
        _sendVoiceNote(duration, simulatedAudioUrl);
      }
      return;
    }

    try {
      final localAudioUrl = await stopJsRecording();
      if (duration > 0 && localAudioUrl != null && localAudioUrl.isNotEmpty) {
        String finalUrl = localAudioUrl;
        
        try {
          final response = await http.get(Uri.parse(localAudioUrl));
          final bytes = response.bodyBytes;
          
          if (bytes.isNotEmpty) {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('chats/${widget.chatId}/voice_${DateTime.now().millisecondsSinceEpoch}.webm');
            
            final uploadTask = storageRef.putData(
              bytes,
              SettableMetadata(contentType: 'audio/webm'),
            );
            
            final snapshot = await uploadTask;
            final downloadUrl = await snapshot.ref.getDownloadURL();
            if (downloadUrl.isNotEmpty) {
              finalUrl = downloadUrl;
            }
          }
        } catch (storageError) {
          print('Firebase Storage Voice upload error (falling back to local): $storageError');
        }

        _sendVoiceNote(duration, finalUrl);
      }
    } catch (e) {
      print('Mic stop recording error: $e');
    }
  }

  void _showImagePicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('Send a Photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _demoImages.length,
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _sendImage(_demoImages[i]);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(_demoImages[i], fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCallDialog(bool isVideo) {
    final name = widget.userData['name'] as String? ?? 'User';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isVideo ? '📹 Video Call' : '📞 Voice Call', style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Text('Starting ${isVideo ? 'video' : 'voice'} call with $name...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${isVideo ? "Video" : "Voice"} calls coming soon ✨'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: Text(isVideo ? 'Start Video' : 'Start Call'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesNotifierProvider(widget.chatId));
    final currentUser = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = widget.userData['name'] as String? ?? 'User';
    final avatarUrl = widget.userData['avatarUrl'] as String?;
    final isOnline = widget.userData['isOnline'] as bool? ?? false;

    // Scroll to bottom when new messages arrive
    if (messages.isNotEmpty) {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF5F7FF),
      appBar: _buildAppBar(context, name, avatarUrl, isOnline, isDark),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? _buildMessagesLoadingSkeleton(isDark)
                : messages.isEmpty && !_isTypingLocal
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          avatarUrl != null ? '💬' : '👋',
                          style: const TextStyle(fontSize: 48),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Say hi to $name!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Be the first to send a message ✨',
                          style: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length + (_isTypingLocal ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_isTypingLocal && index == messages.length) {
                        return _TypingIndicator(
                          controller: _typingController,
                          avatarUrl: avatarUrl,
                        );
                      }
                      final msg = messages[index];
                      final isMe = msg.senderId == currentUser.id;
                      return _MessageBubble(
                        message: msg,
                        isMe: isMe,
                        otherAvatarUrl: avatarUrl,
                      );
                    },
                  ),
          ),
          if (_showEmoji) _buildEmojiBar(isDark),
          _buildInputBar(context, isDark),
        ],
      ),
    );
  }

  AppBar _buildAppBar(
    BuildContext context,
    String name,
    String? avatarUrl,
    bool isOnline,
    bool isDark,
  ) {
    return AppBar(
      backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage(
                  avatarUrl ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&size=100&background=6ECBF5&color=fff&rounded=true',
                ),
              ),
              if (isOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                _isTypingLocal
                    ? 'typing...'
                    : isOnline
                        ? 'Active now'
                        : 'Last seen recently',
                style: TextStyle(
                  fontSize: 12,
                  color: _isTypingLocal
                      ? AppTheme.accentPink
                      : isOnline
                          ? AppTheme.success
                          : AppTheme.textTertiary,
                  fontWeight: _isTypingLocal ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () => _showCallDialog(true),
          icon: const Icon(Icons.videocam_outlined, size: 24),
        ),
        IconButton(
          onPressed: () => _showCallDialog(false),
          icon: const Icon(Icons.call_outlined, size: 22),
        ),
      ],
    );
  }

  Widget _buildEmojiBar(bool isDark) {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
      ),
      child: Column(
        children: [
          // Keyboard Tabs
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTabButton(0, '🌈 Emojis', isDark),
                  const SizedBox(width: 8),
                  _buildTabButton(1, '🎨 3D Packs', isDark),
                  const SizedBox(width: 8),
                  _buildTabButton(2, '🎭 Live Stickers', isDark),
                  const SizedBox(width: 8),
                  _buildTabButton(3, '🎬 Live GIFs', isDark),
                ],
              ),
            ),
          ),
          // Tab Contents
          Expanded(
            child: _keyboardTab == 0
                ? GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _emojiQuickPicks.length,
                    itemBuilder: (_, i) {
                      final hex = _emojiToHex(_emojiQuickPicks[i]);
                      final imgUrl = 'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u$hex.png';
                      return GestureDetector(
                        onTap: () => _sendMessage(_emojiQuickPicks[i]),
                        child: Center(
                          child: Image.network(
                            imgUrl,
                            width: 38,
                            height: 38,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Text(
                              _emojiQuickPicks[i],
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : _keyboardTab == 1
                    ? Column(
                        children: [
                          // Sticker Grid Content
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _selectedStickerPack == 0
                                  ? _packEmojis.length
                                  : _selectedStickerPack == 1
                                      ? _packAnimals.length
                                      : _selectedStickerPack == 2
                                          ? _packFood.length
                                          : _packObjects.length,
                              itemBuilder: (_, i) {
                                final pack = _selectedStickerPack == 0
                                    ? _packEmojis
                                    : _selectedStickerPack == 1
                                        ? _packAnimals
                                        : _selectedStickerPack == 2
                                            ? _packFood
                                            : _packObjects;
                                final sticker = pack[i];
                                return GestureDetector(
                                  onTap: () => _sendSticker(sticker['url']!),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    padding: const EdgeInsets.all(10),
                                    child: Image.network(
                                      sticker['url']!,
                                      fit: BoxFit.contain,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)));
                                      },
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Text(
                                          sticker['emoji']!,
                                          style: const TextStyle(fontSize: 28),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // WhatsApp Style Sticker Pack Selector Bar
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkCard : const Color(0xFFF0F4FF),
                              border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStickerPackTabButton(0, '😊 Emojis', isDark),
                                _buildStickerPackTabButton(1, '🐱 Animals', isDark),
                                _buildStickerPackTabButton(2, '🍕 Food', isDark),
                                _buildStickerPackTabButton(3, '🚀 Objects', isDark),
                              ],
                            ),
                          ),
                        ],
                      )
                    : (_customGiphyApiKey == null || _customGiphyApiKey!.isEmpty)
                        ? _buildGiphyActivationView(isDark, _keyboardTab == 2)
                        : _buildGiphyGridView(isDark, _keyboardTab == 2),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerPackTabButton(int index, String label, bool isDark) {
    final active = _selectedStickerPack == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedStickerPack = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active 
              ? (isDark ? Colors.white24 : AppTheme.primaryBlue.withOpacity(0.15))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            color: active ? AppTheme.primaryBlue : (isDark ? Colors.white70 : AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, bool isDark) {
    final active = _keyboardTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _keyboardTab = index;
        });
        if ((index == 2 || index == 3) && _customGiphyApiKey != null && _customGiphyApiKey!.isNotEmpty) {
          _fetchGiphyContent();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active 
              ? (isDark ? Colors.white10 : AppTheme.primaryBlue.withOpacity(0.1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: active ? AppTheme.primaryBlue : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildGiphyActivationView(bool isDark, bool isSticker) {
    final controller = TextEditingController();
    return Container(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSticker ? Icons.star_border : Icons.gif_box_outlined,
                size: 48,
                color: AppTheme.primaryBlue,
              ),
              const SizedBox(height: 12),
              Text(
                isSticker ? 'Unlock Live GIPHY Stickers 🎭' : 'Unlock Live GIPHY GIFs 🎬',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Situationship searches millions of trending stickers and GIFs via Giphy. Enter your Giphy API key to get started:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Paste Giphy API Key here...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      openJsUrl('https://developers.giphy.com/dashboard/');
                    },
                    child: const Text(
                      'Get API Key (Free) ➔',
                      style: TextStyle(fontSize: 12, color: AppTheme.primaryBlue),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final key = controller.text.trim();
                      if (key.isNotEmpty) {
                        _saveGiphyApiKey(key);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Save & Load', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGiphyGridView(bool isDark, bool isSticker) {
    final list = isSticker ? _giphyStickers : _giphyGifs;
    return Column(
      children: [
        // Giphy Search Bar with Settings icon to clear key
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextField(
                    onChanged: _onGiphySearchChanged,
                    decoration: InputDecoration(
                      hintText: isSticker ? '🔍 Search animated stickers...' : '🔍 Search animated GIFs...',
                      hintStyle: TextStyle(color: isDark ? Colors.white54 : AppTheme.textSecondary, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    ),
                    style: TextStyle(color: isDark ? Colors.white : AppTheme.textPrimary, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Option to reset/change API key
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Reset GIPHY Key?'),
                      content: const Text('Are you sure you want to change or remove your Giphy API key?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _saveGiphyApiKey('');
                          },
                          child: const Text('Reset', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.settings, size: 18, color: isDark ? Colors.white70 : AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
        // Grid or Loading/Error/Empty States
        Expanded(
          child: _giphyLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue))
              : _giphyError != null
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, color: Colors.red[300], size: 36),
                          const SizedBox(height: 8),
                          Text(
                            _giphyError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => _saveGiphyApiKey(''),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                            child: const Text('Reset API Key', style: TextStyle(fontSize: 11, color: Colors.white)),
                          )
                        ],
                      ),
                    )
                  : list.isEmpty
                      ? Center(
                          child: Text(
                            'No results found. Try another search!',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : AppTheme.textSecondary),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isSticker ? 4 : 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final item = list[i];
                            final images = item['images'];
                            final String url = images['fixed_height']['url'] ?? images['downsized']['url'] ?? '';
                            
                            return GestureDetector(
                              onTap: () {
                                if (isSticker) {
                                  _sendSticker(url);
                                } else {
                                  _sendGif(url);
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)));
                                  },
                                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 20)),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildInputBar(BuildContext context, bool isDark) {
    final showSend = _messageController.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (!_isRecording) ...[
              IconButton(
                onPressed: () => setState(() => _showEmoji = !_showEmoji),
                icon: Icon(
                  _showEmoji ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                  color: _showEmoji ? AppTheme.primaryBlue : AppTheme.textSecondary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: _isRecording
                    ? Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '0:${_recordDuration.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(child: _RecordingEqualizer()),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _cancelRecording,
                            child: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 22),
                          ),
                        ],
                      )
                    : TextField(
                        controller: _messageController,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 15),
                        onTap: () => setState(() => _showEmoji = false),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 15),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            if (!_isRecording) ...[
              IconButton(
                onPressed: _showImagePicker,
                icon: Icon(Icons.image_outlined, color: AppTheme.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 4),
            ],
            GestureDetector(
              onTap: _isRecording 
                  ? _stopAndSendRecording 
                  : (showSend ? () => _sendMessage() : _startRecording),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: _isRecording 
                      ? const LinearGradient(colors: [Color(0xFFFF5252), Color(0xFFFF1744)]) 
                      : AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : AppTheme.primaryBlue).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording 
                      ? Icons.check_rounded 
                      : (showSend ? Icons.send_rounded : Icons.mic_rounded), 
                  color: Colors.white, 
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final String? otherAvatarUrl;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.otherAvatarUrl,
  });

  static const _emojiQuickPicks = [
    '😊', '🔥', '✨', '😂', '🥺', '💫', '❤️', '🙏', '👀', '🎉', '😍', '💬',
    '👍', '🙌', '💯', '🚀', '⭐', '🎈', '🍕', '🍻', '💖', '🍿', '💡', '🎵'
  ];

  static String _emojiToHex(String emoji) {
    if (emoji == '😊') return '1f60a';
    if (emoji == '🔥') return '1f525';
    if (emoji == '✨') return '2728';
    if (emoji == '😂') return '1f602';
    if (emoji == '🥺') return '1f97a';
    if (emoji == '💫') return '1f4ab';
    if (emoji == '❤️') return '2764';
    if (emoji == '🙏') return '1f64f';
    if (emoji == '👀') return '1f440';
    if (emoji == '🎉') return '1f389';
    if (emoji == '😍') return '1f60d';
    if (emoji == '💬') return '1f4ac';
    if (emoji == '👍') return '1f44d';
    if (emoji == '🙌') return '1f64c';
    if (emoji == '💯') return '1f4af';
    if (emoji == '🚀') return '1f680';
    if (emoji == '⭐') return '2b50';
    if (emoji == '🎈') return '1f388';
    if (emoji == '🍕') return '1f355';
    if (emoji == '🍻') return '1f37b';
    if (emoji == '💖') return '1f496';
    if (emoji == '🍿') return '1f37f';
    if (emoji == '💡') return '1f4a1';
    if (emoji == '🎵') return '1f3b5';
    return '1f600';
  }

  List<Widget> _buildEmojiText(String text, double size) {
    if (text.isEmpty) return [];
    final runesList = text.runes.toList();
    final List<String> chars = [];
    for (var rune in runesList) {
      chars.add(String.fromCharCode(rune));
    }
    
    bool allQuickPicks = true;
    for (final char in chars) {
      if (!_emojiQuickPicks.contains(char)) {
        allQuickPicks = false;
        break;
      }
    }

    if (allQuickPicks && chars.isNotEmpty) {
      return chars.map((char) {
        final hex = _emojiToHex(char);
        final imgUrl = 'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u$hex.png';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Image.network(
            imgUrl,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text(char, style: TextStyle(fontSize: size - 8)),
          ),
        );
      }).toList();
    }
    return [];
  }

  Widget _buildMessageTextWithColorEmojis(String text, bool isMe, bool isDark) {
    final List<InlineSpan> spans = [];
    final runesList = text.runes.toList();
    String currentText = '';
    
    for (int i = 0; i < runesList.length; i++) {
      final char = String.fromCharCode(runesList[i]);
      if (_emojiQuickPicks.contains(char)) {
        if (currentText.isNotEmpty) {
          spans.add(TextSpan(
            text: currentText,
            style: TextStyle(
              color: isMe ? Colors.white : (isDark ? Colors.white : AppTheme.textPrimary),
              fontSize: 15,
              height: 1.4,
            ),
          ));
          currentText = '';
        }
        
        final hex = _emojiToHex(char);
        final imgUrl = 'https://raw.githubusercontent.com/googlefonts/noto-emoji/main/png/128/emoji_u$hex.png';
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Image.network(
              imgUrl,
              width: 22,
              height: 22,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Text(
                char,
                style: TextStyle(
                  fontSize: 15,
                  color: isMe ? Colors.white : (isDark ? Colors.white : AppTheme.textPrimary),
                ),
              ),
            ),
          ),
        ));
      } else {
        currentText += char;
      }
    }
    
    if (currentText.isNotEmpty) {
      spans.add(TextSpan(
        text: currentText,
        style: TextStyle(
          color: isMe ? Colors.white : (isDark ? Colors.white : AppTheme.textPrimary),
          fontSize: 15,
          height: 1.4,
        ),
      ));
    }
    
    return RichText(
      text: TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final time = DateFormat('h:mm a').format(message.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 14,
              backgroundImage: NetworkImage(
                otherAvatarUrl ?? 'https://ui-avatars.com/api/?name=User&size=100&background=6ECBF5&color=fff&rounded=true',
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (message.type == MessageType.image && message.imageUrl != null)
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.6,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                      child: Image.network(message.imageUrl!, fit: BoxFit.cover),
                    ),
                  )
                else if (message.type == MessageType.sticker && message.imageUrl != null)
                  Container(
                    constraints: const BoxConstraints(
                      maxWidth: 130,
                      maxHeight: 130,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Image.network(message.imageUrl!, fit: BoxFit.contain),
                  )
                else if (message.type == MessageType.audio)
                  VoiceNotePlayer(message: message, isMe: isMe)
                else
                  Builder(
                    builder: (context) {
                      final emojiWidgets = _buildEmojiText(message.text, 36);
                      if (emojiWidgets.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: emojiWidgets,
                          ),
                        );
                      }
                      return Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.68,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: isMe ? AppTheme.primaryGradient : null,
                          color: isMe
                              ? null
                              : isDark
                                  ? AppTheme.darkCard
                                  : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(isMe ? 18 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildMessageTextWithColorEmojis(message.text, isMe, isDark),
                      );
                    }
                  ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(fontSize: 10, color: AppTheme.textTertiary),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isRead ? Icons.done_all : Icons.done,
                        size: 12,
                        color: message.isRead ? AppTheme.primaryBlue : AppTheme.textTertiary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final AnimationController controller;
  final String? avatarUrl;

  const _TypingIndicator({required this.controller, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundImage: NetworkImage(
              avatarUrl ?? 'https://ui-avatars.com/api/?name=User&size=100&background=6ECBF5&color=fff&rounded=true',
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) {
                    final delay = index * 0.33;
                    final rawVal = controller.value - delay;
                    final value = rawVal < 0 ? rawVal + 1.0 : rawVal;
                    final bounce = value < 0.5 ? value * 2 : (1 - value) * 2;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.translate(
                        offset: Offset(0, -5 * bounce),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class VoiceNotePlayer extends StatefulWidget {
  final MessageModel message;
  final bool isMe;

  const VoiceNotePlayer({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isPlaying = false;
  int _currentSeconds = 0;
  Timer? _playbackTimer;

  // Generate deterministic waveform heights based on message ID hash
  late final List<double> _waveformHeights;

  @override
  void initState() {
    super.initState();
    final rand = Random(widget.message.id.hashCode);
    _waveformHeights = List.generate(20, (_) => 5.0 + rand.nextDouble() * 20.0);

    // Duration is stored in message.text like "5s"
    final durationSeconds = int.tryParse(widget.message.text.replaceAll('s', '')) ?? 5;

    _animController = AnimationController(
      vsync: this,
      duration: Duration(seconds: durationSeconds),
    );

    _animController.addListener(() {
      setState(() {});
    });

    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _stopPlayback();
      }
    });
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    HapticFeedback.lightImpact();
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _startPlayback();
    }
  }

  void _startPlayback() {
    final durationSeconds = int.tryParse(widget.message.text.replaceAll('s', '')) ?? 5;
    setState(() {
      _isPlaying = true;
    });

    if (_animController.value >= 1.0) {
      _animController.reset();
      _currentSeconds = 0;
    }

    _animController.forward();

    // Start real HTML5 Audio playback if imageUrl contains a valid blob/url!
    if (widget.message.imageUrl != null && widget.message.imageUrl != 'audio_note') {
      try {
        playJsAudio(widget.message.imageUrl!);
      } catch (e) {
        print('Real audio playback error: $e');
      }
    }

    _playbackTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentSeconds < durationSeconds) {
        setState(() {
          _currentSeconds++;
        });
      } else {
        _playbackTimer?.cancel();
      }
    });
  }

  void _pausePlayback() {
    _animController.stop();
    _playbackTimer?.cancel();
    
    // Pause real HTML5 Audio playback via JS!
    try {
      pauseJsAudio();
    } catch (e) {
      print('Real audio pause error: $e');
    }

    setState(() {
      _isPlaying = false;
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    
    // Stop real HTML5 Audio playback via JS!
    try {
      pauseJsAudio();
    } catch (e) {
      print('Real audio stop error: $e');
    }

    setState(() {
      _isPlaying = false;
      _currentSeconds = 0;
      _animController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = widget.isMe ? Colors.white : AppTheme.primaryBlue;
    final totalSeconds = int.tryParse(widget.message.text.replaceAll('s', '')) ?? 5;
    
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: widget.isMe ? AppTheme.primaryGradient : null,
        color: widget.isMe ? null : (isDark ? AppTheme.darkCard : Colors.white),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play/Pause button
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white.withOpacity(0.2) : AppTheme.primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: themeColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Waveform and progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Waveform rendering
                SizedBox(
                  height: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_waveformHeights.length, (i) {
                      final progress = _animController.value;
                      final targetProgress = i / _waveformHeights.length;
                      final isPlayed = progress > targetProgress;
                      
                      return Container(
                        width: 2.2,
                        height: _waveformHeights[i],
                        decoration: BoxDecoration(
                          color: isPlayed
                              ? (widget.isMe ? Colors.white : AppTheme.accentPink)
                              : (widget.isMe ? Colors.white30 : (isDark ? Colors.white10 : Colors.black12)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 4),
                // Time tracker
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '0:${_currentSeconds.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 9,
                        color: widget.isMe ? Colors.white70 : AppTheme.textTertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '0:${totalSeconds.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 9,
                        color: widget.isMe ? Colors.white70 : AppTheme.textTertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.mic_rounded,
            color: widget.isMe ? Colors.white70 : AppTheme.primaryBlue.withOpacity(0.6),
            size: 14,
          ),
        ],
      ),
    );
  }
}

class _RecordingEqualizer extends StatefulWidget {
  const _RecordingEqualizer();

  @override
  State<_RecordingEqualizer> createState() => _RecordingEqualizerState();
}

class _RecordingEqualizerState extends State<_RecordingEqualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _heights = [10, 20, 7, 15, 24, 12, 18, 9];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_heights.length, (index) {
            final val = _controller.value;
            final height = _heights[index] * (0.3 + 0.7 * sin(val * pi + index));
            return Container(
              width: 2.5,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              decoration: BoxDecoration(
                color: AppTheme.accentPink,
                borderRadius: BorderRadius.circular(1.2),
              ),
            );
          }),
        );
      },
    );
  }
}
