import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/app.dart';
import 'package:ielts_vocabulary_master/core/widgets/common.dart';
import 'package:ielts_vocabulary_master/data/repositories/learning_repository.dart';
import 'package:ielts_vocabulary_master/data/repositories/settings_repository.dart';
import 'package:ielts_vocabulary_master/data/repositories/vocabulary_repository.dart';
import 'package:ielts_vocabulary_master/domain/srs/srs_scheduler.dart';
import 'package:ielts_vocabulary_master/features/learn/flashcard_session_screen.dart';
import 'package:ielts_vocabulary_master/providers.dart';

import '../helpers/test_db.dart';

/// Swipe-to-flip and "choose how many cards / questions" behaviour.
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
    for (var i = 0; i < 120; i++) {
      if (f.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 50));
    }
    throw TestFailure('timed out waiting for $f');
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget session(FlashcardSessionScreen screen) => ProviderScope(
    overrides: [databaseProvider.overrideWithValue(t.db), initialSettingsProvider.overrideWithValue(const AppSettings(onboarded: true))],
    child: MaterialApp(home: screen),
  );

  String counter(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('flash-counter'))).data!;

  /// Headword on the front of the current card (34 pt text).
  String headword(WidgetTester tester) =>
      tester.widgetList<Text>(find.byType(Text)).where((x) => (x.style?.fontSize ?? 0) == 34).last.data!;
  Finder card() => find.byKey(const ValueKey('flash-card')).last;

  testWidgets('tap reveals; swipe left = next card, swipe right = previous card; vertical swipe does nothing', (tester) async {
    phone(tester);
    await tester.pumpWidget(session(const FlashcardSessionScreen(kind: SessionKind.learnNew, count: 3)));
    await pumpUntil(tester, find.text('Hiện đáp án'));
    expect(find.text('Vuốt trái: thẻ tiếp'), findsOneWidget);
    final first = headword(tester);

    // tap the card -> answer shown
    await tester.tap(card());
    await pumpFor(tester, 500);
    expect(find.byKey(const ValueKey('grade-good')), findsOneWidget);
    // tap again -> hidden
    await tester.tap(card());
    await pumpFor(tester, 500);
    expect(find.text('Hiện đáp án'), findsOneWidget);
    // "Hiện đáp án" button -> answer shown
    await tester.tap(find.text('Hiện đáp án'));
    await pumpFor(tester, 500);
    expect(find.byKey(const ValueKey('grade-good')), findsOneWidget);

    // vertical swipe: nothing happens
    await tester.fling(card(), const Offset(0, -300), 1200);
    await pumpFor(tester, 500);
    expect(counter(tester), '1/3');
    expect(find.byKey(const ValueKey('grade-good')), findsOneWidget);

    // a short, slow drag springs back to the same card
    await tester.timedDrag(card(), const Offset(-40, 0), const Duration(milliseconds: 600));
    await pumpFor(tester, 800);
    expect(counter(tester), '1/3');
    expect(find.byKey(const ValueKey('grade-good')), findsOneWidget, reason: 'still the same revealed card');

    // swipe left -> next card, face-down, nothing saved
    await tester.fling(card(), const Offset(-300, 0), 1200);
    await pumpFor(tester, 600);
    expect(counter(tester), '2/3');
    expect(find.text('Hiện đáp án'), findsOneWidget);
    final second = headword(tester);
    expect(second, isNot(first));
    expect(await t.db.db.query('review_history'), isEmpty);

    // swipe right -> back to the first card
    await tester.fling(card(), const Offset(300, 0), 1200);
    await pumpFor(tester, 600);
    expect(counter(tester), '1/3');
    expect(headword(tester), first);
    expect(find.text('Hiện đáp án'), findsOneWidget);

    // swipe right on the first card stays on the first card
    await tester.fling(card(), const Offset(300, 0), 1200);
    await pumpFor(tester, 600);
    expect(counter(tester), '1/3');
    expect(find.text('Đây là thẻ đầu tiên'), findsOneWidget);
  });

  testWidgets('graded card revisited by swiping back shows its grade and cannot be graded again', (tester) async {
    phone(tester);
    await tester.pumpWidget(session(const FlashcardSessionScreen(kind: SessionKind.learnNew, count: 3)));
    await pumpUntil(tester, find.text('Hiện đáp án'));
    await tester.tap(find.text('Hiện đáp án'));
    await pumpFor(tester, 500);
    await tester.tap(find.byKey(const ValueKey('grade-easy')));
    await pumpFor(tester);
    expect(counter(tester), '2/3');

    await tester.fling(card(), const Offset(300, 0), 1200);
    await pumpFor(tester, 600);
    expect(counter(tester), '1/3');
    await tester.tap(find.text('Hiện đáp án'));
    await pumpFor(tester, 500);
    expect(find.byKey(const ValueKey('already-graded')), findsOneWidget);
    expect(find.textContaining('Bạn đã chấm thẻ này: Dễ'), findsOneWidget);
    expect(find.byKey(const ValueKey('grade-easy')), findsNothing);
    expect((await t.db.db.query('review_history')).length, 1);
  });

  testWidgets('swiping past the last card shows the summary with skipped words; can go back', (tester) async {
    phone(tester);
    await tester.pumpWidget(session(const FlashcardSessionScreen(kind: SessionKind.learnNew, count: 2)));
    await pumpUntil(tester, find.text('Hiện đáp án'));
    await tester.tap(find.text('Hiện đáp án'));
    await pumpFor(tester, 500);
    await tester.tap(find.byKey(const ValueKey('grade-easy'))); // card 1 graded
    await pumpFor(tester);
    await tester.fling(card(), const Offset(-300, 0), 1200); // card 2 skipped
    await pumpFor(tester, 600);
    expect(find.text('Hoàn thành phiên học!'), findsOneWidget);
    expect(find.byKey(const ValueKey('skipped-note')), findsOneWidget);
    expect(find.textContaining('1 từ bạn vuốt qua chưa chấm'), findsOneWidget);
    expect((await t.db.db.query('review_history')).length, 1);

    await tester.tap(find.byKey(const ValueKey('back-to-cards')));
    await pumpFor(tester, 600);
    expect(counter(tester), '2/2');
    expect(find.text('Hiện đáp án'), findsOneWidget);
  });

  testWidgets('chosen count is respected for topic, random and new-word sessions', (tester) async {
    phone(tester);
    final topics = await VocabularyRepository(t.db.db).topics();
    final edu = topics.firstWhere((x) => x.code == 'education');

    await tester.pumpWidget(session(FlashcardSessionScreen(kind: SessionKind.topic, topicId: edu.id, count: 5)));
    await pumpUntil(tester, find.byKey(const ValueKey('flash-counter')));
    expect(counter(tester), '1/5');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(session(const FlashcardSessionScreen(kind: SessionKind.random, count: 7)));
    await pumpUntil(tester, find.byKey(const ValueKey('flash-counter')));
    expect(counter(tester), '1/7');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(session(FlashcardSessionScreen(kind: SessionKind.learnNew, topicId: edu.id, count: 4)));
    await pumpUntil(tester, find.byKey(const ValueKey('flash-counter')));
    expect(counter(tester), '1/4');
  });

  testWidgets('difficult-word review uses the chosen count or all words', (tester) async {
    phone(tester);
    final learn = LearningRepository(t.db.db, SrsScheduler(enableFuzzing: false));
    final words = await learn.nextNewWords(6, const AppSettings());
    for (final w in words) {
      await learn.review(w.id, Grade.again); // lapses / "again" -> difficult list
    }
    await tester.pumpWidget(session(const FlashcardSessionScreen(kind: SessionKind.difficult, count: 4)));
    await pumpUntil(tester, find.byKey(const ValueKey('flash-counter')));
    expect(counter(tester), '1/4');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(session(const FlashcardSessionScreen(kind: SessionKind.difficult, count: kCountAll)));
    await pumpUntil(tester, find.byKey(const ValueKey('flash-counter')));
    expect(counter(tester), '1/6');
  });

  testWidgets('count picker: preset, custom value, validation and "Tất cả"', (tester) async {
    phone(tester);
    final results = <int?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async => results.add(await showCountPicker(context, title: 'Ôn từ khó', allowAll: true)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.text('open'));
      await pumpFor(tester, 600);
    }

    await open();
    await tester.tap(find.byKey(const ValueKey('count-30')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('count-start')));
    await pumpFor(tester, 600);

    await open();
    await tester.enterText(find.byKey(const ValueKey('count-custom')), '12');
    await tester.tap(find.byKey(const ValueKey('count-start')));
    await pumpFor(tester, 600);

    await open();
    await tester.enterText(find.byKey(const ValueKey('count-custom')), '0');
    await tester.tap(find.byKey(const ValueKey('count-start')));
    await pumpFor(tester, 300);
    expect(find.textContaining('Nhập số từ 1 đến'), findsOneWidget, reason: 'invalid value is rejected');
    await tester.enterText(find.byKey(const ValueKey('count-custom')), '');
    await tester.tap(find.byKey(const ValueKey('count-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('count-start')));
    await pumpFor(tester, 600);

    expect(results, [30, 12, kCountAll]);
  });

  testWidgets('topic screen: Flashcard and Quiz ask for the number, then use it', (tester) async {
    phone(tester);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(t.db), initialSettingsProvider.overrideWithValue(const AppSettings(onboarded: true))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const IeltsVocabularyApp()));
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));
    container.read(routerProvider).push('/topic/education');
    await pumpUntil(tester, find.text('Flashcard'));

    await tester.tap(find.text('Flashcard'));
    await pumpUntil(tester, find.byKey(const ValueKey('count-5')));
    await pumpFor(tester, 400);
    await tester.tap(find.byKey(const ValueKey('count-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('count-start')));
    await pumpUntil(tester, find.byKey(const ValueKey('flash-counter')));
    expect(counter(tester), '1/5');

    container.read(routerProvider).pop();
    await pumpUntil(tester, find.text('Quiz'));
    await pumpFor(tester, 400);
    await tester.tap(find.text('Quiz'));
    await pumpUntil(tester, find.byKey(const ValueKey('count-5')));
    await pumpFor(tester, 400);
    await tester.tap(find.byKey(const ValueKey('count-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('count-start')));
    await pumpUntil(tester, find.text('Câu 1/5'));
  });
}
