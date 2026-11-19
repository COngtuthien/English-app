import 'dart:math' as math;

import 'package:fsrs/fsrs.dart' as fsrs;

import '../../data/models/models.dart';

/// Ratings shown to the learner.
enum Grade {
  again(1, 'Quên'),
  hard(2, 'Khó'),
  good(3, 'Nhớ'),
  easy(4, 'Dễ');

  const Grade(this.value, this.labelVi);
  final int value;
  final String labelVi;
}

class ReviewOutcome {
  final CardState card;
  final double intervalDays;
  const ReviewOutcome(this.card, this.intervalDays);
}

/// Thin wrapper around the FSRS-6 scheduler from the official `fsrs` Dart port
/// (open-spaced-repetition/dart-fsrs). All timestamps are UTC; the device clock and
/// time zone only affect which *calendar day* activity is attributed to.
class SrsScheduler {
  final fsrs.Scheduler _s;

  SrsScheduler({bool enableFuzzing = true, double desiredRetention = 0.9})
    : _s = fsrs.Scheduler(
        desiredRetention: desiredRetention,
        learningSteps: const [Duration(minutes: 1), Duration(minutes: 10)],
        relearningSteps: const [Duration(minutes: 10)],
        maximumInterval: 3650,
        enableFuzzing: enableFuzzing,
      );

  static fsrs.Card toFsrs(CardState c) => fsrs.Card(
    cardId: c.entryId,
    state: fsrs.State.fromValue(c.state),
    step: c.step,
    stability: c.stability,
    difficulty: c.difficulty,
    due: c.due.toUtc(),
    lastReview: c.lastReview?.toUtc(),
  );

  ReviewOutcome review({required int entryId, CardState? current, required Grade grade, required DateTime nowUtc}) {
    final now = nowUtc.toUtc();
    final card = current != null ? toFsrs(current) : fsrs.Card(cardId: entryId, due: now);
    // Guard against a device clock that moved backwards before the last review.
    final reviewTime = (card.lastReview != null && now.isBefore(card.lastReview!)) ? card.lastReview! : now;
    final res = _s.reviewCard(card, fsrs.Rating.fromValue(grade.value), reviewDateTime: reviewTime);
    final c = res.card;
    final updated = CardState(
      entryId: entryId,
      state: c.state.value,
      step: c.step,
      stability: c.stability,
      difficulty: c.difficulty,
      due: c.due.toUtc(),
      lastReview: c.lastReview?.toUtc(),
      reps: (current?.reps ?? 0) + 1,
      lapses: (current?.lapses ?? 0) + ((current != null && current.state == 2 && grade == Grade.again) ? 1 : 0),
      lastRating: grade.value,
    );
    final interval = c.due.difference(reviewTime).inMinutes / (60 * 24);
    return ReviewOutcome(updated, interval);
  }

  /// Preview of the next interval for each grade (used to label rating buttons).
  Map<Grade, Duration> preview(int entryId, CardState? current, DateTime nowUtc) {
    final s = SrsScheduler(enableFuzzing: false);
    return {
      for (final g in Grade.values)
        g: s.review(entryId: entryId, current: current, grade: g, nowUtc: nowUtc).card.due.difference(nowUtc.toUtc()),
    };
  }

  /// Probability (0..1) that the card is currently remembered.
  double retrievability(CardState c, DateTime nowUtc) {
    if (c.stability == null || c.lastReview == null) return 0;
    final r = _s.getCardRetrievability(toFsrs(c), currentDateTime: nowUtc.toUtc());
    return r.isNaN ? 0 : math.min(1, math.max(0, r));
  }
}

String formatInterval(Duration d) {
  if (d.inMinutes < 60) return '${math.max(1, d.inMinutes)} ph';
  if (d.inHours < 24) return '${d.inHours} giờ';
  if (d.inDays < 30) return '${d.inDays} ngày';
  if (d.inDays < 365) return '${(d.inDays / 30).round()} th';
  return '${(d.inDays / 365).toStringAsFixed(1)} năm';
}
