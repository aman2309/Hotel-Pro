import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';

VoidCallback? _dismissActiveToast;

void hideAppToast() => _dismissActiveToast?.call();

/// Root overlay keeps feedback above modal sheets, keyboards and system bars.
void showAppToast(BuildContext context, String message, {bool error = true}) {
  hideAppToast();
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  bool dismissed = false;
  void dismiss() {
    if (dismissed) return;
    dismissed = true;
    if (identical(_dismissActiveToast, dismiss)) _dismissActiveToast = null;
    entry.remove();
    entry.dispose();
  }

  _dismissActiveToast = dismiss;

  entry = OverlayEntry(
    builder: (context) => _ToastLifetime(
      onTimeout: dismiss,
      child: Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          minimum: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(16),
                color: error ? CustomColors.error : CustomColors.button,
                child: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          error
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: CustomColors.onButton,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: CustomColors.onButton,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: dismiss,
                          tooltip: 'Dismiss message',
                          icon: const Icon(
                            Icons.close_rounded,
                            color: CustomColors.onButton,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

class _ToastLifetime extends StatefulWidget {
  const _ToastLifetime({required this.onTimeout, required this.child});
  final VoidCallback onTimeout;
  final Widget child;
  @override
  State<_ToastLifetime> createState() => _ToastLifetimeState();
}

class _ToastLifetimeState extends State<_ToastLifetime> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 6), widget.onTimeout);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (identical(_dismissActiveToast, widget.onTimeout)) {
      _dismissActiveToast = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
