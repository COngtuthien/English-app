// End-to-end test on a real device / emulator:
//   flutter test integration_test/app_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/app.dart';
import 'package:ielts_vocabulary_master/core/widgets/common.dart';
import 'package:ielts_vocabulary_master/main.dart';
import 'package:ielts_vocabulary_master/providers.dart';
import 'package:integration_test/integration_test.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 40)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(IeltsVocabularyApp)));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full offline learning journey on device', (tester) async {
    // ---- first launch: database copied from the APK, onboarding shown
    await tester.pumpWidget(const BootstrapApp());
    await pumpUntil(tester, find.byType(IeltsVocabularyApp));
    var c = containerOf(tester);
    final db = c.read(databaseProvider).db;
    // clean slate in case the test is re-run on the same install
    for (final t in [
      'quiz_answers',
      'quiz_sessions',
      'review_history',
      'learning_cards',
      'favorites',
      'study_queue',
      'achievements',
      'study_activity',
      'user_settings',
    ]) {
      await db.delete(t);
    }
    final total = (await db.rawQuery('SELECT COUNT(*) n FROM c.vocabulary_entries')).first['n'] as int;
    expect(total, greaterThanOrEqualTo(10000));

    // FTS4 must work with Android's system SQLite
    final fts = await db.rawQuery("SELECT docid FROM c.search_index WHERE search_index MATCH 'kinh* te*' LIMIT 5");
    expect(fts, isNotEmpty);

    // restart the UI so onboarding appears for the cleared settings
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const BootstrapApp());
    await pumpUntil(tester, find.text('Bỏ qua'));
    await tester.tap(find.text('Bỏ qua'));
    await pumpUntil(tester, find.text('Thiết lập mục tiêu'));
    await tester.tap(find.text('Bắt đầu học'));
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));

    // ---- learn new words through the flashcard UI (regression: grading must advance)
    await tester.tap(find.text('Học từ mới'));
    await pumpUntil(tester, find.text('Hiện đáp án'));
    String counter() => tester.widget<Text>(find.byKey(const ValueKey('flash-counter'))).data!;
    expect(counter(), startsWith('1/'));
    await tester.tap(find.byKey(const ValueKey('flash-card'))); // reveal by tapping the card itself
    await pumpUntil(tester, find.byKey(const ValueKey('grade-good')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('grade-good')));
    await pumpUntil(tester, find.text('Hiện đáp án')); // next card, face-down
    expect(counter(), startsWith('2/'));
    expect(find.byKey(const ValueKey('grade-good')), findsNothing);
    await tester.pump(const Duration(milliseconds: 500)); // let the card transition finish
    // swipe right -> back to card 1 (already graded), swipe left -> card 2 again
    await tester.fling(find.byKey(const ValueKey('flash-card')).last, const Offset(300, 0), 1200);
    await tester.pump(const Duration(milliseconds: 600));
    expect(counter(), startsWith('1/'));
    await tester.fling(find.byKey(const ValueKey('flash-card')).last, const Offset(-300, 0), 1200);
    await tester.pump(const Duration(milliseconds: 600));
    expect(counter(), startsWith('2/'));
    await tester.tap(find.byKey(const ValueKey('flash-card')).last); // tap reveals the answer
    await pumpUntil(tester, find.byKey(const ValueKey('grade-easy')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('grade-easy')));
    await pumpUntil(tester, find.text('Hiện đáp án'));
    expect(counter(), startsWith('3/'));
    await tester.pump(const Duration(seconds: 1));
    c = containerOf(tester);
    final cards = await c.read(databaseProvider).db.query('learning_cards');
    expect(cards.length, 2);
    expect((await c.read(databaseProvider).db.query('review_history')).length, 2);
    c.read(routerProvider).pop();
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));

    // ---- dictionary search (Vietnamese, no diacritics)
    await tester.tap(find.text('Từ điển').last);
    await pumpUntil(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'moi truong');
    await pumpUntil(tester, find.byType(WordTile));

    // ---- close and reopen the app: progress must persist
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const BootstrapApp());
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));
    c = containerOf(tester);
    final after = await c.read(databaseProvider).db.query('learning_cards');
    expect(after.length, 2, reason: 'learning progress survives restart');
    expect((await c.read(databaseProvider).db.query('review_history')).length, 2, reason: 'review history survives restart');
    expect(c.read(settingsProvider).onboarded, isTrue, reason: 'settings survive restart');

    // ---- quiz
    await tester.tap(find.text('Luyện tập').last);
    await pumpUntil(tester, find.text('Quiz từ vựng'));
    await tester.tap(find.text('Quiz từ vựng'));
    await pumpUntil(tester, find.text('5 câu'));
    await tester.tap(find.text('5 câu'));
    await tester.tap(find.text('Bắt đầu'));
    await pumpUntil(tester, find.text('Câu 1/5'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('A'));
      await tester.pump(const Duration(milliseconds: 400));
      final next = find.text(i < 4 ? 'Câu tiếp theo' : 'Xem kết quả');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await pumpUntil(tester, find.text('Kết quả quiz'));
    final sessions = await c.read(databaseProvider).db.query('quiz_sessions');
    expect(sessions.single['total'], 5);

    // ---- backup & restore (service level; the system file picker cannot be automated)
    final svc = c.read(backupServiceProvider);
    final bytes = await svc.exportBytes();
    await c.read(databaseProvider).db.delete('learning_cards');
    expect(await c.read(databaseProvider).db.query('learning_cards'), isEmpty);
    final summary = await svc.restore(bytes);
    expect(summary.learnedWords, 2);
    expect((await c.read(databaseProvider).db.query('learning_cards')).length, 2);
  });
}
