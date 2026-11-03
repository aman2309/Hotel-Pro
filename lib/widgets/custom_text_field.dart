import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/custom_colors.dart';

/// One field style for authentication, bookings, customers, settings and dialogs.
class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    this.controller,
    this.label,
    this.icon,
    this.enabled = true,
    this.obscureText = false,
    this.onToggleVisibility,
    this.countryCode,
    this.keyboardType,
    this.autofillHints,
    this.inputFormatters,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.decoration,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.style,
    this.margin = const EdgeInsets.only(bottom: 14),
  });
  final TextEditingController? controller;
  final String? label;
  final IconData? icon;
  final bool enabled, obscureText, autofocus;
  final VoidCallback? onToggleVisibility;
  final String? countryCode;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final InputDecoration? decoration;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged, onSubmitted;
  final int? maxLength, maxLines, minLines;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final TextStyle? style;
  final EdgeInsetsGeometry margin;

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
  @override
  Widget build(BuildContext context) {
    final original = decoration ?? InputDecoration(labelText: label);
    return Padding(
      padding: margin,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        autocorrect: onToggleVisibility == null,
        enableSuggestions: onToggleVisibility == null,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        validator: validator,
        focusNode: focusNode,
        autofocus: autofocus,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        textCapitalization: textCapitalization,
        textAlign: textAlign,
        style: style ?? const TextStyle(color: CustomColors.text, fontSize: 14),
        cursorColor: CustomColors.primary,
        decoration: original.copyWith(
          labelStyle: const TextStyle(color: CustomColors.muted, fontSize: 13),
          floatingLabelStyle: const TextStyle(color: CustomColors.primary),
          errorStyle: const TextStyle(color: CustomColors.error),
          prefixIconColor: CustomColors.primary,
          suffixIconColor: CustomColors.primary,
          prefixIcon: countryCode != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        countryCode!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: CustomColors.text,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const SizedBox(
                        height: 22,
                        child: VerticalDivider(
                          width: 1,
                          color: CustomColors.border,
                        ),
                      ),
                    ],
                  ),
                )
              : original.prefixIcon ??
                    (icon == null ? null : Icon(icon, size: 21)),
          suffixIcon: onToggleVisibility == null
              ? original.suffixIcon
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller != null)
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller!,
                        builder: (context, value, _) => value.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                tooltip: 'Clear password',
                                onPressed: enabled
                                    ? () {
                                        controller!.clear();
                                        onChanged?.call('');
                                        focusNode?.requestFocus();
                                      }
                                    : null,
                                icon: const Icon(Icons.clear_rounded, size: 20),
                              ),
                      ),
                    IconButton(
                      tooltip: obscureText ? 'Show password' : 'Hide password',
                      onPressed: enabled ? onToggleVisibility : null,
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ],
                ),
          filled: true,
          fillColor: CustomColors.fieldBackground,
          contentPadding:
              original.contentPadding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          border: _border(CustomColors.border),
          enabledBorder: _border(CustomColors.border),
          disabledBorder: _border(CustomColors.border),
          focusedBorder: _border(CustomColors.primary, 2),
          errorBorder: _border(CustomColors.error),
          focusedErrorBorder: _border(CustomColors.error, 2),
        ),
      ),
    );
  }
}
