import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// 帶按壓效果的自定義按鈕
/// 點擊時透明度變為 0.7，鬆開還原，圓角 20px
class CustomButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool primary;
  final double? width;
  final double height;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.primary = true,
    this.width,
    this.height = 50,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.primary ? AppConstants.primaryColor : AppConstants.white;
    final fgColor =
        widget.primary ? AppConstants.white : AppConstants.primaryColor;
    final border =
        widget.primary ? null : Border.all(color: AppConstants.primaryColor);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedOpacity(
        opacity: _pressed ? 0.7 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: widget.width ?? double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            color: bgColor,
            border: border,
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
          child: Center(
            child: Text(
              widget.text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: fgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
