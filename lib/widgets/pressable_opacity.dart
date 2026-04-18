import 'package:flutter/material.dart';

/// 按壓效果包裝組件
/// 點擊時透明度變為 0.7，鬆開還原，用於按鈕等交互
class PressableOpacity extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;

  const PressableOpacity({
    super.key,
    required this.child,
    this.onPressed,
  });

  @override
  State<PressableOpacity> createState() => _PressableOpacityState();
}

class _PressableOpacityState extends State<PressableOpacity> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        enableFeedback: false,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        onTapDown: (_) {
          setState(() => _pressed = true);
        },
        onTapUp: (_) {
          setState(() => _pressed = false);
        },
        onTapCancel: () {
          setState(() => _pressed = false);
        },
        onTap: widget.onPressed,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.7 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: widget.child,
        ),
      ),
    );
  }
}
