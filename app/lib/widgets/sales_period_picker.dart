import 'package:flutter/material.dart';

import '../core/state/dashboard_repository.dart';
import '../core/theme/app_theme.dart';

/// One entry on a home dashboard's period menu: a preset window or an earlier
/// month with live sales.
class SalesWindow {
  const SalesWindow({
    required this.id,
    required this.label,
    required this.heading,
    required this.totals,
    required this.icon,
  });

  /// Stable across rebuilds, e.g. `today` or `month:2026-10`.
  final String id;

  /// The short wording on the picker and its menu.
  final String label;

  /// The card title, e.g. "Today's sales".
  final String heading;
  final SalesPeriodTotals totals;
  final IconData icon;
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `2026-10` reads as "October 2026"; anything unexpected is left as-is.
String salesMonthLabel(String key) {
  final parts = key.split('-');
  final month = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return key;
  return '${_monthNames[month - 1]} ${parts[0]}';
}

/// The windows every home dashboard offers: today, the last seven days, this
/// month, then the earlier months the server found live sales in.
///
/// [DashboardSummary] totals are the fallback when an older server sends no
/// `periods`, so the card still shows a real figure rather than zeroes.
List<SalesWindow> salesWindows(DashboardSummary? summary) {
  final periods = summary?.periods;
  final fallback = SalesPeriodTotals(
    transactionCount: summary?.transactionCount ?? 0,
    grossSalesKobo: summary?.grossSalesKobo ?? 0,
    collectedKobo: summary?.collectedKobo ?? 0,
    outstandingKobo: summary?.outstandingKobo ?? 0,
  );

  return [
    SalesWindow(
      id: 'today',
      label: 'Today',
      heading: "Today's sales",
      totals: periods?.today ?? fallback,
      icon: Icons.today_rounded,
    ),
    SalesWindow(
      id: 'week',
      label: '7 days',
      heading: 'Last 7 days',
      totals: periods?.week ?? fallback,
      icon: Icons.date_range_rounded,
    ),
    SalesWindow(
      id: 'month',
      label: 'This month',
      heading: 'This month',
      totals: periods?.month ?? fallback,
      icon: Icons.calendar_month_rounded,
    ),
    for (final month in periods?.months ?? const <SalesMonthPeriod>[])
      SalesWindow(
        id: 'month:${month.key}',
        label: salesMonthLabel(month.key),
        heading: salesMonthLabel(month.key),
        totals: month.totals,
        icon: Icons.history_rounded,
      ),
  ];
}

/// The chosen window, falling back to the first when a month disappears after
/// a refresh (a month whose sales were all cancelled, for example).
SalesWindow selectedSalesWindow(List<SalesWindow> windows, String id) =>
    windows.firstWhere(
      (window) => window.id == id,
      orElse: () => windows.first,
    );

/// The period control: a tinted pill beside the card title that opens a menu of
/// presets and the months that actually have sales. The current window wears a
/// check, so the menu also says what is showing.
class SalesPeriodPicker extends StatelessWidget {
  const SalesPeriodPicker({
    required this.windows,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<SalesWindow> windows;
  final SalesWindow selected;
  final ValueChanged<SalesWindow> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return MenuAnchor(
      alignmentOffset: const Offset(-36, 6),
      menuChildren: [
        for (var i = 0; i < windows.length; i++) ...[
          if (i == 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                'Earlier months',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          MenuItemButton(
            onPressed: () => onSelected(windows[i]),
            leadingIcon: Icon(windows[i].icon, size: 18),
            trailingIcon: windows[i].id == selected.id
                ? Icon(Icons.check_rounded, size: 18, color: accent)
                : null,
            child: Text(
              windows[i].label,
              style: TextStyle(
                fontWeight: windows[i].id == selected.id
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
      builder: (context, controller, _) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            color: accent.withValues(alpha: 0.10),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected.icon, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(
                selected.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 17, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
