import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/custom_colors.dart';
import '../widgets/hotel_ui.dart';
import 'admin_api.dart';

class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) =>
      CustomSurface(padding: padding, child: child);
}

class AdminMetric extends StatelessWidget {
  const AdminMetric({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.note,
  });
  final String title, value;
  final IconData icon;
  final String? note;
  @override
  Widget build(BuildContext context) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: CustomColors.muted, fontSize: 12),
              ),
            ),
            Icon(icon, size: 20, color: CustomColors.muted),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          value,
          style: const TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            note!,
            style: const TextStyle(fontSize: 11, color: CustomColors.muted),
          ),
        ],
      ],
    ),
  );
}

class AdminStatus extends StatelessWidget {
  const AdminStatus(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final color = switch (label.toLowerCase()) {
      'active' || 'available' || 'issued' => CustomColors.available,
      'trial' || 'cleaning' => CustomColors.cleaning,
      'expired' || 'suspended' || 'revoked' => CustomColors.error,
      'booked' || 'redeemed' => CustomColors.primary,
      _ => CustomColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AdminMetricGrid extends StatelessWidget {
  const AdminMetricGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 1000
          ? 4
          : c.maxWidth >= 550
          ? 2
          : 1;
      final width = (c.maxWidth - 16 * (columns - 1)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: children
            .map((w) => SizedBox(width: width, child: w))
            .toList(),
      );
    },
  );
}

class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: -.5,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(color: CustomColors.muted, fontSize: 12),
              ),
          ],
        ),
        ?action,
      ],
    ),
  );
}

class AdminBarChart extends StatelessWidget {
  const AdminBarChart({super.key, required this.series});
  final List<Map<String, dynamic>> series;
  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: Text('No completed bills or expenses in this period.'),
        ),
      );
    }
    final rows = series.length > 12
        ? series.sublist(series.length - 12)
        : series;
    final maxValue = rows.fold<num>(
      1,
      (v, p) => math.max(
        v,
        math.max(adminNumber(p['billed']), adminNumber(p['expenses'])),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Wrap(
          spacing: 20,
          children: [
            Text(
              '● Billed',
              style: TextStyle(color: CustomColors.primary, fontSize: 12),
            ),
            Text(
              '● Expenses',
              style: TextStyle(color: CustomColors.cleaning, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 200,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in rows)
                Expanded(
                  child: Tooltip(
                    message:
                        '${p['month']} · Billed ${adminMoney(p['billed'])} · Expenses ${adminMoney(p['expenses'])}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Container(
                                    width: 30,
                                    height: math.max(
                                      2,
                                      160 * adminNumber(p['billed']) / maxValue,
                                    ),
                                    decoration: BoxDecoration(
                                      color: CustomColors.primary,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Container(
                                    width: 18,
                                    height: math.max(
                                      2,
                                      160 *
                                          adminNumber(p['expenses']) /
                                          maxValue,
                                    ),
                                    decoration: BoxDecoration(
                                      color: CustomColors.cleaning,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${p['month']}'.substring(2),
                            style: const TextStyle(
                              fontSize: 10,
                              color: CustomColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (series.length > 12)
          const Text(
            'Chart shows the latest 12 months; totals include the full selected period.',
            style: TextStyle(fontSize: 11, color: CustomColors.muted),
          ),
      ],
    );
  }
}
