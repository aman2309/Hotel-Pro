import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';

/// Read-only date/time control with a large tap target and consistent form spacing.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });
  final String label, value;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Semantics(
      button: true,
      label: '$label, $value',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: const Icon(Icons.expand_more_rounded),
            filled: true,
            fillColor: CustomColors.fieldBackground,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: CustomColors.border),
            ),
          ),
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, color: CustomColors.text),
          ),
        ),
      ),
    ),
  );
}
