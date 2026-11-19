import 'dart:convert';

/// Compact row used in lists, search results and quiz generation.
class EntrySummary {
  final int id;
  final String headword;
  final String pos;
  final String posVi;
  final String entryType;
  final String? cefr;
  final int difficulty;
  final String meaningVi;
  final String definition;
  final String? ipaUk;
  final String? ipaUs;
  final String? variants;

  const EntrySummary({
    required this.id,
    required this.headword,
    required this.pos,
    required this.posVi,
    required this.entryType,
    required this.cefr,
    required this.difficulty,
    required this.meaningVi,
    required this.definition,
    this.ipaUk,
    this.ipaUs,
    this.variants,
  });

  factory EntrySummary.fromRow(Map<String, Object?> r) => EntrySummary(
    id: r['id'] as int,
    headword: r['headword'] as String,
    pos: r['pos'] as String,
    posVi: r['pos_vi'] as String,
    entryType: r['entry_type'] as String,
    cefr: r['cefr'] as String?,
    difficulty: r['difficulty'] as int,
    meaningVi: r['primary_vi'] as String,
    definition: r['primary_def'] as String,
    ipaUk: r['ipa_uk'] as String?,
    ipaUs: r['ipa_us'] as String?,
    variants: r['variants'] as String?,
  );

  String? ipa(String accent) => accent == 'us' ? (ipaUs ?? ipaUk) : (ipaUk ?? ipaUs);

  /// All accepted spellings (lower case), e.g. "color / colour".
  List<String> get spellings {
    final out = <String>{headword.toLowerCase()};
    if (variants != null) {
      for (final v in variants!.split('/')) {
        final t = v.trim().toLowerCase();
        if (t.isNotEmpty) out.add(t);
      }
    }
    return out.toList();
  }

  String get levelLabel => cefr ?? 'Mức $difficulty';
}

class Sense {
  final int id;
  final int number;
  final String definition;
  final String? labels;
  final String? meaningVi;
  const Sense({required this.id, required this.number, required this.definition, this.labels, this.meaningVi});
}

class Translation {
  final String meaningVi;
  final String? contextEn;
  final String source;
  const Translation({required this.meaningVi, this.contextEn, required this.source});
}

class Example {
  final String textEn;
  final String? textVi;
  final String? highlight;
  final String kind;
  final String source;
  final String? sourceRef;
  const Example({required this.textEn, this.textVi, this.highlight, required this.kind, required this.source, this.sourceRef});

  bool get isSentence => kind == 'sentence';
}

class Collocation {
  final String phrase;
  final String? meaningVi;
  final String source;
  const Collocation({required this.phrase, this.meaningVi, required this.source});
}

class Relation {
  final String relation;
  final String text;
  final int? targetId;
  const Relation({required this.relation, required this.text, this.targetId});
}

class TopicInfo {
  final int id;
  final String code;
  final String nameEn;
  final String nameVi;
  final String category;
  final String? icon;
  final int wordCount;
  final int learnedCount;
  const TopicInfo({
    required this.id,
    required this.code,
    required this.nameEn,
    required this.nameVi,
    required this.category,
    this.icon,
    this.wordCount = 0,
    this.learnedCount = 0,
  });

  double get progress => wordCount == 0 ? 0 : learnedCount / wordCount;
}

class SourceInfo {
  final String code;
  final String name;
  final String url;
  final String license;
  final String attribution;
  const SourceInfo({required this.code, required this.name, required this.url, required this.license, required this.attribution});
}

class EntryDetail {
  final EntrySummary summary;
  final String? register;
  final String? skills;
  final String? usageNote;
  final String? commonMistake;
  final String sources;
  final String? ipaUkSource;
  final String? ipaUsSource;
  final String primaryViSource;
  final String primaryDefSource;
  final List<Sense> senses;
  final List<Translation> translations;
  final List<Example> examples;
  final List<Collocation> collocations;
  final List<Relation> relations;
  final List<TopicInfo> topics;

  const EntryDetail({
    required this.summary,
    this.register,
    this.skills,
    this.usageNote,
    this.commonMistake,
    required this.sources,
    this.ipaUkSource,
    this.ipaUsSource,
    required this.primaryViSource,
    required this.primaryDefSource,
    required this.senses,
    required this.translations,
    required this.examples,
    required this.collocations,
    required this.relations,
    required this.topics,
  });

  List<Relation> rel(String kind) => relations.where((r) => r.relation == kind).toList();
}

/// Learning state of one word (persisted in user DB).
class CardState {
  final int entryId;
  final int state; // 1 learning, 2 review, 3 relearning
  final int? step;
  final double? stability;
  final double? difficulty;
  final DateTime due;
  final DateTime? lastReview;
  final int reps;
  final int lapses;
  final int? lastRating;

  const CardState({
    required this.entryId,
    required this.state,
    this.step,
    this.stability,
    this.difficulty,
    required this.due,
    this.lastReview,
    this.reps = 0,
    this.lapses = 0,
    this.lastRating,
  });

  factory CardState.fromRow(Map<String, Object?> r) => CardState(
    entryId: r['entry_id'] as int,
    state: r['state'] as int,
    step: r['step'] as int?,
    stability: (r['stability'] as num?)?.toDouble(),
    difficulty: (r['difficulty'] as num?)?.toDouble(),
    due: DateTime.fromMillisecondsSinceEpoch(r['due'] as int, isUtc: true),
    lastReview: r['last_review'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['last_review'] as int, isUtc: true),
    reps: (r['reps'] as int?) ?? 0,
    lapses: (r['lapses'] as int?) ?? 0,
    lastRating: r['last_rating'] as int?,
  );

  bool get isMastered => state == 2 && (stability ?? 0) >= 21;
}

class WritingExercise {
  final int id;
  final String category;
  final String prompt;
  final List<String> options;
  final int answerIndex;
  final String explanationVi;
  const WritingExercise({
    required this.id,
    required this.category,
    required this.prompt,
    required this.options,
    required this.answerIndex,
    required this.explanationVi,
  });

  factory WritingExercise.fromRow(Map<String, Object?> r) => WritingExercise(
    id: r['id'] as int,
    category: r['category'] as String,
    prompt: r['prompt'] as String,
    options: (jsonDecode(r['options_json'] as String) as List).cast<String>(),
    answerIndex: r['answer_index'] as int,
    explanationVi: r['explanation_vi'] as String,
  );
}

class SpeakingVocab {
  final String text;
  final int? entryId;
  final String? meaningVi;
  const SpeakingVocab({required this.text, this.entryId, this.meaningVi});
}

class SpeakingPack {
  final int id;
  final String code;
  final int part;
  final String title;
  final String titleVi;
  final String? topicCode;
  final List<String> questions;
  final List<SpeakingVocab> vocab;
  final String? sampleAnswer;
  final String? tipsVi;

  const SpeakingPack({
    required this.id,
    required this.code,
    required this.part,
    required this.title,
    required this.titleVi,
    this.topicCode,
    required this.questions,
    required this.vocab,
    this.sampleAnswer,
    this.tipsVi,
  });

  factory SpeakingPack.fromRow(Map<String, Object?> r) => SpeakingPack(
    id: r['id'] as int,
    code: r['code'] as String,
    part: r['part'] as int,
    title: r['title'] as String,
    titleVi: r['title_vi'] as String,
    topicCode: r['topic_code'] as String?,
    questions: (jsonDecode(r['questions_json'] as String) as List).cast<String>(),
    vocab: (jsonDecode(r['vocab_json'] as String) as List)
        .map((e) => SpeakingVocab(text: e['text'] as String, entryId: e['entry_id'] as int?, meaningVi: e['vi'] as String?))
        .toList(),
    sampleAnswer: r['sample_answer'] as String?,
    tipsVi: r['tips_vi'] as String?,
  );
}

class DayActivity {
  final String day;
  final int newWords;
  final int reviews;
  final int correct;
  final int answers;
  const DayActivity({required this.day, this.newWords = 0, this.reviews = 0, this.correct = 0, this.answers = 0});
  int get total => newWords + reviews + answers;
}

class QuizSessionRecord {
  final int id;
  final String quizType;
  final DateTime startedAt;
  final int total;
  final int correct;
  const QuizSessionRecord({required this.id, required this.quizType, required this.startedAt, required this.total, required this.correct});
  double get accuracy => total == 0 ? 0 : correct / total;
}
