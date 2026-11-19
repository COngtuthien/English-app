import 'dart:math' as math;

import '../../data/models/models.dart';
import '../../domain/srs/srs_scheduler.dart';

/// One position in a flashcard session queue (a card can appear again after its learning step).
class SessionItem {
  final EntrySummary entry;
  final int appearance; // 0 = first time in this session, 1.. = learning-step repeat
  const SessionItem(this.entry, {this.appearance = 0});
}

/// Result of grading the current card.
class GradeResult {
  final SessionItem item;
  final Grade grade;
  final bool requeued;
  final bool isFirstAppearance;
  const GradeResult(this.item, this.grade, {required this.requeued, required this.isFirstAppearance});
}

/// Pure, synchronous state of a flashcard session (no I/O, no widgets) so the navigation rules
/// can be unit-tested:
///  * grading advances to the next position immediately and always shows its front side;
///  * a card can only be graded once per position, and only after it was revealed;
///  * a card whose next learning step is due within [requeueWindow] comes back later in the
///    session, but never directly after itself (at least [minGap] other cards in between), so the
///    learner is never shown the same card twice in a row. If there are not enough other cards
///    left, it is not repeated in this session — FSRS has already scheduled it, and it appears in
///    the next "Ôn tập" session.
class FlashcardSession {
  static const Duration requeueWindow = Duration(minutes: 15);
  static const int maxAppearances = 3; // first showing + at most 2 learning-step repeats
  static const int preferredGap = 4;
  static const int minGap = 1;

  final List<SessionItem> _queue;
  int _pos = 0;
  bool _revealed = false;
  final Map<Grade, int> tally = {for (final g in Grade.values) g: 0};
  final Set<int> gradedEntries = {};
  final Set<int> pendingLearningSteps = {};

  FlashcardSession(List<EntrySummary> entries) : _queue = [for (final e in entries) SessionItem(e)];

  int get position => _pos;
  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isFinished => _pos >= _queue.length;
  bool get revealed => _revealed;
  SessionItem? get current => isFinished ? null : _queue[_pos];
  SessionItem? get next => _pos + 1 < _queue.length ? _queue[_pos + 1] : null;
  int get uniqueWords => _queue.map((i) => i.entry.id).toSet().length;
  int get totalGraded => tally.values.fold(0, (a, b) => a + b);

  /// Progress shown to the learner: "card x of n" where n includes learning-step repeats.
  String get counterLabel => '${math.min(_pos + 1, _queue.length)}/${_queue.length}';
  double get progress => _queue.isEmpty ? 0 : _pos / _queue.length;

  void toggleFlip() {
    if (!isFinished) _revealed = !_revealed;
  }

  void reveal() {
    if (!isFinished) _revealed = true;
  }

  /// Grades the card at [atPosition]. Returns null (and changes nothing) when the call is a
  /// duplicate (position already graded), the card is not revealed yet, or the session is over.
  /// [nextInterval] is the time until the card would be due again after this grade.
  GradeResult? grade(Grade g, {required int atPosition, required Duration nextInterval}) {
    if (isFinished || atPosition != _pos || !_revealed) return null;
    final item = _queue[_pos];
    var requeued = false;
    if (nextInterval < requeueWindow && item.appearance + 1 < maxAppearances) {
      final remainingOthers = _queue.length - _pos - 1;
      if (remainingOthers >= minGap) {
        final int insertAt = _pos + 1 + math.min<int>(preferredGap, remainingOthers);
        _queue.insert(insertAt, SessionItem(item.entry, appearance: item.appearance + 1));
        requeued = true;
      }
    }
    if (nextInterval < requeueWindow && !requeued) {
      pendingLearningSteps.add(item.entry.id);
    } else if (!requeued) {
      pendingLearningSteps.remove(item.entry.id);
    }
    tally[g] = tally[g]! + 1;
    final first = gradedEntries.add(item.entry.id);
    _pos++;
    _revealed = false; // the next card always starts face-down
    return GradeResult(item, g, requeued: requeued, isFirstAppearance: first);
  }

  /// Replaces the queue (e.g. "Học thêm 10 từ").
  void restart(List<EntrySummary> entries) {
    _queue
      ..clear()
      ..addAll(entries.map(SessionItem.new));
    _pos = 0;
    _revealed = false;
    for (final g in Grade.values) {
      tally[g] = 0;
    }
    gradedEntries.clear();
    pendingLearningSteps.clear();
  }
}
