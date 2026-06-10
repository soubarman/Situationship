import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'overlay_manager.dart';

class TextEditorOverlay extends StatefulWidget {
  final OverlayItem? initialItem;

  const TextEditorOverlay({super.key, this.initialItem});

  @override
  State<TextEditorOverlay> createState() => _TextEditorOverlayState();
}

class _TextEditorOverlayState extends State<TextEditorOverlay> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  
  String _fontFamily = 'Inter';
  Color _color = Colors.white;
  bool _hasBackground = false;
  
  // A few safe web/mobile fonts
  final List<String> _fonts = ['Inter', 'Courier', 'Times New Roman', 'Cursive', 'Impact'];
  final List<Color> _colors = [
    Colors.white, Colors.black, AppTheme.accentPurple, Colors.blue, 
    Colors.green, Colors.yellow, Colors.orange, Colors.red
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialItem?.content ?? '');
    _fontFamily = widget.initialItem?.fontFamily ?? 'Inter';
    _color = widget.initialItem?.color ?? Colors.white;
    _hasBackground = widget.initialItem?.hasBackground ?? false;
    
    _focusNode = FocusNode();
    Future.delayed(const Duration(milliseconds: 100), () => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onDone() {
    if (_controller.text.trim().isEmpty) {
      Navigator.pop(context, null);
      return;
    }
    
    final item = OverlayItem(
      id: widget.initialItem?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      isText: true,
      content: _controller.text,
      position: widget.initialItem?.position ?? const Offset(100, 200),
      scale: widget.initialItem?.scale ?? 1.0,
      rotation: widget.initialItem?.rotation ?? 0.0,
      fontFamily: _fontFamily,
      color: _color,
      hasBackground: _hasBackground,
    );
    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.6),
      body: SafeArea(
        child: Column(
          children: [
            // Top Controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _hasBackground ? Icons.font_download : Icons.font_download_outlined,
                          color: Colors.white,
                        ),
                        onPressed: () => setState(() => _hasBackground = !_hasBackground),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: _onDone,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Font picker
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _fonts.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (ctx, i) {
                  final f = _fonts[i];
                  final sel = _fontFamily == f;
                  return GestureDetector(
                    onTap: () => setState(() => _fontFamily = f),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? Colors.white : Colors.white24,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontFamily: f,
                          color: sel ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const Spacer(),

            // Text Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                maxLines: null,
                style: TextStyle(
                  fontFamily: _fontFamily,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _hasBackground && _color == Colors.white ? Colors.black : _color,
                  backgroundColor: _hasBackground 
                      ? (_color == Colors.white || _color == Colors.transparent ? Colors.black87 : Colors.white)
                      : null,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Type something...',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
            ),

            const Spacer(),

            // Color picker
            Container(
              height: 50,
              margin: const EdgeInsets.only(bottom: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _colors.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (ctx, i) {
                  final c = _colors[i];
                  final sel = _color == c;
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 4)
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
