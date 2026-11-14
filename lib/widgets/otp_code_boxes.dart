import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/custom_colors.dart';

/// One box per OTP digit. A single transparent text field sits on top, so
/// typing moves to the next box, backspace moves back, pasting a full code
/// fills every box, and keyboard OTP suggestions (one-time-code autofill on
/// iOS and web) work like a normal field.
class OtpCodeBoxes extends StatefulWidget {
  const OtpCodeBoxes({
    super.key,
    required this.controller,
    this.length = 4,
    this.focusNode,
    this.enabled = true,
    this.onCompleted,
  });

  final TextEditingController controller;
  final int length;
  final FocusNode? focusNode;
  final bool enabled;
  final ValueChanged<String>? onCompleted;

  static const Key inputKey = Key('otp-code-input');

  @override
  State<OtpCodeBoxes> createState() => _OtpCodeBoxesState();
}

class _OtpCodeBoxesState extends State<OtpCodeBoxes> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Enter ${widget.length}-digit OTP',
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, value, _) {
          final code = value.text;
          final active = code.length.clamp(0, widget.length - 1);
          return Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    _box(
                      i < code.length ? code[i] : '',
                      highlighted:
                          widget.enabled && _focus.hasFocus && i == active,
                    ),
                  ],
                ],
              ),
              Positioned.fill(
                child: TextField(
                  key: OtpCodeBoxes.inputKey,
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  showCursor: false,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(color: Colors.transparent),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (text) {
                    if (text.length == widget.length) {
                      widget.onCompleted?.call(text);
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _box(String digit, {required bool highlighted}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 54,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CustomColors.fieldBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? CustomColors.primary : CustomColors.border,
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: CustomColors.text,
        ),
      ),
    );
  }
}
