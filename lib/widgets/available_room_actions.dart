import 'package:flutter/material.dart';
import 'custom_button.dart';

/// Full-width, naturally sized actions; labels can grow with accessibility text.
class AvailableRoomActions extends StatefulWidget {
  const AvailableRoomActions({
    super.key,
    required this.onBook,
    required this.onClose,
  });
  final VoidCallback onBook;
  final Future<void> Function() onClose;
  @override
  State<AvailableRoomActions> createState() => _AvailableRoomActionsState();
}

class _AvailableRoomActionsState extends State<AvailableRoomActions> {
  bool _busy = false;
  Future<void> _close() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onClose();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not close the room. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CustomButton.icon(
        onPressed: _busy ? null : widget.onBook,
        icon: const Icon(Icons.book_online_rounded),
        label: const Text('Book room'),
      ),
      const SizedBox(height: 12),
      CustomButton.outlineIcon(
        onPressed: _busy ? null : _close,
        icon: const Icon(Icons.lock_outline_rounded, size: 18),
        label: Text(_busy ? 'Closing…' : 'Temporarily close'),
      ),
    ],
  );
}
