import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/text/vietnamese.dart';
import '../models/models.dart';

enum SortMode { relevance, alphabetical, frequency, level }

enum LearnStatus { any, unseen, learning, mastered }

class VocabFilter {
  final String query;
  final int? topicId;
  final Set<String> cefr; // A1..C2 or 'none'
  final String? pos;
  final int? difficulty;
  final bool favoritesOnly;
  final LearnStatus status;
  final SortMode sort;
  final bool familySearch;

  const VocabFilter({
    this.query = '',
    this.topicId,
    this.cefr = const {},
    this.pos,
    this.difficulty,
    this.favoritesOnly = false,
    this.status = LearnStatus.any,
    this.sort = SortMode.relevance,
    this.familySearch = false,
  });

  VocabFilter copyWith({
    String? query,
    int? topicId,
    bool clearTopic = false,
    Set<String>? cefr,
    String? pos,
    bool clearPos = false,
    int? difficulty,
    bool clearDifficulty = false,
    bool? favoritesOnly,
    LearnStatus? status,
    SortMode? sort,
    bool? familySearch,
  }) => VocabFilter(
    query: query ?? this.query,
    topicId: clearTopic ? null : (topicId ?? this.topicId),
    cefr: cefr ?? this.cefr,
    pos: clearPos ? null : (pos ?? this.pos),
    difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    status: status ?? this.status,
    sort: sort ?? this.sort,
    familySearch: familySearch ?? this.familySearch,
  );

  bool get hasFilters =>
      topicId != null || cefr.isNotEmpty || pos != null || difficulty != null || favoritesOnly || status != LearnStatus.any;
}

const String _entryCols =
    'e.id,e.headword,e.pos,e.pos_vi,e.entry_type,e.cefr,e.difficulty,e.primary_vi,e.primary_def,e.ipa_uk,e.ipa_us,e.variants';

class VocabularyRepository {
  final Database db;
  bool? _ftsAvailable;
  VocabularyRepository(this.db);

  Future<int> totalEntries() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM c.vocabulary_entries')) ?? 0;

  // ------------------------------------------------------------------ topics
  Future<List<TopicInfo>> topics() async {
    final rows = await db.rawQuery('''
      SELECT t.id,t.code,t.name_en,t.name_vi,t.category,t.icon,
             COUNT(vt.entry_id) AS n,
             SUM(CASE WHEN lc.entry_id IS NOT NULL THEN 1 ELSE 0 END) AS learned
      FROM c.topics t
      LEFT JOIN c.vocabulary_topics vt ON vt.topic_id = t.id
      LEFT JOIN learning_cards lc ON lc.entry_id = vt.entry_id
      GROUP BY t.id ORDER BY t.sort_order''');
    return rows
        .map(
          (r) => TopicInfo(
            id: r['id'] as int,
            code: r['code'] as String,
            nameEn: r['name_en'] as String,
            nameVi: r['name_vi'] as String,
            category: r['category'] as String,
            icon: r['icon'] as String?,
            wordCount: (r['n'] as int?) ?? 0,
            learnedCount: (r['learned'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  Future<TopicInfo?> topicByCode(String code) async {
    final all = await topics();
    for (final t in all) {
      if (t.code == code) return t;
    }
    return null;
  }

  // ------------------------------------------------------------------ search / browse
  String _whereFilters(VocabFilter f, List<Object?> args) {
    final w = <String>[];
    if (f.topicId != null) {
      w.add('e.id IN (SELECT entry_id FROM c.vocabulary_topics WHERE topic_id = ?)');
      args.add(f.topicId);
    }
    if (f.cefr.isNotEmpty) {
      final levels = f.cefr.where((c) => c != 'none').toList();
      final parts = <String>[];
      if (levels.isNotEmpty) {
        parts.add('e.cefr IN (${List.filled(levels.length, '?').join(',')})');
        args.addAll(levels);
      }
      if (f.cefr.contains('none')) parts.add('e.cefr IS NULL');
      w.add('(${parts.join(' OR ')})');
    }
    if (f.pos != null) {
      w.add('e.pos = ?');
      args.add(f.pos);
    }
    if (f.difficulty != null) {
      w.add('e.difficulty = ?');
      args.add(f.difficulty);
    }
    if (f.favoritesOnly) w.add('e.id IN (SELECT entry_id FROM favorites)');
    switch (f.status) {
      case LearnStatus.unseen:
        w.add('e.id NOT IN (SELECT entry_id FROM learning_cards)');
      case LearnStatus.learning:
        w.add('e.id IN (SELECT entry_id FROM learning_cards WHERE NOT (state = 2 AND stability >= 21))');
      case LearnStatus.mastered:
        w.add('e.id IN (SELECT entry_id FROM learning_cards WHERE state = 2 AND stability >= 21)');
      case LearnStatus.any:
        break;
    }
    return w.isEmpty ? '' : w.join(' AND ');
  }

  String _orderBy(SortMode s) {
    switch (s) {
      case SortMode.alphabetical:
        return 'e.headword_norm COLLATE NOCASE';
      case SortMode.level:
        return "COALESCE(e.cefr,'Z'), e.difficulty, e.freq_rank";
      case SortMode.frequency:
      case SortMode.relevance:
        return 'e.freq_rank';
    }
  }

  /// Search/browse with filters. English prefix matches rank first, then full-text matches on
  /// Vietnamese meanings / English definitions (diacritic-insensitive).
  Future<List<EntrySummary>> search(VocabFilter f, {int limit = 50, int offset = 0}) async {
    final q = f.query.trim().toLowerCase();
    if (q.isEmpty) {
      final args = <Object?>[];
      final where = _whereFilters(f, args);
      final rows = await db.rawQuery(
        'SELECT $_entryCols FROM c.vocabulary_entries e ${where.isEmpty ? '' : 'WHERE $where'} '
        'ORDER BY ${_orderBy(f.sort)} LIMIT ? OFFSET ?',
        [...args, limit, offset],
      );
      return rows.map(EntrySummary.fromRow).toList();
    }
    if (f.familySearch) return familyOf(q);

    final results = <int, EntrySummary>{};
    // 1) English headword prefix (uses idx_entries_headword via range scan)
    {
      final args = <Object?>[q, '$q￿'];
      final extra = _whereFilters(f, args);
      final rows = await db.rawQuery(
        'SELECT $_entryCols FROM c.vocabulary_entries e WHERE e.headword_norm >= ? AND e.headword_norm < ? '
        '${extra.isEmpty ? '' : 'AND $extra'} '
        'ORDER BY (e.headword_norm = ?) DESC, length(e.headword_norm), e.freq_rank LIMIT ?',
        [...args, q, offset == 0 ? limit : limit + offset],
      );
      for (final r in rows) {
        final s = EntrySummary.fromRow(r);
        results[s.id] = s;
      }
    }
    // 2) full-text: Vietnamese meaning (accent-insensitive), definitions, spelling variants
    if (results.length < limit + offset) {
      final fts = ftsPrefixQuery(q);
      if (fts.isNotEmpty) {
        final ids = await _ftsIds(fts, q, 300);
        if (ids.isNotEmpty) {
          final args = <Object?>[...ids];
          final extra = _whereFilters(f, args);
          final rows = await db.rawQuery(
            'SELECT $_entryCols, e.vi_norm FROM c.vocabulary_entries e WHERE e.id IN (${List.filled(ids.length, '?').join(',')}) '
            '${extra.isEmpty ? '' : 'AND $extra'} ORDER BY ${f.sort == SortMode.relevance ? 'e.freq_rank' : _orderBy(f.sort)}',
            args,
          );
          // Relevance: the phrase in the primary Vietnamese meaning > anywhere in the Vietnamese meanings > elsewhere.
          final phrase = stripVietnamese(q).trim();
          int rank(Map<String, Object?> r) {
            if (stripVietnamese(r['primary_vi'] as String).contains(phrase)) return 0;
            if ((r['vi_norm'] as String).contains(phrase)) return 1;
            return 2;
          }

          final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
          if (f.sort == SortMode.relevance) {
            indexed.sort((a, b) {
              final c = rank(a.$2).compareTo(rank(b.$2));
              return c != 0 ? c : a.$1.compareTo(b.$1); // stable: keep frequency order within a rank
            });
          }
          for (final (_, r) in indexed) {
            final s = EntrySummary.fromRow(r);
            results.putIfAbsent(s.id, () => s);
          }
        }
      }
    }
    var list = results.values.toList();
    if (f.sort == SortMode.alphabetical) {
      list.sort((a, b) => a.headword.toLowerCase().compareTo(b.headword.toLowerCase()));
    }
    if (offset >= list.length) return [];
    return list.sublist(offset, (offset + limit).clamp(0, list.length));
  }

  Future<List<int>> _ftsIds(String fts, String raw, int limit) async {
    if (_ftsAvailable != false) {
      try {
        final rows = await db.rawQuery('SELECT docid FROM c.search_index WHERE search_index MATCH ? LIMIT ?', [fts, limit]);
        _ftsAvailable = true;
        return rows.map((r) => r['docid'] as int).toList();
      } catch (_) {
        _ftsAvailable = false; // device SQLite without FTS4: fall back to LIKE scan
      }
    }
    final norm = stripVietnamese(raw);
    final rows = await db.rawQuery('SELECT id FROM c.vocabulary_entries WHERE vi_norm LIKE ? OR lower(primary_def) LIKE ? LIMIT ?', [
      '%$norm%',
      '%$norm%',
      limit,
    ]);
    return rows.map((r) => r['id'] as int).toList();
  }

  Future<List<String>> suggestions(String prefix, {int limit = 8}) async {
    final q = prefix.trim().toLowerCase();
    if (q.isEmpty) return [];
    final rows = await db.rawQuery(
      'SELECT DISTINCT headword FROM c.vocabulary_entries WHERE headword_norm >= ? AND headword_norm < ? '
      'ORDER BY length(headword_norm), freq_rank LIMIT ?',
      [q, '$q￿', limit],
    );
    return rows.map((r) => r['headword'] as String).toList();
  }

  /// Word family of a headword: the entries themselves plus "family" relations.
  Future<List<EntrySummary>> familyOf(String word) async {
    final rows = await db.rawQuery(
      '''
      SELECT $_entryCols FROM c.vocabulary_entries e
      WHERE e.headword_norm = ?
         OR e.id IN (SELECT r.target_entry_id FROM c.lexical_relations r
                     JOIN c.vocabulary_entries s ON s.id = r.entry_id
                     WHERE s.headword_norm = ? AND r.relation = 'family' AND r.target_entry_id IS NOT NULL)
      ORDER BY e.headword_norm <> ?, e.freq_rank LIMIT 60''',
      [word.toLowerCase(), word.toLowerCase(), word.toLowerCase()],
    );
    return rows.map(EntrySummary.fromRow).toList();
  }

  Future<List<String>> partsOfSpeech() async {
    final rows = await db.rawQuery('SELECT pos, pos_vi, COUNT(*) n FROM c.vocabulary_entries GROUP BY pos ORDER BY n DESC');
    return rows.map((r) => r['pos'] as String).toList();
  }

  // ------------------------------------------------------------------ details
  Future<EntrySummary?> summary(int id) async {
    final rows = await db.rawQuery('SELECT $_entryCols FROM c.vocabulary_entries e WHERE e.id = ?', [id]);
    return rows.isEmpty ? null : EntrySummary.fromRow(rows.first);
  }

  Future<List<EntrySummary>> summaries(List<int> ids) async {
    if (ids.isEmpty) return [];
    final rows = await db.rawQuery(
      'SELECT $_entryCols FROM c.vocabulary_entries e WHERE e.id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    );
    final byId = {for (final r in rows) r['id'] as int: EntrySummary.fromRow(r)};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<EntryDetail?> detail(int id) async {
    final rows = await db.rawQuery('SELECT e.* FROM c.vocabulary_entries e WHERE e.id = ?', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final srcRows = await db.rawQuery('SELECT id, code FROM c.source_provenance');
    final src = {for (final s in srcRows) s['id'] as int: s['code'] as String};
    final senses = await db.rawQuery(
      'SELECT id,sense_no,definition_en,labels,meaning_vi FROM c.vocabulary_senses WHERE entry_id=? ORDER BY sense_no',
      [id],
    );
    final trs = await db.rawQuery('SELECT meaning_vi,context_en,source_id FROM c.translations WHERE entry_id=? ORDER BY ord', [id]);
    final exs = await db.rawQuery(
      'SELECT text_en,text_vi,highlight,kind,source_id,source_ref FROM c.examples WHERE entry_id=? ORDER BY ord',
      [id],
    );
    final cols = await db.rawQuery('SELECT phrase,meaning_vi,source_id FROM c.collocations WHERE entry_id=? ORDER BY id', [id]);
    final rels = await db.rawQuery('SELECT relation,target_text,target_entry_id FROM c.lexical_relations WHERE entry_id=? ORDER BY id', [
      id,
    ]);
    final tps = await db.rawQuery(
      '''
      SELECT t.id,t.code,t.name_en,t.name_vi,t.category,t.icon FROM c.vocabulary_topics vt
      JOIN c.topics t ON t.id = vt.topic_id WHERE vt.entry_id=? ORDER BY t.sort_order''',
      [id],
    );
    return EntryDetail(
      summary: EntrySummary.fromRow(r),
      register: r['register'] as String?,
      skills: r['skills'] as String?,
      usageNote: r['usage_note'] as String?,
      commonMistake: r['common_mistake'] as String?,
      sources: r['sources'] as String,
      ipaUkSource: r['ipa_uk_source'] as String?,
      ipaUsSource: r['ipa_us_source'] as String?,
      primaryViSource: r['primary_vi_source'] as String,
      primaryDefSource: r['primary_def_source'] as String,
      senses: senses
          .map(
            (s) => Sense(
              id: s['id'] as int,
              number: s['sense_no'] as int,
              definition: s['definition_en'] as String,
              labels: s['labels'] as String?,
              meaningVi: s['meaning_vi'] as String?,
            ),
          )
          .toList(),
      translations: trs
          .map(
            (t) => Translation(
              meaningVi: t['meaning_vi'] as String,
              contextEn: t['context_en'] as String?,
              source: src[t['source_id']] ?? '?',
            ),
          )
          .toList(),
      examples: exs
          .map(
            (e) => Example(
              textEn: e['text_en'] as String,
              textVi: e['text_vi'] as String?,
              highlight: e['highlight'] as String?,
              kind: e['kind'] as String,
              source: src[e['source_id']] ?? '?',
              sourceRef: e['source_ref'] as String?,
            ),
          )
          .toList(),
      collocations: cols
          .map((c) => Collocation(phrase: c['phrase'] as String, meaningVi: c['meaning_vi'] as String?, source: src[c['source_id']] ?? '?'))
          .toList(),
      relations: rels
          .map((x) => Relation(relation: x['relation'] as String, text: x['target_text'] as String, targetId: x['target_entry_id'] as int?))
          .toList(),
      topics: tps
          .map(
            (t) => TopicInfo(
              id: t['id'] as int,
              code: t['code'] as String,
              nameEn: t['name_en'] as String,
              nameVi: t['name_vi'] as String,
              category: t['category'] as String,
              icon: t['icon'] as String?,
            ),
          )
          .toList(),
    );
  }

  Future<List<Example>> sentenceExamples(int entryId) async {
    final rows = await db.rawQuery(
      "SELECT text_en,text_vi,highlight,kind,source_id,source_ref FROM c.examples WHERE entry_id=? AND kind='sentence' AND highlight IS NOT NULL ORDER BY ord",
      [entryId],
    );
    return rows
        .map(
          (e) => Example(
            textEn: e['text_en'] as String,
            textVi: e['text_vi'] as String?,
            highlight: e['highlight'] as String?,
            kind: e['kind'] as String,
            source: '',
          ),
        )
        .toList();
  }

  // ------------------------------------------------------------------ quiz helpers
  /// Random entries for questions/distractors.
  Future<List<EntrySummary>> randomEntries(
    int count, {
    String? pos,
    int? topicId,
    Set<int> excludeIds = const {},
    int? minDifficulty,
    int? maxDifficulty,
    bool wordsOnly = false,
    bool learnedOnly = false,
  }) async {
    final w = <String>[];
    final args = <Object?>[];
    if (pos != null) {
      w.add('e.pos = ?');
      args.add(pos);
    }
    if (topicId != null) {
      w.add('e.id IN (SELECT entry_id FROM c.vocabulary_topics WHERE topic_id=?)');
      args.add(topicId);
    }
    if (minDifficulty != null) {
      w.add('e.difficulty >= ?');
      args.add(minDifficulty);
    }
    if (maxDifficulty != null) {
      w.add('e.difficulty <= ?');
      args.add(maxDifficulty);
    }
    if (wordsOnly) w.add("e.entry_type = 'word'");
    if (learnedOnly) w.add('e.id IN (SELECT entry_id FROM learning_cards)');
    if (excludeIds.isNotEmpty && excludeIds.length < 500) {
      w.add('e.id NOT IN (${List.filled(excludeIds.length, '?').join(',')})');
      args.addAll(excludeIds);
    }
    // ORDER BY random() on ~10k rows is fast enough (< 20 ms on phones).
    final rows = await db.rawQuery(
      'SELECT $_entryCols FROM c.vocabulary_entries e ${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'} ORDER BY random() LIMIT ?',
      [...args, count],
    );
    return rows.map(EntrySummary.fromRow).toList();
  }

  /// Entries that have a synonym/antonym target inside the lexicon.
  Future<List<Map<String, Object?>>> relationPairs(String relation, int count, {Set<int> fromIds = const {}}) async {
    final filter = fromIds.isEmpty ? '' : 'AND r.entry_id IN (${fromIds.join(',')})';
    return db.rawQuery(
      '''
      SELECT r.entry_id AS src, r.target_entry_id AS tgt FROM c.lexical_relations r
      JOIN c.vocabulary_entries t ON t.id = r.target_entry_id
      JOIN c.vocabulary_entries s ON s.id = r.entry_id
      WHERE r.relation = ? AND r.target_entry_id IS NOT NULL AND t.entry_type='word' AND s.entry_type='word'
        AND t.pos = s.pos $filter
      ORDER BY random() LIMIT ?''',
      [relation, count],
    );
  }

  Future<Set<int>> relatedIds(int entryId) async {
    final rows = await db.rawQuery(
      'SELECT target_entry_id FROM c.lexical_relations WHERE entry_id=? AND target_entry_id IS NOT NULL '
      'UNION SELECT entry_id FROM c.lexical_relations WHERE target_entry_id=?',
      [entryId, entryId],
    );
    return rows.map((r) => r['target_entry_id'] as int).toSet();
  }

  Future<Set<String>> relationTexts(int entryId, String relation) async {
    final rows = await db.rawQuery('SELECT lower(target_text) t FROM c.lexical_relations WHERE entry_id=? AND relation=?', [
      entryId,
      relation,
    ]);
    return rows.map((r) => r['t'] as String).toSet();
  }

  /// Collocation phrases (from the open sources / curated list) that contain the headword.
  Future<List<Map<String, Object?>>> collocationCandidates(int count, {Set<int> fromIds = const {}}) async {
    final filter = fromIds.isEmpty ? '' : 'AND e.id IN (${fromIds.join(',')})';
    return db.rawQuery(
      '''
      SELECT e.id AS entry_id, c.phrase, c.meaning_vi FROM c.collocations c
      JOIN c.vocabulary_entries e ON e.id = c.entry_id
      WHERE e.entry_type = 'word' AND c.meaning_vi IS NOT NULL AND length(c.phrase) BETWEEN 6 AND 40
        AND (' ' || lower(c.phrase) || ' ') LIKE ('% ' || e.headword_norm || ' %') $filter
      ORDER BY random() LIMIT ?''',
      [count],
    );
  }

  Future<bool> phraseExists(String phrase) async {
    final r = await db.rawQuery('SELECT 1 FROM c.collocations WHERE lower(phrase)=? LIMIT 1', [phrase.toLowerCase()]);
    return r.isNotEmpty;
  }

  /// Sentence examples (cloze-able) for given or random entries.
  Future<List<Map<String, Object?>>> clozeCandidates(int count, {Set<int> fromIds = const {}, bool withVi = false}) async {
    final filter = fromIds.isEmpty ? '' : 'AND x.entry_id IN (${fromIds.join(',')})';
    return db.rawQuery(
      '''
      SELECT x.entry_id, x.text_en, x.text_vi, x.highlight FROM c.examples x
      JOIN c.vocabulary_entries e ON e.id = x.entry_id
      WHERE x.kind='sentence' AND x.highlight IS NOT NULL AND length(x.text_en) < 140 ${withVi ? 'AND x.text_vi IS NOT NULL' : ''}
        AND e.entry_type IN ('word','phrasal_verb','collocation','expression','idiom') $filter
      ORDER BY random() LIMIT ?''',
      [count],
    );
  }

  // ------------------------------------------------------------------ practice content
  Future<List<WritingExercise>> writingExercises({String? category}) async {
    final rows = category == null
        ? await db.rawQuery('SELECT * FROM c.writing_exercises ORDER BY id')
        : await db.rawQuery('SELECT * FROM c.writing_exercises WHERE category=? ORDER BY id', [category]);
    return rows.map(WritingExercise.fromRow).toList();
  }

  Future<Map<String, int>> writingCategoryCounts() async {
    final rows = await db.rawQuery('SELECT category, COUNT(*) n FROM c.writing_exercises GROUP BY category');
    return {for (final r in rows) r['category'] as String: r['n'] as int};
  }

  Future<List<SpeakingPack>> speakingPacks() async {
    final rows = await db.rawQuery('SELECT * FROM c.speaking_packs ORDER BY part, id');
    return rows.map(SpeakingPack.fromRow).toList();
  }

  Future<SpeakingPack?> speakingPack(String code) async {
    final rows = await db.rawQuery('SELECT * FROM c.speaking_packs WHERE code=?', [code]);
    return rows.isEmpty ? null : SpeakingPack.fromRow(rows.first);
  }

  Future<List<String>> selfPracticePrompts() async {
    final rows = await db.rawQuery("SELECT value FROM c.meta WHERE key='self_practice'");
    if (rows.isEmpty) return [];
    return (jsonDecode(rows.first['value'] as String) as List).cast<String>();
  }

  Future<List<SourceInfo>> sources() async {
    final rows = await db.rawQuery('SELECT * FROM c.source_provenance ORDER BY id');
    return rows
        .map(
          (r) => SourceInfo(
            code: r['code'] as String,
            name: r['name'] as String,
            url: r['url'] as String,
            license: r['license'] as String,
            attribution: r['attribution'] as String,
          ),
        )
        .toList();
  }

  Future<Map<String, String>> contentMeta() async {
    final rows = await db.rawQuery('SELECT key, value FROM c.meta');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }
}
