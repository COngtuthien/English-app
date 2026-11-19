import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_vocabulary_master/data/db/app_database.dart';
import 'package:ielts_vocabulary_master/data/repositories/vocabulary_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_db.dart';

void main() {
  late TestDb t;
  late VocabularyRepository repo;

  setUpAll(() async {
    t = await TestDb.open();
    repo = VocabularyRepository(t.db.db);
  });
  tearDownAll(() => t.close());

  group('content database', () {
    test('bundled seed database has the expected version and >= 10,000 entries', () async {
      final meta = await repo.contentMeta();
      expect(int.parse(meta['content_version']!), kContentVersion);
      expect(await repo.totalEntries(), greaterThanOrEqualTo(10000));
    });

    test('every entry satisfies the minimum quality bar', () async {
      final db = t.db.db;
      final missing = await db.rawQuery('''
        SELECT COUNT(*) n FROM c.vocabulary_entries e
        WHERE trim(primary_vi)='' OR trim(primary_def)=''
           OR NOT EXISTS (SELECT 1 FROM c.examples x WHERE x.entry_id=e.id AND x.kind='sentence')
           OR NOT EXISTS (SELECT 1 FROM c.vocabulary_topics v WHERE v.entry_id=e.id)
           OR sources = '' ''');
      expect(missing.first['n'], 0);
    });

    test('foreign keys and unique keys are consistent', () async {
      final fk = await t.db.db.rawQuery('PRAGMA c.foreign_key_check');
      expect(fk, isEmpty);
      final dup = await t.db.db.rawQuery('SELECT entry_key, COUNT(*) n FROM c.vocabulary_entries GROUP BY entry_key HAVING n > 1');
      expect(dup, isEmpty);
    });

    test('no placeholder or fabricated-looking headwords', () async {
      final bad = await t.db.db.rawQuery(
        "SELECT headword FROM c.vocabulary_entries WHERE headword GLOB '*[0-9][0-9][0-9]*' OR headword LIKE 'word\\_%' ESCAPE '\\' OR headword LIKE '%vocabulary_item%'",
      );
      expect(bad, isEmpty);
    });

    test('all 50 IELTS topics exist and each has words', () async {
      final topics = await repo.topics();
      final ielts = topics.where((t) => t.category == 'ielts').toList();
      expect(ielts.length, 50);
      expect(ielts.every((t) => t.wordCount > 0), isTrue);
    });

    test('every source is documented with a licence', () async {
      final s = await repo.sources();
      expect(s.length, greaterThanOrEqualTo(8));
      expect(s.every((x) => x.license.isNotEmpty && x.attribution.isNotEmpty), isTrue);
    });
  });

  group('search', () {
    test('English prefix search ranks exact match first', () async {
      final r = await repo.search(const VocabFilter(query: 'economy'));
      expect(r, isNotEmpty);
      expect(r.first.headword.toLowerCase(), 'economy');
    });

    test('Vietnamese meaning search works with and without diacritics', () async {
      final withAccents = await repo.search(const VocabFilter(query: 'kinh tế'));
      final noAccents = await repo.search(const VocabFilter(query: 'kinh te'));
      expect(withAccents.map((e) => e.headword.toLowerCase()), contains('economy'));
      expect(noAccents.map((e) => e.headword.toLowerCase()), contains('economy'));
    });

    test('FTS index answers queries (or the LIKE fallback does when FTS4 is not compiled in)', () async {
      try {
        final rows = await t.db.db.rawQuery("SELECT docid FROM c.search_index WHERE search_index MATCH 'moi* truong*' LIMIT 5");
        expect(rows, isNotEmpty);
      } catch (e) {
        // The SQLite build bundled with sqflite_common_ffi on Windows lacks FTS4. Android's system
        // SQLite has it (verified by integration_test on device). Check the fallback path instead.
        expect('$e', contains('fts4'));
        final r = await repo.search(const VocabFilter(query: 'môi trường'));
        expect(r.map((e) => e.headword.toLowerCase()), contains('environment'));
        markTestSkipped('FTS4 module not available in host SQLite – verified LIKE fallback instead');
      }
    });

    test('Vietnamese phrase search ranks primary-meaning matches first', () async {
      final r = await repo.search(const VocabFilter(query: 'môi trường'));
      expect(r.take(3).map((e) => e.headword.toLowerCase()), contains('environment'));
      expect(r.take(5).map((e) => e.headword.toLowerCase()), isNot(contains('this')));
    });

    test('filters: CEFR, POS, topic, pagination', () async {
      final c1 = await repo.search(const VocabFilter(cefr: {'C1'}, pos: 'verb'), limit: 30);
      expect(c1, isNotEmpty);
      expect(c1.every((e) => e.cefr == 'C1' && e.pos == 'verb'), isTrue);
      final topics = await repo.topics();
      final env = topics.firstWhere((t) => t.code == 'environment');
      final p1 = await repo.search(VocabFilter(topicId: env.id), limit: 10, offset: 0);
      final p2 = await repo.search(VocabFilter(topicId: env.id), limit: 10, offset: 10);
      expect(p1.length, 10);
      expect(p1.map((e) => e.id).toSet().intersection(p2.map((e) => e.id).toSet()), isEmpty);
    });

    test('alphabetical sort', () async {
      final r = await repo.search(const VocabFilter(sort: SortMode.alphabetical), limit: 20);
      final heads = r.map((e) => e.headword.toLowerCase()).toList();
      final sorted = [...heads]..sort();
      expect(heads, sorted);
    });

    test('word family search', () async {
      final r = await repo.familyOf('economy');
      final heads = r.map((e) => e.headword.toLowerCase()).toSet();
      expect(heads, contains('economy'));
      expect(heads.length, greaterThan(1));
    });

    test('suggestions by prefix', () async {
      final s = await repo.suggestions('sustain');
      expect(s, isNotEmpty);
      expect(s.every((w) => w.toLowerCase().startsWith('sustain')), isTrue);
    });

    test('search over 10k entries stays fast', () async {
      final sw = Stopwatch()..start();
      for (final q in ['a', 'env', 'phát triển', 'climate', 'xã hội']) {
        await repo.search(VocabFilter(query: q));
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('details', () {
    test('word detail loads senses, translations, examples and topics', () async {
      final id = (await repo.search(const VocabFilter(query: 'sustainable'))).first.id;
      final d = await repo.detail(id);
      expect(d, isNotNull);
      expect(d!.summary.meaningVi, contains('bền vững'));
      expect(d.examples.where((e) => e.isSentence), isNotEmpty);
      expect(d.topics, isNotEmpty);
      expect(d.senses, isNotEmpty);
    });

    test('writing exercises are well-formed with exactly one answer index', () async {
      final ex = await repo.writingExercises();
      expect(ex.length, greaterThanOrEqualTo(100));
      for (final e in ex) {
        expect(e.answerIndex, inInclusiveRange(0, e.options.length - 1));
        expect(e.options.toSet().length, e.options.length, reason: 'duplicate options in "${e.prompt}"');
      }
    });

    test('speaking packs cover parts 1, 2 and 3', () async {
      final packs = await repo.speakingPacks();
      expect(packs.map((p) => p.part).toSet(), {1, 2, 3});
      expect(packs.every((p) => p.questions.isNotEmpty && p.vocab.isNotEmpty), isTrue);
    });
  });

  group('user database', () {
    test('schema version and migrations', () async {
      final v = await t.db.db.getVersion();
      expect(v, kUserSchemaVersion);
      final tables = (await t.db.db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']).toSet();
      for (final name in backupTables) {
        expect(tables, contains(name));
      }
    });

    test('transactions roll back on failure', () async {
      final db = t.db.db;
      await expectLater(
        db.transaction((txn) async {
          await txn.insert('favorites', {'entry_id': 1, 'created_at': 1});
          throw StateError('boom');
        }),
        throwsStateError,
      );
      final rows = await db.query('favorites', where: 'entry_id=1');
      expect(rows, isEmpty);
    });

    test('reopening keeps user data (separate content and user files)', () async {
      final path = '${t.dir.path}/persist.db';
      final a = await TestDb.open(userDbPath: path);
      await a.db.db.insert('favorites', {'entry_id': 42, 'created_at': 1});
      await a.db.db.close();
      sqfliteFfiInit();
      final b = await TestDb.open(userDbPath: path);
      final rows = await b.db.db.query('favorites');
      expect(rows.single['entry_id'], 42);
      await b.db.db.close();
    });
  });
}
