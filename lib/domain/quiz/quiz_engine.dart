import 'dart:math';

import '../../core/text/vietnamese.dart';
import '../../data/models/models.dart';
import '../../data/repositories/vocabulary_repository.dart';
import 'answer_checker.dart';

enum QuestionType {
  enToVi('Anh → Việt', 'Chọn nghĩa tiếng Việt đúng'),
  viToEn('Việt → Anh', 'Chọn từ tiếng Anh đúng'),
  fillBlank('Điền vào chỗ trống', 'Gõ từ còn thiếu trong câu'),
  spelling('Chính tả', 'Gõ đúng chính tả từ tiếng Anh'),
  definition('Ghép định nghĩa', 'Chọn từ khớp với định nghĩa'),
  synonym('Từ đồng nghĩa', 'Chọn từ đồng nghĩa'),
  antonym('Từ trái nghĩa', 'Chọn từ trái nghĩa'),
  collocation('Kết hợp từ', 'Hoàn thành cụm từ'),
  context('Ngữ cảnh IELTS', 'Chọn từ phù hợp ngữ cảnh');

  const QuestionType(this.labelVi, this.instructionVi);
  final String labelVi;
  final String instructionVi;

  bool get isTyped => this == QuestionType.fillBlank || this == QuestionType.spelling;
}

class QuizQuestion {
  final QuestionType type;
  final int? entryId;
  final String prompt;
  final String? subPrompt;
  final List<String> options;
  final int answerIndex;
  final List<String> accepted;
  final String correctAnswer;
  final String explanation;
  final String? exampleVi;

  const QuizQuestion({
    required this.type,
    required this.entryId,
    required this.prompt,
    this.subPrompt,
    this.options = const [],
    this.answerIndex = -1,
    this.accepted = const [],
    required this.correctAnswer,
    required this.explanation,
    this.exampleVi,
  });

  bool get isTyped => type.isTyped;
}

class QuizConfig {
  final Set<QuestionType> types;
  final int count;
  final int? topicId;
  final bool preferLearned;
  const QuizConfig({required this.types, required this.count, this.topicId, this.preferLearned = true});
}

/// Generates quiz questions from the offline database with deterministic answer keys.
/// Distractors are filtered so that only one option can be correct: they must differ in
/// headword and Vietnamese meaning, and must not be a synonym/antonym/collocate of the target.
class QuizEngine {
  final VocabularyRepository repo;
  final Random rng;
  QuizEngine(this.repo, {Random? rng}) : rng = rng ?? Random();

  static String explain(EntrySummary e) => '${e.headword} (${e.posVi}) – ${e.meaningVi}\n${e.definition}';

  Future<List<QuizQuestion>> build(QuizConfig cfg, {List<int> learnedIds = const []}) async {
    final types = cfg.types.isEmpty ? QuestionType.values.toSet() : cfg.types;
    final out = <QuizQuestion>[];
    final usedEntries = <int>{};
    final learned = learnedIds.toSet();
    var guard = 0;
    while (out.length < cfg.count && guard < cfg.count * 6) {
      guard++;
      final type = types.elementAt(rng.nextInt(types.length));
      final fromLearned = cfg.preferLearned && learned.length >= 8 && rng.nextDouble() < 0.75;
      final pool = fromLearned ? (learned.difference(usedEntries).toList()..shuffle(rng)).take(40).toSet() : <int>{};
      QuizQuestion? q;
      try {
        q = await _make(type, cfg.topicId, pool, usedEntries);
      } catch (_) {
        q = null;
      }
      q ??= await _make(QuestionType.enToVi, cfg.topicId, pool, usedEntries);
      if (q != null && (q.entryId == null || !usedEntries.contains(q.entryId))) {
        if (q.entryId != null) usedEntries.add(q.entryId!);
        out.add(q);
      }
    }
    return out;
  }

  Future<EntrySummary?> _target(int? topicId, Set<int> pool, Set<int> used, {bool wordsOnly = false}) async {
    if (pool.isNotEmpty) {
      final list = await repo.summaries(pool.toList());
      final ok = list.where((e) => !used.contains(e.id) && (!wordsOnly || e.entryType == 'word')).toList();
      if (ok.isNotEmpty) return ok[rng.nextInt(ok.length)];
    }
    final r = await repo.randomEntries(1, topicId: topicId, excludeIds: used, wordsOnly: wordsOnly);
    return r.isEmpty ? null : r.first;
  }

  static Set<String> _meaningParts(String vi) =>
      stripVietnamese(vi).split(RegExp(r'[,;/()]')).map((s) => s.trim()).where((s) => s.length > 1).toSet();

  /// Distractor entries of the same POS that cannot be confused with [target].
  Future<List<EntrySummary>> _distractors(EntrySummary target, int n, {Set<String> forbiddenTexts = const {}}) async {
    final related = await repo.relatedIds(target.id);
    final targetParts = _meaningParts(target.meaningVi);
    final cands = await repo.randomEntries(
      n * 5,
      pos: target.pos,
      excludeIds: {target.id, ...related},
      minDifficulty: max(1, target.difficulty - 1),
      maxDifficulty: min(5, target.difficulty + 1),
    );
    final out = <EntrySummary>[];
    final seenHead = {target.headword.toLowerCase()};
    final seenMeaning = {stripVietnamese(target.meaningVi)};
    for (final c in cands) {
      final h = c.headword.toLowerCase();
      if (seenHead.contains(h) || forbiddenTexts.contains(h)) continue;
      final m = stripVietnamese(c.meaningVi);
      if (seenMeaning.contains(m)) continue;
      if (_meaningParts(c.meaningVi).intersection(targetParts).isNotEmpty) continue;
      if (c.definition.toLowerCase() == target.definition.toLowerCase()) continue;
      seenHead.add(h);
      seenMeaning.add(m);
      out.add(c);
      if (out.length == n) break;
    }
    if (out.length < n) {
      // widen the search (any POS) if the same-POS pool was too small
      final more = await repo.randomEntries(n * 6, excludeIds: {target.id, ...related, ...out.map((e) => e.id)});
      for (final c in more) {
        final h = c.headword.toLowerCase();
        final m = stripVietnamese(c.meaningVi);
        if (seenHead.contains(h) || seenMeaning.contains(m) || forbiddenTexts.contains(h)) continue;
        if (_meaningParts(c.meaningVi).intersection(targetParts).isNotEmpty) continue;
        seenHead.add(h);
        seenMeaning.add(m);
        out.add(c);
        if (out.length == n) break;
      }
    }
    return out;
  }

  QuizQuestion _mc({
    required QuestionType type,
    required EntrySummary target,
    required String prompt,
    String? sub,
    required String correct,
    required List<String> wrong,
    String? exampleVi,
  }) {
    final opts = [correct, ...wrong]..shuffle(rng);
    return QuizQuestion(
      type: type,
      entryId: target.id,
      prompt: prompt,
      subPrompt: sub,
      options: opts,
      answerIndex: opts.indexOf(correct),
      correctAnswer: correct,
      explanation: explain(target),
      exampleVi: exampleVi,
    );
  }

  Future<QuizQuestion?> _make(QuestionType type, int? topicId, Set<int> pool, Set<int> used) async {
    switch (type) {
      case QuestionType.enToVi:
        final t = await _target(topicId, pool, used);
        if (t == null) return null;
        final d = await _distractors(t, 3);
        if (d.length < 3) return null;
        return _mc(
          type: type,
          target: t,
          prompt: t.headword,
          sub: t.posVi,
          correct: t.meaningVi,
          wrong: d.map((e) => e.meaningVi).toList(),
        );
      case QuestionType.viToEn:
        final t = await _target(topicId, pool, used);
        if (t == null) return null;
        final d = await _distractors(t, 3);
        if (d.length < 3) return null;
        return _mc(type: type, target: t, prompt: t.meaningVi, sub: t.posVi, correct: t.headword, wrong: d.map((e) => e.headword).toList());
      case QuestionType.definition:
        final t = await _target(topicId, pool, used);
        if (t == null) return null;
        final d = await _distractors(t, 3);
        if (d.length < 3) return null;
        return _mc(
          type: type,
          target: t,
          prompt: t.definition,
          sub: t.posVi,
          correct: t.headword,
          wrong: d.map((e) => e.headword).toList(),
        );
      case QuestionType.spelling:
        final t = await _target(topicId, pool, used, wordsOnly: true);
        if (t == null) return null;
        return QuizQuestion(
          type: type,
          entryId: t.id,
          prompt: t.meaningVi,
          subPrompt: '${t.posVi} • ${t.definition}',
          accepted: t.spellings,
          correctAnswer: t.headword,
          explanation: explain(t),
        );
      case QuestionType.fillBlank:
      case QuestionType.context:
        final rows = await repo.clozeCandidates(1, fromIds: pool.difference(used));
        final row = rows.isNotEmpty ? rows.first : (await repo.clozeCandidates(1)).firstOrNull;
        if (row == null) return null;
        final id = row['entry_id'] as int;
        if (used.contains(id)) return null;
        final t = await repo.summary(id);
        if (t == null) return null;
        final form = row['highlight'] as String;
        final blanked = blankOut(row['text_en'] as String, form);
        if (blanked == null) return null;
        if (type == QuestionType.fillBlank) {
          return QuizQuestion(
            type: type,
            entryId: id,
            prompt: blanked,
            subPrompt: 'Gợi ý: ${t.meaningVi} (${form.length} ký tự, bắt đầu bằng "${form[0]}")',
            accepted: {form, if (form.toLowerCase() == t.headword.toLowerCase()) ...t.spellings}.toList(),
            correctAnswer: form,
            explanation: explain(t),
            exampleVi: row['text_vi'] as String?,
          );
        }
        final d = await _distractors(t, 3);
        if (d.length < 3) return null;
        return _mc(
          type: type,
          target: t,
          prompt: blanked,
          sub: 'Chọn từ phù hợp nhất (đáp án ở dạng từ gốc)',
          correct: t.headword,
          wrong: d.map((e) => e.headword).toList(),
          exampleVi: row['text_vi'] as String?,
        );
      case QuestionType.synonym:
      case QuestionType.antonym:
        final rel = type == QuestionType.synonym ? 'synonym' : 'antonym';
        var pairs = await repo.relationPairs(rel, 1, fromIds: pool.difference(used));
        if (pairs.isEmpty) pairs = await repo.relationPairs(rel, 1);
        if (pairs.isEmpty) return null;
        final src = await repo.summary(pairs.first['src'] as int);
        final tgt = await repo.summary(pairs.first['tgt'] as int);
        if (src == null || tgt == null || used.contains(src.id)) return null;
        final forbidden = {
          ...await repo.relationTexts(src.id, 'synonym'),
          ...await repo.relationTexts(src.id, 'antonym'),
          src.headword.toLowerCase(),
        };
        final d = await _distractors(tgt, 3, forbiddenTexts: forbidden);
        if (d.length < 3) return null;
        return QuizQuestion(
          type: type,
          entryId: src.id,
          prompt: src.headword,
          subPrompt:
              '${type == QuestionType.synonym ? 'Từ nào ĐỒNG NGHĨA với' : 'Từ nào TRÁI NGHĨA với'} "${src.headword}" (${src.meaningVi})?',
          options: ([tgt.headword, ...d.map((e) => e.headword)]..shuffle(rng)),
          answerIndex: -1,
          correctAnswer: tgt.headword,
          explanation:
              '${src.headword} – ${src.meaningVi}\n${rel == 'synonym' ? 'Đồng nghĩa' : 'Trái nghĩa'}: ${tgt.headword} – ${tgt.meaningVi}',
        )._withAnswerIndex();
      case QuestionType.collocation:
        var rows = await repo.collocationCandidates(1, fromIds: pool.difference(used));
        if (rows.isEmpty) rows = await repo.collocationCandidates(1);
        if (rows.isEmpty) return null;
        final t = await repo.summary(rows.first['entry_id'] as int);
        if (t == null || used.contains(t.id)) return null;
        final phrase = rows.first['phrase'] as String;
        final blanked = blankOut(phrase, t.headword);
        if (blanked == null) return null;
        final cands = await _distractors(t, 6);
        final wrong = <String>[];
        for (final c in cands) {
          final alt = blanked.replaceFirst('_____', c.headword);
          if (await repo.phraseExists(alt)) continue; // the alternative is itself a real collocation
          wrong.add(c.headword);
          if (wrong.length == 3) break;
        }
        if (wrong.length < 3) return null;
        return _mc(type: type, target: t, prompt: blanked, sub: 'Nghĩa: ${rows.first['meaning_vi']}', correct: t.headword, wrong: wrong);
    }
  }
}

extension on QuizQuestion {
  QuizQuestion _withAnswerIndex() => QuizQuestion(
    type: type,
    entryId: entryId,
    prompt: prompt,
    subPrompt: subPrompt,
    options: options,
    answerIndex: options.indexOf(correctAnswer),
    accepted: accepted,
    correctAnswer: correctAnswer,
    explanation: explanation,
    exampleVi: exampleVi,
  );
}
