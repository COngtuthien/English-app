import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/domain/srs/srs_scheduler.dart';

void main() {
  final s = SrsScheduler(enableFuzzing: false);
  final t0 = DateTime.utc(2026, 11, 19, 8);

  test('new card rated Good enters learning with a short step', () {
    final o = s.review(entryId: 1, grade: Grade.good, nowUtc: t0);
    expect(o.card.state, 1); // learning
    expect(o.card.reps, 1);
    expect(o.card.due.isAfter(t0), isTrue);
    expect(o.card.due.difference(t0).inMinutes, lessThanOrEqualTo(10));
    expect(o.card.stability, isNotNull);
  });

  test('Easy on a new card graduates straight to review', () {
    final o = s.review(entryId: 1, grade: Grade.easy, nowUtc: t0);
    expect(o.card.state, 2);
    expect(o.card.due.difference(t0).inDays, greaterThanOrEqualTo(1));
  });

  test('intervals grow with successive Good reviews', () {
    var c = s.review(entryId: 7, grade: Grade.good, nowUtc: t0).card;
    var now = c.due;
    c = s.review(entryId: 7, current: c, grade: Grade.good, nowUtc: now).card;
    final gaps = <int>[];
    for (var i = 0; i < 4; i++) {
      now = c.due;
      final next = s.review(entryId: 7, current: c, grade: Grade.good, nowUtc: now).card;
      gaps.add(next.due.difference(now).inHours);
      c = next;
    }
    for (var i = 1; i < gaps.length; i++) {
      expect(gaps[i], greaterThan(gaps[i - 1]));
    }
    expect(c.state, 2);
  });

  test('Again on a review card counts a lapse and enters relearning', () {
    var c = s.review(entryId: 3, grade: Grade.easy, nowUtc: t0).card;
    final later = c.due.add(const Duration(days: 1));
    final o = s.review(entryId: 3, current: c, grade: Grade.again, nowUtc: later);
    expect(o.card.lapses, 1);
    expect(o.card.state, 3); // relearning
    expect(o.card.due.difference(later).inMinutes, lessThanOrEqualTo(10));
  });

  test('a clock moved backwards does not break scheduling', () {
    final c = s.review(entryId: 4, grade: Grade.easy, nowUtc: t0).card;
    final past = t0.subtract(const Duration(days: 3));
    final o = s.review(entryId: 4, current: c, grade: Grade.good, nowUtc: past);
    expect(o.card.due.isAfter(t0), isTrue);
  });

  test('preview gives increasing intervals Again < Hard <= Good < Easy', () {
    final p = s.preview(9, null, t0);
    expect(p[Grade.again]!, lessThanOrEqualTo(p[Grade.hard]!));
    expect(p[Grade.hard]!, lessThanOrEqualTo(p[Grade.good]!));
    expect(p[Grade.good]!, lessThan(p[Grade.easy]!));
  });

  test('retrievability decays over time and stays in [0,1]', () {
    final c = s.review(entryId: 5, grade: Grade.easy, nowUtc: t0).card;
    final r1 = s.retrievability(c, t0.add(const Duration(days: 1)));
    final r30 = s.retrievability(c, t0.add(const Duration(days: 30)));
    expect(r1, inInclusiveRange(0, 1));
    expect(r30, lessThan(r1));
  });

  test('formatInterval', () {
    expect(formatInterval(const Duration(minutes: 10)), '10 ph');
    expect(formatInterval(const Duration(hours: 5)), '5 giờ');
    expect(formatInterval(const Duration(days: 3)), '3 ngày');
  });
}
