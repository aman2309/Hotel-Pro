import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';
export 'custom_button.dart';
export 'custom_dialog.dart';
export 'custom_text_field.dart';
export 'custom_dropdown.dart';

class CustomSurface extends StatelessWidget {
  const CustomSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = CustomColors.surface,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: CustomColors.shadow,
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: CustomColors.border),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class CustomStatusBadge extends StatelessWidget {
  const CustomStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );
}

class CustomStatCard extends StatelessWidget {
  const CustomStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label, value;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => CustomSurface(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: CustomColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class CustomQuickAction extends StatelessWidget {
  const CustomQuickAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 106,
    child: Material(
      color: CustomColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: CustomColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: CustomColors.button, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CustomEmptyState extends StatelessWidget {
  const CustomEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(23),
            decoration: BoxDecoration(
              color: CustomColors.neutralTint,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 40, color: CustomColors.button),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CustomColors.muted,
              height: 1.6,
              fontSize: 13,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

/// Sheet title with an optional muted second line (hotel, period, room…).
class CustomSheetTitle extends StatelessWidget {
  const CustomSheetTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      if (subtitle != null && subtitle!.isNotEmpty)
        Text(
          subtitle!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: CustomColors.muted,
            height: 1.4,
          ),
        ),
    ],
  );
}

/// Tinted rounded icon used as a sheet heading or list leading.
class CustomIconBadge extends StatelessWidget {
  const CustomIconBadge(
    this.icon, {
    super.key,
    this.color = CustomColors.button,
    this.size = 20,
  });
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(size * .5),
    decoration: BoxDecoration(
      color: color == CustomColors.button
          ? CustomColors.neutralTint
          : color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(size * .65),
    ),
    child: Icon(icon, color: color, size: size),
  );
}

class CustomSectionTitle extends StatelessWidget {
  const CustomSectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(2, 18, 2, 10),
  });
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Label on the left, value on the right; stacks when the value is long.
class CustomDetailRow extends StatelessWidget {
  const CustomDetailRow(
    this.label,
    this.value, {
    super.key,
    this.strong = false,
    this.valueColor,
  });
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: strong ? CustomColors.text : CustomColors.muted,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Text(
            value.trim().isEmpty ? '-' : value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: strong ? 14 : 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? CustomColors.text,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Grouped block of [CustomDetailRow]s on a soft surface.
class CustomDetailCard extends StatelessWidget {
  const CustomDetailCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: CustomColors.background,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: CustomColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class CustomDetailDivider extends StatelessWidget {
  const CustomDetailDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 14, color: CustomColors.border);
}

/// Responsive grid of [CustomStatCard]-like tiles: 2 columns on phones.
class CustomStatGrid extends StatelessWidget {
  const CustomStatGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 640 ? 4 : 2;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
