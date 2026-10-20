import 'package:flutter/material.dart' show DateTimeRange;

/// Report / list periods from features.md.
enum PeriodKind { today, yesterday, thisWeek, thisMonth, custom, allTime }

/// A date period with a half-open `[start, end)` range in local time.
/// `start` / `end` are null for "All Time".
class Period {
  const Period._(this.kind, this.start, this.end);

  final PeriodKind kind;
  final DateTime? start;
  final DateTime? end;

  static const allTime = Period._(PeriodKind.allTime, null, null);

  factory Period.of(PeriodKind kind, {DateTime? now, DateTimeRange? custom}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return switch (kind) {
      PeriodKind.today =>
        Period._(kind, today, today.add(const Duration(days: 1))),
      PeriodKind.yesterday =>
        Period._(kind, today.subtract(const Duration(days: 1)), today),
      PeriodKind.thisWeek => () {
          // Weeks start on Monday.
          final start = today.subtract(Duration(days: today.weekday - 1));
          return Period._(kind, start, start.add(const Duration(days: 7)));
        }(),
      PeriodKind.thisMonth => Period._(
          kind,
          DateTime(n.year, n.month),
          DateTime(n.year, n.month + 1),
        ),
      PeriodKind.custom => Period._(
          kind,
          DateTime(custom!.start.year, custom.start.month, custom.start.day),
          DateTime(custom.end.year, custom.end.month, custom.end.day)
              .add(const Duration(days: 1)),
        ),
      PeriodKind.allTime => allTime,
    };
  }

  /// The period of equal length right before this one, for "vs last period"
  /// comparisons. Null for All Time.
  Period? get previous {
    if (start == null || end == null) return null;
    if (kind == PeriodKind.thisMonth) {
      return Period._(
        PeriodKind.custom,
        DateTime(start!.year, start!.month - 1),
        start,
      );
    }
    final length = end!.difference(start!);
    return Period._(PeriodKind.custom, start!.subtract(length), start);
  }

  int? get startMs => start?.millisecondsSinceEpoch;
  int? get endMs => end?.millisecondsSinceEpoch;

  @override
  bool operator ==(Object other) =>
      other is Period &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}
