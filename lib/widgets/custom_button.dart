import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';

enum _ButtonKind { filled, outline, text }

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.focusNode,
    this.autofocus = false,
  }) : icon = null,
       _kind = _ButtonKind.filled;
  const CustomButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
    this.focusNode,
    this.autofocus = false,
  }) : child = label,
       _kind = _ButtonKind.filled;
  const CustomButton.outline({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.focusNode,
    this.autofocus = false,
  }) : icon = null,
       _kind = _ButtonKind.outline;
  const CustomButton.outlineIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.style,
    this.focusNode,
    this.autofocus = false,
  }) : child = label,
       _kind = _ButtonKind.outline;
  const CustomButton.text({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.focusNode,
    this.autofocus = false,
  }) : icon = null,
       _kind = _ButtonKind.text;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final _ButtonKind _kind;
  @override
  Widget build(BuildContext context) {
    final content = icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon!,
              const SizedBox(width: 8),
              Flexible(child: child),
            ],
          );
    final base = FilledButton.styleFrom(
      backgroundColor: _kind == _ButtonKind.filled
          ? CustomColors.button
          : CustomColors.transparent,
      foregroundColor: _kind == _ButtonKind.filled
          ? CustomColors.onButton
          : CustomColors.button,
      disabledBackgroundColor: CustomColors.disabledBackground,
      disabledForegroundColor: CustomColors.muted,
      minimumSize: const Size(48, 46),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      side: _kind == _ButtonKind.outline
          ? const BorderSide(color: CustomColors.border)
          : BorderSide.none,
    ).merge(style);
    return switch (_kind) {
      _ButtonKind.text => TextButton(
        onPressed: onPressed,
        style: base,
        focusNode: focusNode,
        autofocus: autofocus,
        child: content,
      ),
      _ButtonKind.outline => OutlinedButton(
        onPressed: onPressed,
        style: base,
        focusNode: focusNode,
        autofocus: autofocus,
        child: content,
      ),
      _ButtonKind.filled => FilledButton(
        onPressed: onPressed,
        style: base,
        focusNode: focusNode,
        autofocus: autofocus,
        child: content,
      ),
    };
  }
}
