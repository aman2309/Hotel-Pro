import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Uses available layout space, including split windows and the open keyboard.
class ResponsiveUi {
  const ResponsiveUi(this.size);
  final Size size;

  bool get isPhone => size.width < 600;
  bool get isTablet => size.width >= 600 && size.width < 1024;
  bool get isDesktop => size.width >= 1024;
  bool get isCompact => size.width < 360;
  bool get isShort => size.height < 600;

  T value<T>({required T phone, T? tablet, T? desktop}) {
    if (isDesktop) return desktop ?? tablet ?? phone;
    if (isTablet) return tablet ?? phone;
    return phone;
  }

  double get horizontalPadding =>
      isCompact ? 16 : value(phone: 24.0, tablet: 40.0, desktop: 56.0);
  double get verticalPadding =>
      isShort ? 16 : value(phone: 24.0, tablet: 36.0, desktop: 48.0);
}

/// Scrolls when content, keyboard, or larger text needs more vertical space.
/// Centers short content while keeping forms at a readable width on large screens.
class ResponsivePage extends StatelessWidget {
  const ResponsivePage({
    super.key,
    required this.builder,
    this.maxContentWidth = 460,
  });
  final Widget Function(BuildContext context, ResponsiveUi ui) builder;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ui = ResponsiveUi(
            Size(constraints.maxWidth, constraints.maxHeight),
          );
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.symmetric(
              horizontal: ui.horizontalPadding,
              vertical: ui.verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  constraints.maxHeight - ui.verticalPadding * 2,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: SizedBox(
                    width: double.infinity,
                    child: builder(context, ui),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
