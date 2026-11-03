import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/stay_duration.dart';

/// Refreshes display only; no periodic Firebase writes or local counters.
class LiveStayDuration extends StatefulWidget {
  const LiveStayDuration({
    super.key,
    required this.start,
    this.checkout,
    this.prefix = '',
    this.style,
    this.now = DateTime.now,
  });
  final DateTime? start, checkout;
  final String prefix;
  final TextStyle? style;
  final DateTime Function() now;
  @override
  State<LiveStayDuration> createState() => _LiveStayDurationState();
}

class _LiveStayDurationState extends State<LiveStayDuration> {
  Timer? _timer;
  String _label = '';
  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant LiveStayDuration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start ||
        oldWidget.checkout != widget.checkout) {
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    _label = stayDurationLabel(
      widget.start,
      checkout: widget.checkout,
      now: widget.now(),
    );
    if (widget.start != null && widget.checkout == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final next = stayDurationLabel(widget.start, now: widget.now());
        if (mounted && next != _label) setState(() => _label = next);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    '${widget.prefix}$_label',
    style: widget.style,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}
