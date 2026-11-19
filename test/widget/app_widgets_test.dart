import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/app.dart';
import 'package:ielts_vocabulary_master/core/widgets/common.dart';
import 'package:ielts_vocabulary_master/data/repositories/learning_repository.dart';
import 'package:ielts_vocabulary_master/data/repositories/settings_repository.dart';
import 'package:ielts_vocabulary_master/domain/quiz/quiz_engine.dart';
import 'package:ielts_vocabulary_master/features/learn/flashcard_session_screen.dart';
import 'package:ielts_vocabulary_master/features/quiz/quiz_play_screen.dart';
import 'package:ielts_vocabulary_master/features/quiz/quiz_result_screen.dart';
import 'package:ielts_vocabulary_master/features/settings/settings_screen.dart';
import 'package:ielts_vocabulary_master/providers.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/test_db.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {int maxTicks = 120}) async {
  for (var i = 0; i < maxTicks; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

void main() {
  late TestDb t;

  setUpAll(() async {
    await initializeDateFormatting('vi');
  });

  setUp(() async {
    t = await TestDb.open();
  });
  tearDown(() => t.close());

  Future<void> setPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app({AppSettings settings = const AppSettings(onboarded: true, userName: 'Lan')}) => ProviderScope(
    overrides: [databaseProvider.overrideWithValue(t.db), initialSettingsProvider.overrideWithValue(settings)],
    child: const IeltsVocabularyApp(),
  );

  testWidgets('first launch shows onboarding, then goal setup leads to the dashboard', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app(settings: const AppSettings()));
    await pumpUntil(tester, find.text('Hơn 10.000 mục từ IELTS'));
    await tester.tap(find.text('Tiếp tục'));
    await pumpUntil(tester, find.text('Lặp lại ngắt quãng FSRS'));
    await tester.tap(find.text('Bỏ qua'));
    await pumpUntil(tester, find.text('Thiết lập mục tiêu'));
    await tester.enterText(find.byType(TextField).first, 'Minh');
    await tester.tap(find.text('Bắt đầu học'));
    await pumpUntil(tester, find.textContaining('Minh'));
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));
    final saved = await SettingsRepository(t.db.db).load();
    expect(saved.onboarded, isTrue);
    expect(saved.userName, 'Minh');
  });

  testWidgets('home dashboard shows daily goal, stats and quick actions', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));
    expect(find.text('Học từ mới'), findsOneWidget);
    expect(find.textContaining('Ôn tập ('), findsOneWidget);
    expect(find.text('Từ đã học'), findsOneWidget);
    expect(find.text('Hoạt động 7 ngày'), findsOneWidget);
  });

  testWidgets('dictionary search opens word detail with Vietnamese meaning and examples', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Từ điển'));
    await tester.tap(find.text('Từ điển').last);
    await pumpUntil(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'sustainable');
    await tester.pump(const Duration(milliseconds: 400));
    final tile = find.ancestor(of: find.text('sustainable'), matching: find.byType(WordTile));
    await pumpUntil(tester, tile);
    await tester.tap(tile.first);
    await pumpUntil(tester, find.textContaining('bền vững'));
    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('Nghĩa tiếng Việt'), 200, scrollable: list);
    await tester.scrollUntilVisible(find.text('Ví dụ'), 300, scrollable: list);
    expect(find.text('Ví dụ'), findsOneWidget);
  });

  testWidgets('flashcard learning session: flip, rate and persist', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(t.db),
          initialSettingsProvider.overrideWithValue(const AppSettings(onboarded: true, dailyNewWords: 3)),
        ],
        child: const MaterialApp(home: FlashcardSessionScreen(kind: SessionKind.learnNew)),
      ),
    );
    await pumpUntil(tester, find.text('Hiện đáp án'));
    expect(find.text('1/3'), findsOneWidget);
    await tester.tap(find.text('Hiện đáp án'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Nhớ'), findsOneWidget);
    expect(find.text('Quên'), findsOneWidget);
    await tester.tap(find.text('Dễ'));
    await pumpUntil(tester, find.text('2/3'));
    final cards = await t.db.db.query('learning_cards');
    expect(cards.length, 1);
    final hist = await t.db.db.query('review_history');
    expect(hist.single['rating'], 4);
  });

  testWidgets('quiz gameplay: answer all questions, results are shown and persisted', (tester) async {
    await setPhone(tester);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(t.db), initialSettingsProvider.overrideWithValue(const AppSettings(onboarded: true))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const IeltsVocabularyApp()));
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));
    container
        .read(routerProvider)
        .push('/quiz/play', extra: const QuizConfig(types: {QuestionType.enToVi}, count: 3, preferLearned: false));
    await pumpUntil(tester, find.text('Câu 1/3'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('A'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining(RegExp('Chính xác|Chưa đúng')), findsOneWidget);
      final next = i < 2 ? 'Câu tiếp theo' : 'Xem kết quả';
      await tester.ensureVisible(find.text(next));
      await tester.tap(find.text(next));
      if (i < 2) await pumpUntil(tester, find.text('Câu ${i + 2}/3'));
    }
    await pumpUntil(tester, find.text('Kết quả quiz'));
    final sessions = await t.db.db.query('quiz_sessions');
    expect(sessions.single['total'], 3);
    final answers = await t.db.db.query('quiz_answers');
    expect(answers.length, 3);
  });

  testWidgets('quiz result screen lists mistakes', (tester) async {
    await setPhone(tester);
    const q = QuizQuestion(
      type: QuestionType.enToVi,
      entryId: null,
      prompt: 'mitigate',
      options: ['giảm nhẹ', 'tăng', 'xây', 'ăn'],
      answerIndex: 0,
      correctAnswer: 'giảm nhẹ',
      explanation: 'mitigate – giảm nhẹ',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: QuizResultScreen(
          result: QuizResult(
            [q],
            [
              QuizAnswerRecord(
                entryId: null,
                questionType: 'enToVi',
                prompt: 'mitigate',
                userAnswer: 'tăng',
                correctAnswer: 'giảm nhẹ',
                correct: false,
              ),
            ],
            QuizConfig(types: {QuestionType.enToVi}, count: 1),
            Duration(seconds: 42),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('Xem lại câu sai'), findsOneWidget);
    expect(find.text('Đáp án đúng: giảm nhẹ'), findsOneWidget);
  });

  testWidgets('settings changes persist to the user database', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Cá nhân'));
    await tester.tap(find.text('Cá nhân').last);
    await pumpUntil(tester, find.text('Cài đặt'));
    await tester.tap(find.text('Cài đặt'));
    await pumpUntil(tester, find.text('Hồ sơ & mục tiêu'));
    final settingsList = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Giao diện'), 150, scrollable: settingsList);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Giao diện'));
    await pumpUntil(tester, find.text('Tối'));
    await tester.pump(const Duration(milliseconds: 600)); // let the bottom sheet finish sliding in
    await tester.tap(find.text('Tối'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Sáng'), findsNothing, reason: 'sheet closes after choosing');
    final s = await SettingsRepository(t.db.db).load();
    expect(s.themeMode, 'dark');
  });

  testWidgets('bottom navigation reaches every tab', (tester) async {
    await setPhone(tester);
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));
    await tester.tap(find.text('Chủ đề').last);
    await pumpUntil(tester, find.text('Kỹ năng & nhóm từ'));
    await tester.tap(find.text('Luyện tập').last);
    await pumpUntil(tester, find.text('Quiz từ vựng'));
    await tester.tap(find.text('Từ điển').last);
    await pumpUntil(tester, find.textContaining('Tìm tiếng Anh'));
    await tester.tap(find.text('Cá nhân').last);
    await pumpUntil(tester, find.text('Thống kê học tập'));
    await tester.tap(find.text('Trang chủ').last);
    await pumpUntil(tester, find.text('Mục tiêu hôm nay'));
  });
}
