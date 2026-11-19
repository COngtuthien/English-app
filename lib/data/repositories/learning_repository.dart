import 'package:sqflite/sqflite.dart';

import '../../core/utils/dates.dart';
import '../../domain/srs/srs_scheduler.dart';
import '../models/models.dart';
import 'settings_repository.dart';

const String _cols =
    'e.id,e.headword,e.pos,e.pos_vi,e.entry_type,e.cefr,e.difficulty,e.primary_vi,e.primary_def,e.ipa_uk,e.ipa_us,e.variants';

/// Persists spaced-repetition state, history, favourites and the study queue.
class LearningRepository {
  final Database db;
  final SrsScheduler scheduler;
  final DateTime Function() clock;

  LearningRepository(this.db, this.scheduler, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  DateTime get _nowUtc => clock().toUtc();

  Future<CardState?> card(int entryId) async {
    final r = await db.query('learning_cards', where: 'entry_id=?', whereArgs: [entryId]);
    return r.isEmpty ? null : CardState.fromRow(r.first);
  }

  Future<Map<int, CardState>> cards(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    final r = await db.rawQuery('SELECT * FROM learning_cards WHERE entry_id IN (${List.filled(list.length, '?').join(',')})', list);
    return {for (final row in r) row['entry_id'] as int: CardState.fromRow(row)};
  }

  /// Records a flashcard rating: updates FSRS state, review history and daily activity in one transaction.
  Future<ReviewOutcome> review(int entryId, Grade grade, {String mode = 'review', int? durationMs}) async {
    final now = _nowUtc;
    final day = Dates.dayKey(now);
    late ReviewOutcome outcome;
    await db.transaction((txn) async {
      final rows = await txn.query('learning_cards', where: 'entry_id=?', whereArgs: [entryId]);
      final current = rows.isEmpty ? null : CardState.fromRow(rows.first);
      outcome = scheduler.review(entryId: entryId, current: current, grade: grade, nowUtc: now);
      final c = outcome.card;
      await txn.insert('learning_cards', {
        'entry_id': entryId,
        'state': c.state,
        'step': c.step,
        'stability': c.stability,
        'difficulty': c.difficulty,
        'due': c.due.millisecondsSinceEpoch,
        'last_review': c.lastReview?.millisecondsSinceEpoch,
        'reps': c.reps,
        'lapses': c.lapses,
        'last_rating': grade.value,
        'created_at': rows.isEmpty ? now.millisecondsSinceEpoch : rows.first['created_at'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('review_history', {
        'entry_id': entryId,
        'rating': grade.value,
        'mode': mode,
        'reviewed_at': now.millisecondsSinceEpoch,
        'local_day': day,
        'duration_ms': durationMs,
        'state_before': current?.state,
        'interval_days': outcome.intervalDays,
        'is_new': current == null ? 1 : 0,
      });
      await txn.delete('study_queue', where: 'entry_id=?', whereArgs: [entryId]);
      await _bumpActivity(
        txn,
        day,
        newWords: current == null ? 1 : 0,
        reviews: current == null ? 0 : 1,
        correct: grade == Grade.again ? 0 : 1,
        answers: 1,
        studyMs: durationMs ?? 0,
      );
    });
    return outcome;
  }

  static Future<void> _bumpActivity(
    DatabaseExecutor ex,
    String day, {
    int newWords = 0,
    int reviews = 0,
    int correct = 0,
    int answers = 0,
    int studyMs = 0,
  }) async {
    await ex.rawInsert('INSERT OR IGNORE INTO study_activity(local_day) VALUES(?)', [day]);
    await ex.rawUpdate(
      'UPDATE study_activity SET new_words=new_words+?, reviews=reviews+?, correct=correct+?, answers=answers+?, study_ms=study_ms+? WHERE local_day=?',
      [newWords, reviews, correct, answers, studyMs, day],
    );
  }

  /// Records answers from quizzes and games (not flashcards).
  Future<int> recordQuizSession({
    required String quizType,
    String? topicCode,
    required DateTime startedAt,
    required List<QuizAnswerRecord> answers,
  }) async {
    final now = _nowUtc;
    final day = Dates.dayKey(now);
    late int sessionId;
    await db.transaction((txn) async {
      sessionId = await txn.insert('quiz_sessions', {
        'quiz_type': quizType,
        'topic_code': topicCode,
        'started_at': startedAt.toUtc().millisecondsSinceEpoch,
        'finished_at': now.millisecondsSinceEpoch,
        'total': answers.length,
        'correct': answers.where((a) => a.correct).length,
        'local_day': day,
      });
      final batch = txn.batch();
      for (final a in answers) {
        batch.insert('quiz_answers', {
          'session_id': sessionId,
          'entry_id': a.entryId,
          'question_type': a.questionType,
          'prompt': a.prompt,
          'user_answer': a.userAnswer,
          'correct_answer': a.correctAnswer,
          'is_correct': a.correct ? 1 : 0,
          'answered_at': now.millisecondsSinceEpoch,
        });
      }
      await batch.commit(noResult: true);
      await _bumpActivity(
        txn,
        day,
        correct: answers.where((a) => a.correct).length,
        answers: answers.length,
        studyMs: now.difference(startedAt.toUtc()).inMilliseconds.clamp(0, 3 * 3600 * 1000),
      );
    });
    return sessionId;
  }

  // ------------------------------------------------------------------ queues
  Future<int> dueCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM learning_cards WHERE due <= ?', [_nowUtc.millisecondsSinceEpoch])) ?? 0;

  Future<List<EntrySummary>> dueEntries({int limit = 100}) async {
    final rows = await db.rawQuery(
      '''
      SELECT $_cols FROM learning_cards lc JOIN c.vocabulary_entries e ON e.id = lc.entry_id
      WHERE lc.due <= ? ORDER BY lc.due LIMIT ?''',
      [_nowUtc.millisecondsSinceEpoch, limit],
    );
    return rows.map(EntrySummary.fromRow).toList();
  }

  Future<int> newWordsToday() async {
    final r = await db.query('study_activity', where: 'local_day=?', whereArgs: [Dates.dayKey(_nowUtc)]);
    return r.isEmpty ? 0 : r.first['new_words'] as int;
  }

  Future<int> reviewsToday() async {
    final r = await db.query('study_activity', where: 'local_day=?', whereArgs: [Dates.dayKey(_nowUtc)]);
    return r.isEmpty ? 0 : r.first['reviews'] as int;
  }

  /// Next unseen words according to the learner's settings. Words added to the study queue come first.
  Future<List<EntrySummary>> nextNewWords(int count, AppSettings s, {int? topicId}) async {
    if (count <= 0) return [];
    final out = <EntrySummary>[];
    if (topicId == null) {
      final queued = await db.rawQuery(
        '''
        SELECT $_cols FROM study_queue q JOIN c.vocabulary_entries e ON e.id = q.entry_id
        WHERE e.id NOT IN (SELECT entry_id FROM learning_cards) ORDER BY q.added_at LIMIT ?''',
        [count],
      );
      out.addAll(queued.map(EntrySummary.fromRow));
    }
    if (out.length >= count) return out;
    final w = <String>['e.id NOT IN (SELECT entry_id FROM learning_cards)'];
    final args = <Object?>[];
    if (out.isNotEmpty) w.add('e.id NOT IN (${out.map((e) => e.id).join(',')})');
    if (topicId != null) {
      w.add('e.id IN (SELECT entry_id FROM c.vocabulary_topics WHERE topic_id=?)');
      args.add(topicId);
    } else if (s.preferredTopics.isNotEmpty) {
      w.add(
        'e.id IN (SELECT vt.entry_id FROM c.vocabulary_topics vt JOIN c.topics t ON t.id=vt.topic_id '
        'WHERE t.code IN (${List.filled(s.preferredTopics.length, '?').join(',')}))',
      );
      args.addAll(s.preferredTopics);
    }
    final band = levelBand(s.levelFocus);
    if (band != null && topicId == null) {
      w.add('e.difficulty BETWEEN ? AND ?');
      args.addAll(band);
      // Skip grammar/function words and headwords the learner already knows at a much lower level
      // (e.g. "that" adverb is CEFR B2, but "that" determiner/pronoun is A1).
      w.add("e.pos NOT IN ('pronoun','determiner','preposition','conjunction','interjection','number')");
      w.add('NOT EXISTS (SELECT 1 FROM c.vocabulary_entries o WHERE o.headword_norm = e.headword_norm AND o.difficulty <= ?)');
      args.add(band[0] - 2);
    }
    final order = switch (s.studyOrder) {
      StudyOrder.alphabetical => 'e.headword_norm',
      StudyOrder.random => 'random()',
      StudyOrder.frequency => 'e.freq_rank',
    };
    var rows = await db.rawQuery('SELECT $_cols FROM c.vocabulary_entries e WHERE ${w.join(' AND ')} ORDER BY $order LIMIT ?', [
      ...args,
      count - out.length,
    ]);
    out.addAll(rows.map(EntrySummary.fromRow));
    if (out.length < count && (band != null || s.preferredTopics.isNotEmpty) && topicId == null) {
      // the preferred pool is exhausted: continue with the rest of the lexicon
      rows = await db.rawQuery(
        'SELECT $_cols FROM c.vocabulary_entries e WHERE e.id NOT IN (SELECT entry_id FROM learning_cards) '
        '${out.isEmpty ? '' : 'AND e.id NOT IN (${out.map((e) => e.id).join(',')})'} ORDER BY $order LIMIT ?',
        [count - out.length],
      );
      out.addAll(rows.map(EntrySummary.fromRow));
    }
    return out;
  }

  /// Difficulty band (min,max) for a CEFR focus. Difficulty: 1=A1-A2, 2=B1, 3=B2, 4=C1, 5=C2.
  static List<int>? levelBand(String focus) => switch (focus) {
    'B1' => [2, 3],
    'B2' => [3, 4],
    'C1' => [4, 5],
    'C2' => [5, 5],
    _ => null,
  };

  // ------------------------------------------------------------------ favourites / queue
  Future<bool> isFavorite(int id) async => (await db.query('favorites', where: 'entry_id=?', whereArgs: [id])).isNotEmpty;

  Future<bool> toggleFavorite(int id) async {
    if (await isFavorite(id)) {
      await db.delete('favorites', where: 'entry_id=?', whereArgs: [id]);
      return false;
    }
    await db.insert('favorites', {
      'entry_id': id,
      'created_at': _nowUtc.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<List<EntrySummary>> favorites() async {
    final rows = await db.rawQuery(
      'SELECT $_cols FROM favorites f JOIN c.vocabulary_entries e ON e.id=f.entry_id ORDER BY f.created_at DESC',
    );
    return rows.map(EntrySummary.fromRow).toList();
  }

  Future<bool> inStudyQueue(int id) async => (await db.query('study_queue', where: 'entry_id=?', whereArgs: [id])).isNotEmpty;

  Future<void> addToStudyQueue(int id) async {
    await db.insert('study_queue', {
      'entry_id': id,
      'added_at': _nowUtc.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeFromStudyQueue(int id) async => db.delete('study_queue', where: 'entry_id=?', whereArgs: [id]);

  // ------------------------------------------------------------------ lists
  /// Words with lapses, a recent "again" rating, or repeated quiz mistakes.
  Future<List<EntrySummary>> difficultWords({int limit = 300}) async {
    final rows = await db.rawQuery(
      '''
      SELECT $_cols FROM c.vocabulary_entries e WHERE e.id IN (
        SELECT entry_id FROM learning_cards WHERE lapses > 0 OR last_rating = 1 OR (difficulty IS NOT NULL AND difficulty >= 7)
        UNION
        SELECT entry_id FROM quiz_answers WHERE is_correct = 0 AND entry_id IS NOT NULL GROUP BY entry_id HAVING COUNT(*) >= 2
      ) LIMIT ?''',
      [limit],
    );
    return rows.map(EntrySummary.fromRow).toList();
  }

  Future<List<EntrySummary>> recentlyStudied({int limit = 50}) async {
    final rows = await db.rawQuery(
      '''
      SELECT $_cols FROM learning_cards lc JOIN c.vocabulary_entries e ON e.id=lc.entry_id
      ORDER BY lc.last_review DESC LIMIT ?''',
      [limit],
    );
    return rows.map(EntrySummary.fromRow).toList();
  }

  /// Words answered wrongly (flashcard "again" or quiz mistakes), most recent first.
  Future<List<EntrySummary>> missedWords({int limit = 100}) async {
    final rows = await db.rawQuery(
      '''
      SELECT $_cols FROM c.vocabulary_entries e JOIN (
        SELECT entry_id, MAX(t) AS t FROM (
          SELECT entry_id, reviewed_at AS t FROM review_history WHERE rating = 1
          UNION ALL
          SELECT entry_id, answered_at AS t FROM quiz_answers WHERE is_correct = 0 AND entry_id IS NOT NULL
        ) GROUP BY entry_id
      ) m ON m.entry_id = e.id ORDER BY m.t DESC LIMIT ?''',
      [limit],
    );
    return rows.map(EntrySummary.fromRow).toList();
  }

  Future<List<int>> learnedIds({int limit = 5000}) async {
    final rows = await db.rawQuery('SELECT entry_id FROM learning_cards ORDER BY last_review DESC LIMIT ?', [limit]);
    return rows.map((r) => r['entry_id'] as int).toList();
  }

  Future<List<CardState>> allCards() async {
    final rows = await db.query('learning_cards');
    return rows.map(CardState.fromRow).toList();
  }
}

class QuizAnswerRecord {
  final int? entryId;
  final String questionType;
  final String prompt;
  final String? userAnswer;
  final String correctAnswer;
  final bool correct;
  const QuizAnswerRecord({
    required this.entryId,
    required this.questionType,
    required this.prompt,
    required this.userAnswer,
    required this.correctAnswer,
    required this.correct,
  });
}
