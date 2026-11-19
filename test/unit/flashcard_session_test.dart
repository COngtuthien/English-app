import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/data/models/models.dart';
import 'package:ielts_vocabulary_master/domain/srs/srs_scheduler.dart';
import 'package:ielts_vocabulary_master/features/learn/flashcard_session.dart';

EntrySummary w(int id) => EntrySummary(
  id: id,
  headword: 'word$id',
  pos: 'noun',
  posVi: 'danh từ',
  entryType: 'word',
  cefr: 'B2',
  difficulty: 3,
  meaningVi: 'nghĩa $id',
  definition: 'definition $id',
);

const short = Duration(minutes: 10); // learning step -> card comes back in this session
const long = Duration(days: 3); // graduated -> not repeated in this session

void main() {
  test('starts on the first card, face-down', () {
    final s = FlashcardSession([w(1), w(2), w(3)]);
    expect(s.current!.entry.id, 1);
    expect(s.revealed, isFalse);
    expect(s.counterLabel, '1/3');
    expect(s.progress, 0);
  });

  test('grading requires the card to be revealed', () {
    final s = FlashcardSession([w(1), w(2)]);
    expect(s.grade(Grade.good, atPosition: 0, nextInterval: long), isNull);
    expect(s.position, 0);
    s.reveal();
    expect(s.grade(Grade.good, atPosition: 0, nextInterval: long), isNotNull);
  });

  test('Good advances to the next card, which starts face-down, and updates progress', () {
    final s = FlashcardSession([w(1), w(2), w(3)]);
    s.toggleFlip();
    expect(s.revealed, isTrue);
    final r = s.grade(Grade.good, atPosition: 0, nextInterval: long)!;
    expect(r.item.entry.id, 1);
    expect(s.current!.entry.id, 2);
    expect(s.revealed, isFalse);
    expect(s.counterLabel, '2/3');
    expect(s.progress, closeTo(1 / 3, 1e-9));
    expect(s.tally[Grade.good], 1);
  });

  test('duplicate submissions for the same position are ignored', () {
    final s = FlashcardSession([w(1), w(2), w(3)]);
    s.reveal();
    expect(s.grade(Grade.good, atPosition: 0, nextInterval: long), isNotNull);
    // a second tap carrying the old position must not grade card 2
    expect(s.grade(Grade.good, atPosition: 0, nextInterval: long), isNull);
    s.reveal();
    expect(s.grade(Grade.easy, atPosition: 0, nextInterval: long), isNull);
    expect(s.position, 1);
    expect(s.totalGraded, 1);
  });

  test('no card is skipped: every card is shown in order', () {
    final s = FlashcardSession([w(1), w(2), w(3), w(4)]);
    final seen = <int>[];
    while (!s.isFinished) {
      seen.add(s.current!.entry.id);
      s.reveal();
      s.grade(Grade.easy, atPosition: s.position, nextInterval: long);
    }
    expect(seen, [1, 2, 3, 4]);
    expect(s.counterLabel, '4/4');
  });

  test('ROOT CAUSE: the last remaining card is never shown again immediately', () {
    final s = FlashcardSession([w(1)]);
    s.reveal();
    final r = s.grade(Grade.good, atPosition: 0, nextInterval: short)!;
    expect(r.requeued, isFalse);
    expect(s.isFinished, isTrue, reason: 'one card graded -> session complete (summary)');
    expect(s.pendingLearningSteps, {1}, reason: 'FSRS keeps it due soon for the next review session');
  });

  test('a learning-step card returns later but never directly after itself', () {
    final s = FlashcardSession([w(1), w(2), w(3), w(4), w(5), w(6), w(7)]);
    final order = <int>[];
    var guard = 0;
    while (!s.isFinished && guard++ < 100) {
      order.add(s.current!.entry.id);
      s.reveal();
      s.grade(Grade.again, atPosition: s.position, nextInterval: short);
    }
    for (var i = 1; i < order.length; i++) {
      expect(order[i], isNot(order[i - 1]), reason: 'same card twice in a row at $i: $order');
    }
    // each card appears at most maxAppearances times
    for (final id in order.toSet()) {
      expect(order.where((x) => x == id).length, lessThanOrEqualTo(FlashcardSession.maxAppearances));
    }
    expect(s.isFinished, isTrue);
  });

  test('two-card session with learning steps alternates and terminates', () {
    final s = FlashcardSession([w(1), w(2)]);
    final order = <int>[];
    var guard = 0;
    while (!s.isFinished && guard++ < 20) {
      order.add(s.current!.entry.id);
      s.reveal();
      s.grade(Grade.good, atPosition: s.position, nextInterval: short);
    }
    expect(s.isFinished, isTrue);
    for (var i = 1; i < order.length; i++) {
      expect(order[i], isNot(order[i - 1]));
    }
  });

  test('swipe left (goNext) moves forward without grading; past the last card finishes', () {
    final s = FlashcardSession([w(1), w(2)]);
    s.reveal();
    expect(s.goNext(), isTrue);
    expect(s.current!.entry.id, 2);
    expect(s.revealed, isFalse, reason: 'next card is face-down');
    expect(s.totalGraded, 0);
    expect(s.goNext(), isTrue);
    expect(s.isFinished, isTrue);
    expect(s.goNext(), isFalse);
    expect(s.skippedEntries, {1, 2});
  });

  test('swipe right (goPrevious) goes back; not before the first card', () {
    final s = FlashcardSession([w(1), w(2), w(3)]);
    expect(s.canGoBack, isFalse);
    expect(s.goPrevious(), isFalse);
    s.goNext();
    s.goNext();
    s.reveal();
    expect(s.goPrevious(), isTrue);
    expect(s.current!.entry.id, 2);
    expect(s.revealed, isFalse);
    // from the summary the learner can come back to the last card
    s.goNext();
    s.goNext();
    expect(s.isFinished, isTrue);
    expect(s.goPrevious(), isTrue);
    expect(s.current!.entry.id, 3);
  });

  test('a revisited graded card cannot be graded twice', () {
    final s = FlashcardSession([w(1), w(2)]);
    s.reveal();
    s.grade(Grade.good, atPosition: 0, nextInterval: long);
    s.goPrevious();
    expect(s.current!.entry.id, 1);
    expect(s.current!.isGraded, isTrue);
    expect(s.current!.grade, Grade.good);
    s.reveal();
    expect(s.grade(Grade.easy, atPosition: 0, nextInterval: long), isNull);
    expect(s.totalGraded, 1);
    s.goNext();
    expect(s.current!.entry.id, 2);
    expect(s.skippedEntries, {2});
  });

  test('completing the final card finishes the session', () {
    final s = FlashcardSession([w(1), w(2)]);
    for (var i = 0; i < 2; i++) {
      s.reveal();
      s.grade(Grade.easy, atPosition: s.position, nextInterval: long);
    }
    expect(s.isFinished, isTrue);
    expect(s.current, isNull);
    expect(s.grade(Grade.easy, atPosition: 2, nextInterval: long), isNull);
    expect(s.gradedEntries, {1, 2});
  });
}
