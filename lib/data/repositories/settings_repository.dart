import 'dart:convert';

import 'package:sqflite/sqflite.dart';

enum StudyOrder { frequency, random, alphabetical }

enum FlashMode { enToVi, viToEn, defToWord, cloze }

class AppSettings {
  final String userName;
  final bool onboarded;
  final String currentLevel; // B1, B2, C1
  final String targetBand; // e.g. 7.5
  final int dailyNewWords;
  final int dailyReviewLimit;
  final List<String> preferredTopics;
  final String levelFocus; // 'B1','B2','C1','C2','all'
  final StudyOrder studyOrder;
  final FlashMode flashMode;
  final String accent; // 'uk' | 'us'
  final double speechRate; // 0.2 - 0.7 (flutter_tts scale on Android)
  final String themeMode; // system | light | dark
  final bool reminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final bool autoPlayAudio;

  const AppSettings({
    this.userName = '',
    this.onboarded = false,
    this.currentLevel = 'B2',
    this.targetBand = '7.5',
    this.dailyNewWords = 20,
    this.dailyReviewLimit = 200,
    this.preferredTopics = const [],
    this.levelFocus = 'B2',
    this.studyOrder = StudyOrder.frequency,
    this.flashMode = FlashMode.enToVi,
    this.accent = 'uk',
    this.speechRate = 0.45,
    this.themeMode = 'system',
    this.reminderEnabled = false,
    this.reminderHour = 20,
    this.reminderMinute = 0,
    this.autoPlayAudio = false,
  });

  AppSettings copyWith({
    String? userName,
    bool? onboarded,
    String? currentLevel,
    String? targetBand,
    int? dailyNewWords,
    int? dailyReviewLimit,
    List<String>? preferredTopics,
    String? levelFocus,
    StudyOrder? studyOrder,
    FlashMode? flashMode,
    String? accent,
    double? speechRate,
    String? themeMode,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    bool? autoPlayAudio,
  }) => AppSettings(
    userName: userName ?? this.userName,
    onboarded: onboarded ?? this.onboarded,
    currentLevel: currentLevel ?? this.currentLevel,
    targetBand: targetBand ?? this.targetBand,
    dailyNewWords: dailyNewWords ?? this.dailyNewWords,
    dailyReviewLimit: dailyReviewLimit ?? this.dailyReviewLimit,
    preferredTopics: preferredTopics ?? this.preferredTopics,
    levelFocus: levelFocus ?? this.levelFocus,
    studyOrder: studyOrder ?? this.studyOrder,
    flashMode: flashMode ?? this.flashMode,
    accent: accent ?? this.accent,
    speechRate: speechRate ?? this.speechRate,
    themeMode: themeMode ?? this.themeMode,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    autoPlayAudio: autoPlayAudio ?? this.autoPlayAudio,
  );

  Map<String, String> toMap() => {
    'userName': userName,
    'onboarded': onboarded ? '1' : '0',
    'currentLevel': currentLevel,
    'targetBand': targetBand,
    'dailyNewWords': '$dailyNewWords',
    'dailyReviewLimit': '$dailyReviewLimit',
    'preferredTopics': jsonEncode(preferredTopics),
    'levelFocus': levelFocus,
    'studyOrder': studyOrder.name,
    'flashMode': flashMode.name,
    'accent': accent,
    'speechRate': '$speechRate',
    'themeMode': themeMode,
    'reminderEnabled': reminderEnabled ? '1' : '0',
    'reminderHour': '$reminderHour',
    'reminderMinute': '$reminderMinute',
    'autoPlayAudio': autoPlayAudio ? '1' : '0',
  };

  static AppSettings fromMap(Map<String, String> m) {
    const d = AppSettings();
    int i(String k, int def) => int.tryParse(m[k] ?? '') ?? def;
    double dbl(String k, double def) => double.tryParse(m[k] ?? '') ?? def;
    List<String> topics = d.preferredTopics;
    try {
      if (m['preferredTopics'] != null) topics = (jsonDecode(m['preferredTopics']!) as List).cast<String>();
    } catch (_) {}
    return AppSettings(
      userName: m['userName'] ?? d.userName,
      onboarded: m['onboarded'] == '1',
      currentLevel: m['currentLevel'] ?? d.currentLevel,
      targetBand: m['targetBand'] ?? d.targetBand,
      dailyNewWords: i('dailyNewWords', d.dailyNewWords).clamp(1, 100),
      dailyReviewLimit: i('dailyReviewLimit', d.dailyReviewLimit).clamp(10, 1000),
      preferredTopics: topics,
      levelFocus: m['levelFocus'] ?? d.levelFocus,
      studyOrder: StudyOrder.values.firstWhere((e) => e.name == m['studyOrder'], orElse: () => d.studyOrder),
      flashMode: FlashMode.values.firstWhere((e) => e.name == m['flashMode'], orElse: () => d.flashMode),
      accent: (m['accent'] == 'us') ? 'us' : 'uk',
      speechRate: dbl('speechRate', d.speechRate).clamp(0.1, 1.0),
      themeMode: m['themeMode'] ?? d.themeMode,
      reminderEnabled: m['reminderEnabled'] == '1',
      reminderHour: i('reminderHour', d.reminderHour).clamp(0, 23),
      reminderMinute: i('reminderMinute', d.reminderMinute).clamp(0, 59),
      autoPlayAudio: m['autoPlayAudio'] == '1',
    );
  }
}

class SettingsRepository {
  final Database db;
  SettingsRepository(this.db);

  Future<AppSettings> load() async {
    final rows = await db.query('user_settings');
    return AppSettings.fromMap({for (final r in rows) r['key'] as String: r['value'] as String});
  }

  Future<void> save(AppSettings s) async {
    await db.transaction((txn) async {
      final batch = txn.batch();
      s.toMap().forEach((k, v) {
        batch.insert('user_settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await batch.commit(noResult: true);
    });
  }
}
