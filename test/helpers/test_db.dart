import 'dart:io';

import 'package:ielts_vocabulary_master/data/db/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the real bundled content database (assets/db/vocab.db, copied to a temp dir)
/// plus a fresh user database. Uses the no-isolate FFI factory so it also works inside
/// widget tests (fake async zone).
class TestDb {
  final AppDatabase db;
  final Directory dir;
  TestDb(this.db, this.dir);

  static String? _contentCopy;

  static Future<TestDb> open({String? userDbPath}) async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('ivm_test_');
    _contentCopy ??= await _copyContent();
    final userPath = userDbPath ?? p.join(dir.path, 'user.db');
    final db = await AppDatabase.open(contentPath: _contentCopy!, userPath: userPath, factory: databaseFactoryFfiNoIsolate);
    return TestDb(db, dir);
  }

  static Future<String> _copyContent() async {
    final src = File('assets/db/vocab.db');
    if (!src.existsSync()) {
      throw StateError('assets/db/vocab.db missing – run scripts/validate_vocabulary.ps1 / build_database.py first');
    }
    final tmp = await Directory.systemTemp.createTemp('ivm_content_');
    final dst = p.join(tmp.path, 'vocab.db');
    await src.copy(dst);
    return dst;
  }

  Future<void> close() async {
    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
