import 'package:sqflite/sqflite.dart';

import '../../core/utils/dates.dart';
import '../../domain/srs/srs_scheduler.dart';
import '../models/models.dart';

class DashboardStats {
  final int newToday;
  final int reviewsToday;
  final int dueNow;
  final int totalStudied;
  final int mastered;
  final double? retention; // average predicted recall of reviewed words, null if none
  final int streak;
  final List<DayActivity> week; // oldest -> today
  final int totalEntries;
  const DashboardStats({
    required this.newToday,
    required this.reviewsToday,
    required this.dueNow,
    required this.totalStudied,
    required this.mastered,
    required this.retention,
    required this.streak,
    required this.week,
    required this.totalEntries,
  });
}

class TopicMastery {
  final String code;
  final String nameVi;
  final String? icon;
  final int total;
  final int learned;
  final int mastered;
  const TopicMastery(this.code, this.nameVi, this.icon, this.total, this.learned, this.mastered);
}

class FullStats {
  final int totalStudied;
  final int mastered;
  final int learning;
  final int dueNow;
  final int totalAnswers;
  final int correctAnswers;
  final int streak;
  final int longestStreak;
  final int totalReviews;
  final int studyMinutes;
  final List<DayActivity> last30;
  final List<TopicMastery> topics;
  final List<QuizSessionRecord> quizzes;
  final List<Map<String, Object?>> recentReviews;
  final Map<int, int> ratingCounts;
  const FullStats({
    required this.totalStudied,
    required this.mastered,
    required this.learning,
    required this.dueNow,
    required this.totalAnswers,
    required this.correctAnswers,
    required this.streak,
    required this.longestStreak,
    required this.totalReviews,
    required this.studyMinutes,
    required this.last30,
    required this.topics,
    required this.quizzes,
    required this.recentReviews,
    required this.ratingCounts,
  });

  double get accuracy => totalAnswers == 0 ? 0 : correctAnswers / totalAnswers;
}

class StatsRepository {
  final Database db;
  final SrsScheduler scheduler;
  final DateTime Function() clock;
  StatsRepository(this.db, this.scheduler, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  Future<Set<String>> activeDays() async {
    final rows = await db.rawQuery('SELECT local_day FROM study_activity WHERE answers > 0 OR new_words > 0 OR reviews > 0');
    return rows.map((r) => r['local_day'] as String).toSet();
  }

  Future<List<DayActivity>> activityRange(int days) async {
    final now = clock();
    final start = DateTime(now.year, now.month, now.day - (days - 1));
    final rows = await db.rawQuery('SELECT * FROM study_activity WHERE local_day >= ?', [Dates.dayKey(start)]);
    final byDay = {for (final r in rows) r['local_day'] as String: r};
    return List.generate(days, (i) {
      final d = DateTime(start.year, start.month, start.day + i);
      final k = Dates.dayKey(d);
      final r = byDay[k];
      return DayActivity(
        day: k,
        newWords: (r?['new_words'] as int?) ?? 0,
        reviews: (r?['reviews'] as int?) ?? 0,
        correct: (r?['correct'] as int?) ?? 0,
        answers: (r?['answers'] as int?) ?? 0,
      );
    });
  }

  Future<Map<String, DayActivity>> activityForMonth(int year, int month) async {
    final from = Dates.dayKey(DateTime(year, month, 1));
    final to = Dates.dayKey(DateTime(year, month + 1, 0));
    final rows = await db.rawQuery('SELECT * FROM study_activity WHERE local_day BETWEEN ? AND ?', [from, to]);
    return {
      for (final r in rows)
        r['local_day'] as String: DayActivity(
          day: r['local_day'] as String,
          newWords: r['new_words'] as int,
          reviews: r['reviews'] as int,
          correct: r['correct'] as int,
          answers: r['answers'] as int,
        ),
    };
  }

  Future<double?> retention() async {
    final rows = await db.rawQuery('SELECT * FROM learning_cards WHERE stability IS NOT NULL AND last_review IS NOT NULL');
    if (rows.isEmpty) return null;
    final now = clock().toUtc();
    var sum = 0.0;
    for (final r in rows) {
      sum += scheduler.retrievability(CardState.fromRow(r), now);
    }
    return sum / rows.length;
  }

  Future<DashboardStats> dashboard() async {
    final now = clock();
    final today = Dates.dayKey(now);
    final t = await db.query('study_activity', where: 'local_day=?', whereArgs: [today]);
    final due =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM learning_cards WHERE due <= ?', [now.toUtc().millisecondsSinceEpoch]),
        ) ??
        0;
    final total = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM learning_cards')) ?? 0;
    final mastered = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM learning_cards WHERE state=2 AND stability>=21')) ?? 0;
    final entries = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM c.vocabulary_entries')) ?? 0;
    return DashboardStats(
      newToday: t.isEmpty ? 0 : t.first['new_words'] as int,
      reviewsToday: t.isEmpty ? 0 : t.first['reviews'] as int,
      dueNow: due,
      totalStudied: total,
      mastered: mastered,
      retention: await retention(),
      streak: Dates.streak(await activeDays(), now: now),
      week: await activityRange(7),
      totalEntries: entries,
    );
  }

  Future<List<TopicMastery>> topicMastery() async {
    final rows = await db.rawQuery('''
      SELECT t.code, t.name_vi, t.icon, COUNT(vt.entry_id) AS total,
             SUM(CASE WHEN lc.entry_id IS NOT NULL THEN 1 ELSE 0 END) AS learned,
             SUM(CASE WHEN lc.state = 2 AND lc.stability >= 21 THEN 1 ELSE 0 END) AS mastered
      FROM c.topics t JOIN c.vocabulary_topics vt ON vt.topic_id = t.id
      LEFT JOIN learning_cards lc ON lc.entry_id = vt.entry_id
      WHERE t.category = 'ielts' GROUP BY t.id ORDER BY learned DESC, t.sort_order''');
    return rows
        .map(
          (r) => TopicMastery(
            r['code'] as String,
            r['name_vi'] as String,
            r['icon'] as String?,
            r['total'] as int,
            (r['learned'] as int?) ?? 0,
            (r['mastered'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  Future<List<QuizSessionRecord>> quizHistory({int limit = 30}) async {
    final rows = await db.rawQuery('SELECT * FROM quiz_sessions ORDER BY started_at DESC LIMIT ?', [limit]);
    return rows
        .map(
          (r) => QuizSessionRecord(
            id: r['id'] as int,
            quizType: r['quiz_type'] as String,
            startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int, isUtc: true),
            total: r['total'] as int,
            correct: r['correct'] as int,
          ),
        )
        .toList();
  }

  Future<FullStats> full() async {
    final now = clock();
    final total = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM learning_cards')) ?? 0;
    final mastered = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM learning_cards WHERE state=2 AND stability>=21')) ?? 0;
    final due =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM learning_cards WHERE due <= ?', [now.toUtc().millisecondsSinceEpoch]),
        ) ??
        0;
    final agg = (await db.rawQuery(
      'SELECT COALESCE(SUM(answers),0) a, COALESCE(SUM(correct),0) c, COALESCE(SUM(reviews),0) r, COALESCE(SUM(study_ms),0) ms FROM study_activity',
    )).first;
    final days = await activeDays();
    final ratings = await db.rawQuery('SELECT rating, COUNT(*) n FROM review_history GROUP BY rating');
    final recent = await db.rawQuery('''
      SELECT rh.rating, rh.reviewed_at, rh.mode, e.headword, e.id FROM review_history rh
      JOIN c.vocabulary_entries e ON e.id = rh.entry_id ORDER BY rh.reviewed_at DESC LIMIT 40''');
    return FullStats(
      totalStudied: total,
      mastered: mastered,
      learning: total - mastered,
      dueNow: due,
      totalAnswers: (agg['a'] as num).toInt(),
      correctAnswers: (agg['c'] as num).toInt(),
      streak: Dates.streak(days, now: now),
      longestStreak: Dates.longestStreak(days),
      totalReviews: (agg['r'] as num).toInt(),
      studyMinutes: ((agg['ms'] as num).toInt() / 60000).round(),
      last30: await activityRange(30),
      topics: await topicMastery(),
      quizzes: await quizHistory(),
      recentReviews: recent,
      ratingCounts: {for (final r in ratings) r['rating'] as int: r['n'] as int},
    );
  }
}
