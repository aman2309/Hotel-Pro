import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';

/// Shared sheet content: fixed actions when space allows, whole-sheet scrolling
/// on short/keyboard-constrained windows so no title or action is clipped.
class CustomDialog extends StatelessWidget {
  const CustomDialog({
    super.key,
    required this.title,
    this.content,
    this.actions,
    this.icon,
    this.actionsAlignment,
    this.titlePadding,
    this.canClose = true,
    this.notice,
  });
  final Widget title;
  final Widget? content, icon, notice;
  final List<Widget>? actions;
  final MainAxisAlignment? actionsAlignment;
  final EdgeInsetsGeometry? titlePadding;
  final bool canClose;
  @override
  Widget build(BuildContext context) {
    final heading = Padding(
      padding: titlePadding ?? const EdgeInsets.fromLTRB(20, 0, 12, 12),
      child: Row(
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 12)],
          Expanded(
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: CustomColors.text,
              ),
              child: title,
            ),
          ),
          IconButton(
            tooltip: 'Close sheet',
            onPressed: canClose ? () => Navigator.of(context).pop() : null,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: CustomColors.muted,
          ),
        ],
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: content ?? const SizedBox.shrink(),
    );
    final actionBar = actions?.isNotEmpty == true
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OverflowBar(
              alignment: actionsAlignment ?? MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: actions!,
            ),
          )
        : const SizedBox.shrink();
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Semantics(liveRegion: true, child: notice!),
          ),
        actionBar,
      ],
    );
    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        height: 1.5,
        color: CustomColors.text,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxHeight < 240 ||
              (constraints.maxHeight < 400 &&
                  MediaQuery.textScalerOf(context).scale(1) > 1.5)) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, if (content != null) body, footer],
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              if (content != null)
                Flexible(child: SingleChildScrollView(child: body)),
              footer,
            ],
          );
        },
      ),
    );
  }
}
