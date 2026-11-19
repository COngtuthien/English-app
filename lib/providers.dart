import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/db/app_database.dart';
import 'data/models/models.dart';
import 'data/repositories/achievement_repository.dart';
import 'data/repositories/learning_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/stats_repository.dart';
import 'data/repositories/vocabulary_repository.dart';
import 'data/services/backup_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/tts_service.dart';
import 'domain/quiz/quiz_engine.dart';
import 'domain/srs/srs_scheduler.dart';

/// Overridden in main() / tests with the opened database.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('database not initialised'));

final schedulerProvider = Provider<SrsScheduler>((ref) => SrsScheduler());
final vocabRepoProvider = Provider((ref) => VocabularyRepository(ref.watch(databaseProvider).db));
final learningRepoProvider = Provider((ref) => LearningRepository(ref.watch(databaseProvider).db, ref.watch(schedulerProvider)));
final statsRepoProvider = Provider((ref) => StatsRepository(ref.watch(databaseProvider).db, ref.watch(schedulerProvider)));
final achievementRepoProvider = Provider((ref) => AchievementRepository(ref.watch(databaseProvider).db));
final settingsRepoProvider = Provider((ref) => SettingsRepository(ref.watch(databaseProvider).db));
final backupServiceProvider = Provider((ref) => BackupService(ref.watch(databaseProvider).db));
final quizEngineProvider = Provider((ref) => QuizEngine(ref.watch(vocabRepoProvider)));
final ttsProvider = Provider<TtsService>((ref) => TtsService());
final notificationProvider = Provider<NotificationService>((ref) => NotificationService());

/// Initial settings loaded before the UI starts (overridden in main()).
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsRepository repo;
  SettingsNotifier(this.repo, AppSettings initial) : super(initial);

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final next = change(state);
    state = next;
    await repo.save(next);
  }

  void replace(AppSettings s) => state = s;
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(ref.watch(settingsRepoProvider), ref.watch(initialSettingsProvider)),
);

/// Incremented after any change to learning data so dependent views refresh.
final dataVersionProvider = StateProvider<int>((ref) => 0);

final dashboardProvider = FutureProvider.autoDispose<DashboardStats>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(statsRepoProvider).dashboard();
});

final topicsProvider = FutureProvider.autoDispose<List<TopicInfo>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(vocabRepoProvider).topics();
});

final entryDetailProvider = FutureProvider.autoDispose.family<EntryDetail?, int>((ref, id) {
  return ref.watch(vocabRepoProvider).detail(id);
});

final cardStateProvider = FutureProvider.autoDispose.family<CardState?, int>((ref, id) {
  ref.watch(dataVersionProvider);
  return ref.watch(learningRepoProvider).card(id);
});

final isFavoriteProvider = FutureProvider.autoDispose.family<bool, int>((ref, id) {
  ref.watch(dataVersionProvider);
  return ref.watch(learningRepoProvider).isFavorite(id);
});

final inQueueProvider = FutureProvider.autoDispose.family<bool, int>((ref, id) {
  ref.watch(dataVersionProvider);
  return ref.watch(learningRepoProvider).inStudyQueue(id);
});

final favoritesProvider = FutureProvider.autoDispose<List<EntrySummary>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(learningRepoProvider).favorites();
});

final difficultProvider = FutureProvider.autoDispose<List<EntrySummary>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(learningRepoProvider).difficultWords();
});

final recentProvider = FutureProvider.autoDispose<List<EntrySummary>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(learningRepoProvider).recentlyStudied();
});

final missedProvider = FutureProvider.autoDispose<List<EntrySummary>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(learningRepoProvider).missedWords();
});

final fullStatsProvider = FutureProvider.autoDispose<FullStats>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(statsRepoProvider).full();
});

final achievementsProvider = FutureProvider.autoDispose<Map<String, DateTime>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(achievementRepoProvider).unlocked();
});

final ttsStatusProvider = StreamProvider<TtsStatus>((ref) async* {
  final tts = ref.watch(ttsProvider);
  yield tts.status;
  await tts.init();
  yield tts.status;
  yield* tts.statusStream;
});

/// Call after any learning activity: re-evaluates achievements, refreshes views and
/// shows a celebration for newly unlocked achievements.
Future<void> afterLearningActivity(WidgetRef ref, [BuildContext? context]) async {
  final fresh = await ref.read(achievementRepoProvider).evaluate();
  ref.read(dataVersionProvider.notifier).state++;
  if (context != null && context.mounted && fresh.isNotEmpty) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    for (final a in fresh) {
      messenger?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.emoji_events, color: Colors.amber),
              const SizedBox(width: 12),
              Expanded(child: Text('Thành tích mới: ${a.title}')),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
