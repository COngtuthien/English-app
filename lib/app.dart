import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'domain/quiz/quiz_engine.dart';
import 'features/about/about_screen.dart';
import 'features/achievements/achievements_screen.dart';
import 'features/backup/backup_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/dictionary/dictionary_screen.dart';
import 'features/home/home_screen.dart';
import 'features/learn/flashcard_session_screen.dart';
import 'features/lists/word_lists_screen.dart';
import 'features/listening/listening_screen.dart';
import 'features/matching/matching_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/practice/practice_hub_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/quiz/quiz_play_screen.dart';
import 'features/quiz/quiz_result_screen.dart';
import 'features/quiz/quiz_selection_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/speaking/speaking_screens.dart';
import 'features/stats/stats_screen.dart';
import 'features/topics/topic_words_screen.dart';
import 'features/topics/topics_screen.dart';
import 'features/typing/typing_screen.dart';
import 'features/word/word_detail_screen.dart';
import 'features/writing/writing_screen.dart';
import 'providers.dart';

final _rootKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    redirect: (context, state) {
      final onboarded = ref.read(settingsProvider).onboarded;
      final going = state.matchedLocation;
      if (!onboarded && going != '/onboarding') return '/onboarding';
      if (onboarded && going == '/onboarding') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (c, s) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/topics', builder: (c, s) => const TopicsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/practice', builder: (c, s) => const PracticeHubScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/dictionary', builder: (c, s) => const DictionaryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/topic/:code',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => TopicWordsScreen(code: s.pathParameters['code']!),
      ),
      GoRoute(
        path: '/word/:id',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => WordDetailScreen(id: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/learn',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => FlashcardSessionScreen(kind: SessionKind.learnNew, topicId: int.tryParse(s.uri.queryParameters['topic'] ?? '')),
      ),
      GoRoute(
        path: '/review',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => const FlashcardSessionScreen(kind: SessionKind.review),
      ),
      GoRoute(
        path: '/flashcards',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => FlashcardSessionScreen(
          kind: SessionKind.values.byName(s.uri.queryParameters['kind'] ?? 'random'),
          topicId: int.tryParse(s.uri.queryParameters['topic'] ?? ''),
        ),
      ),
      GoRoute(path: '/quiz', parentNavigatorKey: _rootKey, builder: (c, s) => const QuizSelectionScreen()),
      GoRoute(
        path: '/quiz/play',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => QuizPlayScreen(config: s.extra as QuizConfig),
      ),
      GoRoute(
        path: '/quiz/result',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => QuizResultScreen(result: s.extra as QuizResult),
      ),
      GoRoute(path: '/match', parentNavigatorKey: _rootKey, builder: (c, s) => const MatchingScreen()),
      GoRoute(path: '/typing', parentNavigatorKey: _rootKey, builder: (c, s) => const TypingScreen()),
      GoRoute(path: '/listening', parentNavigatorKey: _rootKey, builder: (c, s) => const ListeningScreen()),
      GoRoute(path: '/writing', parentNavigatorKey: _rootKey, builder: (c, s) => const WritingScreen()),
      GoRoute(path: '/speaking', parentNavigatorKey: _rootKey, builder: (c, s) => const SpeakingListScreen()),
      GoRoute(
        path: '/speaking/:code',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => SpeakingPackScreen(code: s.pathParameters['code']!),
      ),
      GoRoute(
        path: '/words/:kind',
        parentNavigatorKey: _rootKey,
        builder: (c, s) => WordListsScreen(kind: WordListKind.values.byName(s.pathParameters['kind']!)),
      ),
      GoRoute(path: '/stats', parentNavigatorKey: _rootKey, builder: (c, s) => const StatsScreen()),
      GoRoute(path: '/achievements', parentNavigatorKey: _rootKey, builder: (c, s) => const AchievementsScreen()),
      GoRoute(path: '/calendar', parentNavigatorKey: _rootKey, builder: (c, s) => const CalendarScreen()),
      GoRoute(path: '/settings', parentNavigatorKey: _rootKey, builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/backup', parentNavigatorKey: _rootKey, builder: (c, s) => const BackupScreen()),
      GoRoute(path: '/about', parentNavigatorKey: _rootKey, builder: (c, s) => const AboutScreen()),
    ],
  );
}

final routerProvider = Provider<GoRouter>((ref) => buildRouter(ref));

class IeltsVocabularyApp extends ConsumerWidget {
  const IeltsVocabularyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp.router(
      title: 'IELTS Vocabulary Master',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class MainShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const MainShell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Trang chủ'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Chủ đề'),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports_rounded),
            label: 'Luyện tập',
          ),
          NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.manage_search_rounded), label: 'Từ điển'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Cá nhân'),
        ],
      ),
    );
  }
}
