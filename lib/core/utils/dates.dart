import 'package:intl/intl.dart';

/// Calendar-day helpers. Study streaks and daily goals are counted in the
/// device's local calendar day, while scheduling timestamps are stored in UTC.
class Dates {
  static final _dayFmt = DateFormat('yyyy-MM-dd');

  static String dayKey(DateTime t) => _dayFmt.format(t.toLocal());
  static String today([DateTime? now]) => dayKey(now ?? DateTime.now());

  static DateTime parseDay(String key) => DateTime.parse(key);

  static DateTime startOfLocalDay(DateTime t) {
    final l = t.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Returns consecutive-day streak ending today (or yesterday if today has no activity yet).
  static int streak(Set<String> activeDays, {DateTime? now}) {
    var day = startOfLocalDay(now ?? DateTime.now());
    if (!activeDays.contains(dayKey(day))) {
      day = day.subtract(const Duration(days: 1));
      if (!activeDays.contains(dayKey(day))) return 0;
    }
    var n = 0;
    while (activeDays.contains(dayKey(day))) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  /// Longest run of consecutive days.
  static int longestStreak(Iterable<String> days) {
    final sorted = days.map(parseDay).toList()..sort();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final d in sorted) {
      if (prev != null && DateTime(prev.year, prev.month, prev.day + 1) == d) {
        cur++;
      } else {
        cur = 1;
      }
      if (cur > best) best = cur;
      prev = d;
    }
    return best;
  }

  static String weekdayShortVi(DateTime d) {
    const names = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return names[d.weekday - 1];
  }

  static String friendlyDue(DateTime dueUtc, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toUtc();
    final diff = dueUtc.difference(n);
    if (diff.isNegative || diff.inMinutes < 1) return 'bây giờ';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút';
    if (diff.inHours < 24) return '${diff.inHours} giờ';
    if (diff.inDays < 30) return '${diff.inDays} ngày';
    if (diff.inDays < 365) return '${(diff.inDays / 30).round()} tháng';
    return '${(diff.inDays / 365).toStringAsFixed(1)} năm';
  }
}
