import 'package:sqflite/sqflite.dart';

import '../../core/utils/dates.dart';

class AchievementDef {
  final String code;
  final String title;
  final String description;
  final String icon;
  const AchievementDef(this.code, this.title, this.description, this.icon);
}

const List<AchievementDef> kAchievements = [
  AchievementDef('words_10', '10 từ đầu tiên', 'Học 10 từ vựng đầu tiên', 'spa'),
  AchievementDef('words_100', '100 từ vựng', 'Học được 100 từ', 'local_florist'),
  AchievementDef('words_500', '500 từ vựng', 'Học được 500 từ', 'park'),
  AchievementDef('words_1000', '1.000 từ vựng', 'Học được 1.000 từ – vốn từ vững chắc!', 'forest'),
  AchievementDef('words_3000', '3.000 từ vựng', 'Học được 3.000 từ – tiến gần trình độ C1', 'emoji_events'),
  AchievementDef('streak_7', 'Chuỗi 7 ngày', 'Học liên tục 7 ngày', 'local_fire_department'),
  AchievementDef('streak_30', 'Chuỗi 30 ngày', 'Học liên tục 30 ngày', 'whatshot'),
  AchievementDef('perfect_quiz', 'Bài kiểm tra hoàn hảo', 'Đạt 100% một bài quiz (từ 5 câu)', 'verified'),
  AchievementDef('first_topic', 'Hoàn thành chủ đề', 'Học hết toàn bộ từ của một chủ đề', 'workspace_premium'),
  AchievementDef('reviews_100', '100 lượt ôn tập', 'Hoàn thành 100 lượt ôn tập thẻ', 'replay'),
  AchievementDef('mastered_50', 'Ghi nhớ bền vững', 'Có 50 từ đạt trạng thái thành thạo', 'psychology'),
  AchievementDef('quiz_10', 'Chăm luyện tập', 'Hoàn thành 10 bài luyện tập', 'quiz'),
];

class AchievementRepository {
  final Database db;
  final DateTime Function() clock;
  AchievementRepository(this.db, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  Future<Map<String, DateTime>> unlocked() async {
    final rows = await db.query('achievements');
    return {for (final r in rows) r['code'] as String: DateTime.fromMillisecondsSinceEpoch(r['unlocked_at'] as int, isUtc: true)};
  }

  /// Evaluates all achievements against persisted data; returns the newly unlocked ones.
  Future<List<AchievementDef>> evaluate() async {
    final have = await unlocked();
    int q(List<Map<String, Object?>> r) => Sqflite.firstIntValue(r) ?? 0;
    final words = q(await db.rawQuery('SELECT COUNT(*) FROM learning_cards'));
    final reviews = q(await db.rawQuery('SELECT COUNT(*) FROM review_history WHERE is_new = 0'));
    final mastered = q(await db.rawQuery('SELECT COUNT(*) FROM learning_cards WHERE state=2 AND stability>=21'));
    final quizzes = q(await db.rawQuery('SELECT COUNT(*) FROM quiz_sessions'));
    final perfect = q(await db.rawQuery('SELECT COUNT(*) FROM quiz_sessions WHERE total >= 5 AND correct = total'));
    final days = (await db.rawQuery(
      'SELECT local_day FROM study_activity WHERE answers > 0 OR new_words > 0 OR reviews > 0',
    )).map((r) => r['local_day'] as String).toSet();
    final longest = Dates.longestStreak(days);
    final topicDone = q(
      await db.rawQuery('''
      SELECT COUNT(*) FROM (
        SELECT vt.topic_id FROM c.vocabulary_topics vt LEFT JOIN learning_cards lc ON lc.entry_id = vt.entry_id
        GROUP BY vt.topic_id HAVING COUNT(*) >= 10 AND COUNT(lc.entry_id) = COUNT(*))'''),
    );
    final checks = <String, bool>{
      'words_10': words >= 10,
      'words_100': words >= 100,
      'words_500': words >= 500,
      'words_1000': words >= 1000,
      'words_3000': words >= 3000,
      'streak_7': longest >= 7,
      'streak_30': longest >= 30,
      'perfect_quiz': perfect > 0,
      'first_topic': topicDone > 0,
      'reviews_100': reviews >= 100,
      'mastered_50': mastered >= 50,
      'quiz_10': quizzes >= 10,
    };
    final fresh = <AchievementDef>[];
    final now = clock().toUtc().millisecondsSinceEpoch;
    for (final a in kAchievements) {
      if (checks[a.code] == true && !have.containsKey(a.code)) {
        await db.insert('achievements', {'code': a.code, 'unlocked_at': now}, conflictAlgorithm: ConflictAlgorithm.ignore);
        fresh.add(a);
      }
    }
    return fresh;
  }
}
