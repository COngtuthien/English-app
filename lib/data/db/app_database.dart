import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Version of the bundled vocabulary database (assets/db/vocab.db, table meta.content_version).
/// Bump together with CONTENT_VERSION in tools/data/build_database.py.
const int kContentVersion = 1;

/// Schema version of the user (progress) database.
const int kUserSchemaVersion = 1;

/// Opens the two databases used by the app:
///  * the read-only **content** database shipped inside the APK (copied once to app storage), and
///  * the **user** database holding progress, settings and history.
/// The content database is attached to the user connection as schema `c`, so queries can join
/// learning state with vocabulary. Replacing the content file on an app update never touches
/// user progress because entry ids are stable hashes of `headword|pos`.
class AppDatabase {
  final Database db;
  final String contentPath;
  final String userPath;

  AppDatabase._(this.db, this.contentPath, this.userPath);

  static Future<AppDatabase> openForApp() async {
    final dir = await getDatabasesPath();
    await Directory(dir).create(recursive: true);
    final contentPath = await _ensureContentDb(dir);
    final userPath = p.join(dir, 'user.db');
    return open(contentPath: contentPath, userPath: userPath, factory: databaseFactory);
  }

  /// Opens with explicit paths (used by tests with sqflite_common_ffi).
  static Future<AppDatabase> open({required String contentPath, required String userPath, required DatabaseFactory factory}) async {
    final db = await factory.openDatabase(
      userPath,
      options: OpenDatabaseOptions(
        version: kUserSchemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final stmt in userSchemaV1) {
            batch.execute(stmt);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          for (var v = oldVersion + 1; v <= newVersion; v++) {
            for (final stmt in userMigrations[v] ?? const <String>[]) {
              await db.execute(stmt);
            }
          }
        },
      ),
    );
    // sqflite returns the same connection if the user DB is opened again (e.g. when Android re-creates
    // the activity in a living process), so only attach the content DB once.
    final attached = (await db.rawQuery('PRAGMA database_list')).any((r) => r['name'] == 'c');
    if (!attached) {
      await db.execute('ATTACH DATABASE ? AS c', [contentPath]);
    }
    return AppDatabase._(db, contentPath, userPath);
  }

  Future<void> close() => db.close();

  static Future<String> _ensureContentDb(String dir) async {
    final target = p.join(dir, 'vocab_v$kContentVersion.db');
    final file = File(target);
    if (await file.exists() && await file.length() > 0 && await _contentVersionOk(target)) {
      return target;
    }
    final data = await rootBundle.load('assets/db/vocab.db');
    final tmp = File('$target.tmp');
    await tmp.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(target);
    // remove previous content versions
    for (final f in Directory(dir).listSync()) {
      final name = p.basename(f.path);
      if (f is File && name.startsWith('vocab_v') && name != p.basename(target)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    return target;
  }

  static Future<bool> _contentVersionOk(String path) async {
    Database? d;
    try {
      d = await openReadOnlyDatabase(path);
      final r = await d.rawQuery("SELECT value FROM meta WHERE key='content_version'");
      return r.isNotEmpty && int.tryParse(r.first['value'] as String) == kContentVersion;
    } catch (_) {
      return false;
    } finally {
      await d?.close();
    }
  }
}

/// User database schema (version 1).
const List<String> userSchemaV1 = [
  '''CREATE TABLE learning_cards(
       entry_id INTEGER PRIMARY KEY,
       state INTEGER NOT NULL,
       step INTEGER,
       stability REAL,
       difficulty REAL,
       due INTEGER NOT NULL,
       last_review INTEGER,
       reps INTEGER NOT NULL DEFAULT 0,
       lapses INTEGER NOT NULL DEFAULT 0,
       last_rating INTEGER,
       created_at INTEGER NOT NULL)''',
  'CREATE INDEX idx_cards_due ON learning_cards(due)',
  '''CREATE TABLE review_history(
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       entry_id INTEGER NOT NULL,
       rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 4),
       mode TEXT NOT NULL,
       reviewed_at INTEGER NOT NULL,
       local_day TEXT NOT NULL,
       duration_ms INTEGER,
       state_before INTEGER,
       interval_days REAL,
       is_new INTEGER NOT NULL DEFAULT 0)''',
  'CREATE INDEX idx_review_day ON review_history(local_day)',
  'CREATE INDEX idx_review_entry ON review_history(entry_id)',
  '''CREATE TABLE quiz_sessions(
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       quiz_type TEXT NOT NULL,
       topic_code TEXT,
       started_at INTEGER NOT NULL,
       finished_at INTEGER,
       total INTEGER NOT NULL DEFAULT 0,
       correct INTEGER NOT NULL DEFAULT 0,
       local_day TEXT NOT NULL)''',
  'CREATE INDEX idx_quiz_day ON quiz_sessions(local_day)',
  '''CREATE TABLE quiz_answers(
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       session_id INTEGER NOT NULL REFERENCES quiz_sessions(id) ON DELETE CASCADE,
       entry_id INTEGER,
       question_type TEXT NOT NULL,
       prompt TEXT NOT NULL,
       user_answer TEXT,
       correct_answer TEXT NOT NULL,
       is_correct INTEGER NOT NULL,
       answered_at INTEGER NOT NULL)''',
  'CREATE INDEX idx_answers_entry ON quiz_answers(entry_id)',
  'CREATE TABLE favorites(entry_id INTEGER PRIMARY KEY, created_at INTEGER NOT NULL)',
  'CREATE TABLE study_queue(entry_id INTEGER PRIMARY KEY, added_at INTEGER NOT NULL)',
  'CREATE TABLE achievements(code TEXT PRIMARY KEY, unlocked_at INTEGER NOT NULL)',
  'CREATE TABLE user_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  '''CREATE TABLE study_activity(
       local_day TEXT PRIMARY KEY,
       new_words INTEGER NOT NULL DEFAULT 0,
       reviews INTEGER NOT NULL DEFAULT 0,
       correct INTEGER NOT NULL DEFAULT 0,
       answers INTEGER NOT NULL DEFAULT 0,
       study_ms INTEGER NOT NULL DEFAULT 0)''',
];

/// Future schema migrations: version -> statements.
const Map<int, List<String>> userMigrations = {};

/// Tables included in backups, in restore order.
const List<String> backupTables = [
  'learning_cards',
  'review_history',
  'quiz_sessions',
  'quiz_answers',
  'favorites',
  'study_queue',
  'achievements',
  'user_settings',
  'study_activity',
];
