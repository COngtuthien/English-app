import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/data/repositories/settings_repository.dart';
import 'package:ielts_vocabulary_master/features/learn/flashcard_session_screen.dart';
import 'package:ielts_vocabulary_master/providers.dart';

import '../helpers/test_db.dart';

/// Regression tests for "flashcard does not move to the next card" (fix/flashcard-next-navigation).
void main() {
  late TestDb t;
  setUp(() async => t = await TestDb.open());
  tearDown(() => t.close());

  Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 100; i++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    throw TestFailure('timed out waiting for $f');
  }

  Future<void> start(WidgetTester tester, {int daily = 3}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(t.db),
          initialSettingsProvider.overrideWithValue(AppSettings(onboarded: true, dailyNewWords: daily)),
        ],
        child: const MaterialApp(home: FlashcardSessionScreen(kind: SessionKind.learnNew)),
      ),
    );
    await pumpUntil(tester, find.text('Hiện đáp án'));
    await pumpFor(tester, 300); // interval preview loaded
  }

  String counter(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('flash-counter'))).data!;

  /// Headword shown on the front of the current card (the largest text on the card).
  String frontHeadword(WidgetTester tester) {
    final texts = tester.widgetList<Text>(find.byType(Text)).where((x) => (x.style?.fontSize ?? 0) == 34).toList();
    return texts.last.data!;
  }

  testWidgets('reveal by tapping the card, grade Good, advance to the next face-down card and save', (tester) async {
    await start(tester);
    expect(counter(tester), '1/3');
    final first = frontHeadword(tester);

    await tester.tap(find.text('Chạm để lật thẻ'));
    await pumpFor(tester, 500);
    expect(find.text('Chọn mức độ ghi nhớ để chuyển sang từ tiếp theo.'), findsOneWidget);
    expect(find.byKey(const ValueKey('grade-good')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('grade-good')));
    await tester.pump(); // a single frame: the UI must advance without waiting for the database
    expect(find.text('Hiện đáp án'), findsOneWidget, reason: 'next card starts face-down');
    expect(find.byKey(const ValueKey('grade-good')), findsNothing);
    await pumpFor(tester);
    expect(frontHeadword(tester), isNot(first));
    expect(counter(tester), '2/4', reason: '3 words + the first one again after its 10-minute learning step');

    final history = await t.db.db.query('review_history');
    expect(history.length, 1);
    expect(history.single['rating'], Grade3.good);
    expect((await t.db.db.query('learning_cards')).length, 1);
  });

  testWidgets('double tapping a grade button saves only one review', (tester) async {
    await start(tester);
    await tester.tap(find.text('Hiện đáp án'));
    await pumpFor(tester, 500);
    final good = find.byKey(const ValueKey('grade-good'));
    await tester.tap(good);
    await tester.tap(good, warnIfMissed: false); // second tap in the same frame
    await pumpFor(tester);
    expect((await t.db.db.query('review_history')).length, 1);
    expect(counter(tester), '2/4');
  });

  testWidgets('the only card graded Good ends the session (no repeat of the same card)', (tester) async {
    await start(tester, daily: 1);
    await tester.tap(find.text('Hiện đáp án'));
    await pumpFor(tester, 500);
    await tester.tap(find.byKey(const ValueKey('grade-good')));
    await pumpFor(tester);
    expect(find.text('Hoàn thành phiên học!'), findsOneWidget);
    expect(find.textContaining('sẽ xuất hiện lại trong phần Ôn tập'), findsOneWidget);
    expect(find.text('Đã lưu tiến độ'), findsOneWidget);
    expect((await t.db.db.query('review_history')).length, 1);
  });

  testWidgets('every card can be completed and the summary is shown after the last one', (tester) async {
    await start(tester, daily: 3);
    final seen = <String>[];
    for (var i = 0; i < 3; i++) {
      seen.add(frontHeadword(tester));
      await tester.tap(find.text('Hiện đáp án'));
      await pumpFor(tester, 500);
      await tester.tap(find.byKey(const ValueKey('grade-easy')));
      await pumpFor(tester);
    }
    expect(seen.toSet().length, 3, reason: 'no card repeated or skipped');
    expect(find.text('Hoàn thành phiên học!'), findsOneWidget);
    expect((await t.db.db.query('learning_cards')).length, 3);
    expect((await t.db.db.query('review_history')).length, 3);
  });
}

/// Rating value stored for "Nhớ" (FSRS Good).
abstract final class Grade3 {
  static const good = 3;
}
