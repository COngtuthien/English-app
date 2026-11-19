import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/core/text/vietnamese.dart';
import 'package:ielts_vocabulary_master/core/utils/dates.dart';
import 'package:ielts_vocabulary_master/data/repositories/settings_repository.dart';
import 'package:ielts_vocabulary_master/domain/quiz/answer_checker.dart';

void main() {
  group('Vietnamese normalisation', () {
    test('strips diacritics and đ', () {
      expect(stripVietnamese('Kinh tế'), 'kinh te');
      expect(stripVietnamese('ĐƯỜNG phố'), 'duong pho');
      expect(stripVietnamese('nghiên cứu khoa học'), 'nghien cuu khoa hoc');
    });
    test('builds FTS prefix query', () {
      expect(ftsPrefixQuery('Kinh tế'), '"kinh te*"');
      expect(ftsPrefixQuery('kinh'), 'kinh*');
      expect(ftsPrefixQuery('  '), '');
      expect(ftsPrefixQuery('"drop" OR x'), '"drop or x*"');
    });
    test('detects Vietnamese letters', () {
      expect(containsVietnameseLetters('môi trường'), isTrue);
      expect(containsVietnameseLetters('environment'), isFalse);
    });
  });

  group('Typed answer checking', () {
    test('case-insensitive and whitespace tolerant', () {
      expect(checkTyped('  Economy ', ['economy']).correct, isTrue);
      expect(checkTyped('ECONOMY.', ['economy']).correct, isTrue);
    });
    test('accepts British/American variants and hyphen/space', () {
      expect(checkTyped('colour', ['color', 'colour']).correct, isTrue);
      expect(checkTyped('well being', ['well-being']).correct, isTrue);
      expect(checkTyped('wellbeing', ['well-being']).correct, isTrue);
    });
    test('near miss is reported but not correct', () {
      final c = checkTyped('accomodation', ['accommodation']);
      expect(c.correct, isFalse);
      expect(c.nearMiss, isTrue);
      expect(c.distance, 1);
    });
    test('far miss is not near', () {
      final c = checkTyped('banana', ['accommodation']);
      expect(c.correct, isFalse);
      expect(c.nearMiss, isFalse);
    });
    test('empty answer is wrong', () {
      expect(checkTyped('', ['word']).correct, isFalse);
      expect(checkTyped('', ['word']).nearMiss, isFalse);
    });
    test('levenshtein', () {
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('', 'abc'), 3);
      expect(levenshtein('same', 'same'), 0);
    });
    test('blankOut replaces whole word only', () {
      expect(blankOut('The economy grew.', 'economy'), 'The _____ grew.');
      expect(blankOut('Economics is not economy.', 'economy'), 'Economics is not _____.');
      expect(blankOut('No match here', 'economy'), isNull);
    });
  });

  group('Dates & streaks', () {
    final now = DateTime(2026, 11, 19, 10);
    test('streak counts consecutive days ending today', () {
      final days = {'2026-11-19', '2026-11-18', '2026-11-17', '2026-11-15'};
      expect(Dates.streak(days, now: now), 3);
    });
    test('streak continues from yesterday if today not yet studied', () {
      final days = {'2026-11-18', '2026-11-17'};
      expect(Dates.streak(days, now: now), 2);
    });
    test('streak is zero after a missed day', () {
      expect(Dates.streak({'2026-11-16'}, now: now), 0);
    });
    test('streak across month boundary', () {
      final days = {'2026-12-01', '2026-11-30', '2026-11-29'};
      expect(Dates.streak(days, now: DateTime(2026, 12, 1, 8)), 3);
    });
    test('longest streak', () {
      expect(Dates.longestStreak(['2026-01-01', '2026-01-02', '2026-01-05', '2026-01-06', '2026-01-07']), 3);
      expect(Dates.longestStreak([]), 0);
    });
  });

  group('Settings serialisation', () {
    test('round trip', () {
      const s = AppSettings(
        userName: 'Lan',
        dailyNewWords: 30,
        preferredTopics: ['education', 'environment'],
        accent: 'us',
        flashMode: FlashMode.cloze,
      );
      final back = AppSettings.fromMap(s.toMap());
      expect(back.userName, 'Lan');
      expect(back.dailyNewWords, 30);
      expect(back.preferredTopics, ['education', 'environment']);
      expect(back.accent, 'us');
      expect(back.flashMode, FlashMode.cloze);
    });
    test('defaults match the B2 -> 7.5 learner profile', () {
      final d = AppSettings.fromMap({});
      expect(d.currentLevel, 'B2');
      expect(d.targetBand, '7.5');
      expect(d.dailyNewWords, 20);
    });
    test('corrupt values fall back to defaults', () {
      final d = AppSettings.fromMap({'dailyNewWords': 'abc', 'preferredTopics': '{bad json', 'accent': 'xx'});
      expect(d.dailyNewWords, 20);
      expect(d.preferredTopics, isEmpty);
      expect(d.accent, 'uk');
    });
  });
}
