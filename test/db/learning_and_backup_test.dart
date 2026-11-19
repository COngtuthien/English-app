import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/data/repositories/achievement_repository.dart';
import 'package:ielts_vocabulary_master/data/repositories/learning_repository.dart';
import 'package:ielts_vocabulary_master/data/repositories/settings_repository.dart';
import 'package:ielts_vocabulary_master/data/repositories/stats_repository.dart';
import 'package:ielts_vocabulary_master/data/repositories/vocabulary_repository.dart';
import 'package:ielts_vocabulary_master/data/services/backup_service.dart';
import 'package:ielts_vocabulary_master/domain/quiz/quiz_engine.dart';
import 'package:ielts_vocabulary_master/domain/srs/srs_scheduler.dart';

import '../helpers/test_db.dart';

void main() {
  late TestDb t;
  late LearningRepository learn;
  late VocabularyRepository vocab;
  late StatsRepository stats;
  var now = DateTime.utc(2026, 11, 19, 3);

  setUp(() async {
    t = await TestDb.open();
    final sched = SrsScheduler(enableFuzzing: false);
    learn = LearningRepository(t.db.db, sched, clock: () => now);
    vocab = VocabularyRepository(t.db.db);
    stats = StatsRepository(t.db.db, sched, clock: () => now);
  });
  tearDown(() => t.close());

  test('learning a new word creates a card, history and daily activity', () async {
    final words = await learn.nextNewWords(5, const AppSettings());
    expect(words.length, 5);
    final o = await learn.review(words.first.id, Grade.good, mode: 'learn', durationMs: 4000);
    expect(o.card.reps, 1);
    expect(await learn.newWordsToday(), 1);
    final card = await learn.card(words.first.id);
    expect(card, isNotNull);
    final hist = await t.db.db.query('review_history');
    expect(hist.single['is_new'], 1);
    // the learned word is no longer offered as new
    final next = await learn.nextNewWords(5, const AppSettings());
    expect(next.map((e) => e.id), isNot(contains(words.first.id)));
  });

  test('due words appear in review after their interval passes', () async {
    final w = (await learn.nextNewWords(1, const AppSettings())).first;
    await learn.review(w.id, Grade.easy);
    expect(await learn.dueCount(), 0);
    now = now.add(const Duration(days: 30));
    expect(await learn.dueCount(), 1);
    final due = await learn.dueEntries();
    expect(due.single.id, w.id);
    await learn.review(w.id, Grade.good);
    expect(await learn.dueCount(), 0);
    now = DateTime.utc(2026, 11, 19, 3);
  });

  test('study queue words come first; favourites toggle', () async {
    final pick = (await vocab.randomEntries(1)).first;
    await learn.addToStudyQueue(pick.id);
    final next = await learn.nextNewWords(3, const AppSettings());
    expect(next.first.id, pick.id);
    expect(await learn.toggleFavorite(pick.id), isTrue);
    expect((await learn.favorites()).single.id, pick.id);
    expect(await learn.toggleFavorite(pick.id), isFalse);
    expect(await learn.favorites(), isEmpty);
  });

  test('B2 new-word queue skips function words and words already known at A-level', () async {
    final words = await learn.nextNewWords(40, const AppSettings(levelFocus: 'B2'));
    expect(words.length, 40);
    for (final w in words) {
      expect(['pronoun', 'determiner', 'preposition', 'conjunction'], isNot(contains(w.pos)));
      expect(w.difficulty, inInclusiveRange(3, 4));
    }
    expect(words.map((w) => w.headword.toLowerCase()), isNot(contains('that')));
  });

  test('topic and level settings steer new words', () async {
    final s = const AppSettings(levelFocus: 'C1', preferredTopics: ['environment']);
    final words = await learn.nextNewWords(10, s);
    expect(words.every((w) => w.difficulty >= 4), isTrue);
  });

  test('difficult and missed words come from lapses and quiz errors', () async {
    final w = (await learn.nextNewWords(2, const AppSettings()));
    await learn.review(w[0].id, Grade.again);
    await learn.recordQuizSession(
      quizType: 'quiz:enToVi',
      startedAt: now,
      answers: [
        QuizAnswerRecord(entryId: w[1].id, questionType: 'enToVi', prompt: 'x', userAnswer: 'a', correctAnswer: 'b', correct: false),
        QuizAnswerRecord(entryId: w[1].id, questionType: 'enToVi', prompt: 'x', userAnswer: 'a', correctAnswer: 'b', correct: false),
      ],
    );
    final difficult = (await learn.difficultWords()).map((e) => e.id).toSet();
    expect(difficult, containsAll([w[0].id, w[1].id]));
    final missed = (await learn.missedWords()).map((e) => e.id).toSet();
    expect(missed, containsAll([w[0].id, w[1].id]));
  });

  test('dashboard and full statistics use persisted data', () async {
    final words = await learn.nextNewWords(3, const AppSettings());
    for (final w in words) {
      await learn.review(w.id, Grade.good);
    }
    await learn.recordQuizSession(
      quizType: 'quiz:mixed',
      startedAt: now,
      answers: [
        QuizAnswerRecord(entryId: words.first.id, questionType: 'enToVi', prompt: 'p', userAnswer: 'a', correctAnswer: 'a', correct: true),
      ],
    );
    final d = await stats.dashboard();
    expect(d.newToday, 3);
    expect(d.totalStudied, 3);
    expect(d.streak, 1);
    expect(d.week.length, 7);
    final f = await stats.full();
    expect(f.totalAnswers, 4);
    expect(f.quizzes.single.correct, 1);
    expect(f.recentReviews.length, 3);
  });

  test('achievements unlock from real progress', () async {
    final ach = AchievementRepository(t.db.db, clock: () => now);
    final words = await learn.nextNewWords(10, const AppSettings());
    for (final w in words) {
      await learn.review(w.id, Grade.good);
    }
    await learn.recordQuizSession(
      quizType: 'quiz:x',
      startedAt: now,
      answers: [
        for (final w in words.take(5))
          QuizAnswerRecord(entryId: w.id, questionType: 'enToVi', prompt: 'p', userAnswer: 'a', correctAnswer: 'a', correct: true),
      ],
    );
    final fresh = (await ach.evaluate()).map((a) => a.code).toSet();
    expect(fresh, containsAll(['words_10', 'perfect_quiz']));
    expect(await ach.evaluate(), isEmpty, reason: 'achievements unlock only once');
  });

  group('backup', () {
    test('export -> restore round trip into a fresh database', () async {
      final words = await learn.nextNewWords(4, const AppSettings());
      for (final w in words) {
        await learn.review(w.id, Grade.good);
      }
      await learn.toggleFavorite(words.first.id);
      await SettingsRepository(t.db.db).save(const AppSettings(userName: 'Minh', dailyNewWords: 35, onboarded: true));
      final bytes = await BackupService(t.db.db).exportBytes();

      final other = await TestDb.open();
      final restored = await BackupService(other.db.db).restore(bytes);
      expect(restored.learnedWords, 4);
      expect((await other.db.db.query('learning_cards')).length, 4);
      expect((await other.db.db.query('favorites')).single['entry_id'], words.first.id);
      final s = await SettingsRepository(other.db.db).load();
      expect(s.userName, 'Minh');
      expect(s.dailyNewWords, 35);
      await other.close();
    });

    test('rejects corrupted, foreign and future-version files without changing data', () async {
      final svc = BackupService(t.db.db);
      final w = (await learn.nextNewWords(1, const AppSettings())).first;
      await learn.review(w.id, Grade.good);
      final good = await svc.exportBytes();
      final doc = jsonDecode(utf8.decode(good)) as Map<String, dynamic>;

      // tampered payload -> checksum mismatch
      final tampered = Map<String, dynamic>.from(doc);
      (tampered['data'] as Map<String, dynamic>)['favorites'] = [
        {'entry_id': 1, 'created_at': 1},
      ];
      await expectLater(svc.restore(Uint8List.fromList(utf8.encode(jsonEncode(tampered)))), throwsA(isA<BackupException>()));

      await expectLater(svc.restore(Uint8List.fromList(utf8.encode('not json'))), throwsA(isA<BackupException>()));
      await expectLater(svc.restore(Uint8List.fromList(utf8.encode('{"format":"other"}'))), throwsA(isA<BackupException>()));
      final future = Map<String, dynamic>.from(jsonDecode(utf8.decode(good)) as Map<String, dynamic>)..['schemaVersion'] = 99;
      await expectLater(svc.restore(Uint8List.fromList(utf8.encode(jsonEncode(future)))), throwsA(isA<BackupException>()));

      expect((await t.db.db.query('learning_cards')).length, 1, reason: 'failed restores must not modify data');
    });
  });

  group('quiz engine', () {
    test('builds questions of every type with one valid answer', () async {
      final engine = QuizEngine(vocab);
      for (final type in QuestionType.values) {
        final qs = await engine.build(QuizConfig(types: {type}, count: 4, preferLearned: false));
        expect(qs, isNotEmpty, reason: 'no questions for $type');
        for (final q in qs) {
          if (q.isTyped) {
            expect(q.accepted, isNotEmpty);
            expect(q.accepted.map((a) => a.toLowerCase()), contains(q.correctAnswer.toLowerCase()));
          } else {
            expect(q.options.length, 4, reason: '${q.type} ${q.prompt}');
            expect(q.options.toSet().length, 4, reason: 'duplicate options: ${q.options}');
            expect(q.answerIndex, inInclusiveRange(0, 3));
            expect(q.options[q.answerIndex], q.correctAnswer);
          }
        }
      }
    });

    test('mixed quiz with 20 questions and no repeated target word', () async {
      final qs = await QuizEngine(vocab).build(QuizConfig(types: QuestionType.values.toSet(), count: 20, preferLearned: false));
      expect(qs.length, 20);
      final ids = qs.map((q) => q.entryId).whereType<int>().toList();
      expect(ids.toSet().length, ids.length);
    });

    test('topic quiz uses words from the topic', () async {
      final topics = await vocab.topics();
      final edu = topics.firstWhere((t) => t.code == 'education');
      final qs = await QuizEngine(vocab).build(QuizConfig(types: {QuestionType.enToVi}, count: 5, topicId: edu.id, preferLearned: false));
      for (final q in qs) {
        final inTopic = await t.db.db.rawQuery('SELECT 1 FROM c.vocabulary_topics WHERE entry_id=? AND topic_id=?', [q.entryId, edu.id]);
        expect(inTopic, isNotEmpty);
      }
    });
  });
}
