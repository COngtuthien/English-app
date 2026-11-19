import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/achievement_repository.dart';
import '../../data/repositories/learning_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/quiz/answer_checker.dart';
import '../../domain/srs/srs_scheduler.dart';
import '../../providers.dart';
import 'flashcard_session.dart';

enum SessionKind { learnNew, review, random, topic, difficult, favorites }

extension on SessionKind {
  String get title => switch (this) {
    SessionKind.learnNew => 'Học từ mới',
    SessionKind.review => 'Ôn tập',
    SessionKind.random => 'Flashcard ngẫu nhiên',
    SessionKind.topic => 'Flashcard theo chủ đề',
    SessionKind.difficult => 'Ôn từ khó',
    SessionKind.favorites => 'Ôn từ yêu thích',
  };
  String get mode => switch (this) {
    SessionKind.learnNew => 'learn',
    SessionKind.review => 'review',
    _ => 'practice',
  };
}

class FlashcardSessionScreen extends ConsumerStatefulWidget {
  final SessionKind kind;
  final int? topicId;
  const FlashcardSessionScreen({super.key, required this.kind, this.topicId});
  @override
  ConsumerState<FlashcardSessionScreen> createState() => _FlashcardSessionScreenState();
}

class _FlashcardSessionScreenState extends ConsumerState<FlashcardSessionScreen> {
  FlashcardSession _session = FlashcardSession(const []);
  final Map<int, EntryDetail> _details = {};
  bool _loading = true;
  Object? _error;
  late FlashMode _mode;
  DateTime _shownAt = DateTime.now();

  /// Interval preview for the card at [_previewPos] (labels the grade buttons and decides
  /// whether the card returns later in this session).
  Map<Grade, Duration> _preview = {};
  int _previewPos = -1;
  Future<void>? _preparing;

  /// Reviews are written to the database in order, in the background, so the UI never waits on
  /// I/O before showing the next card.
  Future<void> _saveChain = Future.value();
  int _pendingSaves = 0;
  int _saveErrors = 0;
  bool _extraOffered = false;

  late final LearningRepository _learning;
  late final AchievementRepository _achievements;
  late final StateController<int> _dataVersion;

  @override
  void initState() {
    super.initState();
    _mode = ref.read(settingsProvider).flashMode;
    _learning = ref.read(learningRepoProvider);
    _achievements = ref.read(achievementRepoProvider);
    _dataVersion = ref.read(dataVersionProvider.notifier);
    _load();
  }

  Future<List<EntrySummary>> _fetch({int extra = 0}) async {
    final s = ref.read(settingsProvider);
    final vocab = ref.read(vocabRepoProvider);
    switch (widget.kind) {
      case SessionKind.learnNew:
        final remaining = extra > 0 ? extra : s.dailyNewWords - await _learning.newWordsToday();
        if (remaining <= 0) return [];
        return _learning.nextNewWords(remaining, s, topicId: widget.topicId);
      case SessionKind.review:
        return _learning.dueEntries(limit: s.dailyReviewLimit);
      case SessionKind.random:
        final learned = await _learning.learnedIds();
        return learned.length >= 20 ? (await vocab.summaries((learned..shuffle()).take(20).toList())) : vocab.randomEntries(20);
      case SessionKind.topic:
        return vocab.randomEntries(20, topicId: widget.topicId);
      case SessionKind.difficult:
        return (await _learning.difficultWords())..shuffle();
      case SessionKind.favorites:
        return ((await _learning.favorites())..shuffle()).take(40).toList();
    }
  }

  Future<void> _load({int extra = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _saveChain; // a previous session's reviews must be stored before new words are picked
      final items = await _fetch(extra: extra);
      _session = FlashcardSession(items);
      _previewPos = -1;
      if (!_session.isEmpty) await _prepareCurrent();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Loads details + the FSRS interval preview for the current position. Waits for pending saves
  /// first, because a card that comes back in the session must be previewed from its saved state.
  Future<void> _prepareCurrent() {
    final pos = _session.position;
    final item = _session.current;
    if (item == null) return Future.value();
    final f = () async {
      await _saveChain;
      final e = item.entry;
      if (!_details.containsKey(e.id)) {
        final d = await ref.read(vocabRepoProvider).detail(e.id);
        if (d != null) _details[e.id] = d;
      }
      final card = await _learning.card(e.id);
      if (!mounted || _session.position != pos) return;
      setState(() {
        _preview = ref.read(schedulerProvider).preview(e.id, card, DateTime.now().toUtc());
        _previewPos = pos;
      });
      final n = _session.next?.entry.id;
      if (n != null && !_details.containsKey(n)) {
        unawaited(
          ref.read(vocabRepoProvider).detail(n).then((d) {
            if (d != null) _details[n] = d;
          }),
        );
      }
      final s = ref.read(settingsProvider);
      if (s.autoPlayAudio && _effectiveMode() == FlashMode.enToVi) {
        unawaited(ref.read(ttsProvider).speak(e.headword, accent: s.accent, rate: s.speechRate));
      }
    }();
    _shownAt = DateTime.now();
    _preparing = f;
    return f;
  }

  FlashMode _effectiveMode() {
    final cur = _session.current;
    if (cur == null) return _mode;
    if (_mode == FlashMode.cloze && _clozeFor(cur.entry) == null) return FlashMode.enToVi;
    return _mode;
  }

  Example? _clozeExample(EntrySummary e) {
    final d = _details[e.id];
    if (d == null) return null;
    for (final x in d.examples) {
      if (x.isSentence && x.highlight != null && blankOut(x.textEn, x.highlight!) != null) return x;
    }
    return null;
  }

  String? _clozeFor(EntrySummary e) {
    final x = _clozeExample(e);
    return x == null ? null : blankOut(x.textEn, x.highlight!);
  }

  void _toggleFlip() => setState(_session.toggleFlip);

  /// Grades the card shown at [atPosition]: advances synchronously (next card, face-down), then
  /// stores the review in the background. Duplicate taps for the same position are ignored.
  Future<void> _rate(Grade g, int atPosition) async {
    if (_previewPos != atPosition && _preparing != null) {
      await _preparing; // the preview decides whether the card comes back in this session
    }
    if (!mounted) return;
    final interval = _previewPos == atPosition ? _preview[g] : null;
    final durationMs = DateTime.now().difference(_shownAt).inMilliseconds.clamp(0, 600000);
    final result = _session.grade(g, atPosition: atPosition, nextInterval: interval ?? const Duration(days: 1));
    if (result == null) return; // duplicate / not revealed / finished
    setState(() {
      _preview = {};
      _previewPos = -1;
    });
    _persist(result, durationMs);
    if (!_session.isFinished) unawaited(_prepareCurrent());
  }

  void _persist(GradeResult r, int durationMs) {
    _pendingSaves++;
    _saveChain = _saveChain.then((_) async {
      try {
        await _learning.review(r.item.entry.id, r.grade, mode: widget.kind.mode, durationMs: durationMs);
        final fresh = await _achievements.evaluate();
        _dataVersion.state++;
        if (mounted && fresh.isNotEmpty) {
          for (final a in fresh) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.emoji_events, color: Colors.amber),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Thành tích mới: ${a.title}')),
                  ],
                ),
              ),
            );
          }
        }
      } catch (e) {
        _saveErrors++;
        if (mounted) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text('Không lưu được kết quả của "${r.item.entry.headword}": $e')));
        }
      } finally {
        _pendingSaves--;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kind.title),
        actions: [
          PopupMenuButton<FlashMode>(
            tooltip: 'Kiểu thẻ',
            icon: const Icon(Icons.style_rounded),
            initialValue: _mode,
            onSelected: (m) => setState(() => _mode = m),
            itemBuilder: (_) => const [
              PopupMenuItem(value: FlashMode.enToVi, child: Text('Anh → Việt')),
              PopupMenuItem(value: FlashMode.viToEn, child: Text('Việt → Anh')),
              PopupMenuItem(value: FlashMode.defToWord, child: Text('Định nghĩa → Từ')),
              PopupMenuItem(value: FlashMode.cloze, child: Text('Điền từ vào câu')),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const LoadingView(message: 'Đang chuẩn bị thẻ…');
    if (_error != null) return ErrorView(_error!, onRetry: _load);
    if (_session.isEmpty) return _emptyState(context);
    if (_session.isFinished) return _summary(context);
    final item = _session.current!;
    final pos = _session.position;
    final revealed = _session.revealed;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(child: RoundedProgress(value: _session.progress, height: 8)),
              const SizedBox(width: 12),
              Text(
                _session.counterLabel,
                key: const ValueKey('flash-counter'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        if (item.appearance > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Pill('Ôn lại lần ${item.appearance + 1} • bước học ngắn', icon: Icons.replay_rounded, color: AppColors.amber),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              // The outgoing card is still painted while it fades out, but it must not receive taps.
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.center,
                children: [
                  for (final p in previous) IgnorePointer(child: p),
                  ?current,
                ],
              ),
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween(
                  begin: const Offset(0.25, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: KeyedSubtree(
                key: ValueKey('card-$pos-${item.entry.id}'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleFlip,
                  child: FlipCard(flipped: revealed, front: _front(context, item.entry), back: _back(context, item.entry)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: revealed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Chọn mức độ ghi nhớ để chuyển sang từ tiếp theo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                    Row(
                      children: [
                        for (final g in Grade.values) ...[
                          if (g != Grade.again) const SizedBox(width: 8),
                          Expanded(child: _gradeButton(g, pos)),
                        ],
                      ],
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => setState(_session.reveal),
                    icon: const Icon(Icons.flip_rounded),
                    label: const Text('Hiện đáp án'),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _gradeButton(Grade g, int pos) {
    final color = switch (g) {
      Grade.again => AppColors.danger,
      Grade.hard => AppColors.amber,
      Grade.good => AppColors.indigo,
      Grade.easy => AppColors.success,
    };
    final interval = _previewPos == pos ? _preview[g] : null;
    return FilledButton(
      key: ValueKey('grade-${g.name}'),
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.14),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        minimumSize: const Size(0, 58),
      ),
      onPressed: () => _rate(g, pos),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(g.labelVi, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(interval == null ? '…' : formatInterval(interval), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _front(BuildContext context, EntrySummary e) {
    final mode = _effectiveMode();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    Widget content;
    switch (mode) {
      case FlashMode.enToVi:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(e.headword, textAlign: TextAlign.center, style: tt.headlineMedium?.copyWith(fontSize: 34)),
            const SizedBox(height: 8),
            if (e.ipa(accent) != null) Text(e.ipa(accent)!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
            Text(
              e.posVi,
              style: TextStyle(color: cs.secondary, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [SpeakButton(e.headword), SpeakButton(e.headword, slow: true)]),
          ],
        );
      case FlashMode.viToEn:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(e.meaningVi, textAlign: TextAlign.center, style: tt.headlineSmall),
            const SizedBox(height: 8),
            Text(
              e.posVi,
              style: TextStyle(color: cs.secondary, fontStyle: FontStyle.italic),
            ),
          ],
        );
      case FlashMode.defToWord:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Định nghĩa',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              e.definition,
              textAlign: TextAlign.center,
              style: tt.titleLarge?.copyWith(height: 1.4, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              e.posVi,
              style: TextStyle(color: cs.secondary, fontStyle: FontStyle.italic),
            ),
          ],
        );
      case FlashMode.cloze:
        final ex = _clozeExample(e)!;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Điền từ còn thiếu',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              blankOut(ex.textEn, ex.highlight!)!,
              textAlign: TextAlign.center,
              style: tt.titleLarge?.copyWith(height: 1.45, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Text(
              'Gợi ý: ${e.meaningVi}',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        );
    }
    return _CardFace(
      child: Column(
        children: [
          Row(
            children: [
              LevelBadge(cefr: e.cefr, difficulty: e.difficulty),
              const Spacer(),
              Text('Chạm để lật thẻ', style: TextStyle(color: cs.outline, fontSize: 12)),
            ],
          ),
          Expanded(
            child: Center(child: SingleChildScrollView(child: content)),
          ),
        ],
      ),
    );
  }

  Widget _back(BuildContext context, EntrySummary e) {
    final d = _details[e.id];
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    final ex = d?.examples.where((x) => x.isSentence).firstOrNull;
    return _CardFace(
      highlight: true,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(e.headword, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                SpeakButton(e.headword),
              ],
            ),
            Text('${e.posVi}${e.ipa(accent) != null ? '  •  ${e.ipa(accent)}' : ''}', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 14),
            Text(e.meaningVi, style: tt.titleLarge?.copyWith(color: cs.primary, height: 1.3)),
            const SizedBox(height: 8),
            Text(e.definition, style: const TextStyle(height: 1.4)),
            if (ex != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HighlightText(ex.textEn, highlight: ex.highlight, style: const TextStyle(height: 1.4, fontSize: 15)),
                    if (ex.textVi != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        ex.textVi!,
                        style: TextStyle(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (d != null && d.collocations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final c in d.collocations.take(3)) Pill(c.phrase, color: AppColors.teal)]),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.push('/word/${e.id}'),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Xem chi tiết'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    switch (widget.kind) {
      case SessionKind.review:
        return EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'Không có từ nào cần ôn',
          message: 'Tuyệt vời! Bạn đã ôn hết các từ đến hạn. Hãy học thêm từ mới.',
          actionLabel: 'Học từ mới',
          onAction: () => context.pushReplacement('/learn'),
        );
      case SessionKind.learnNew:
        return EmptyState(
          icon: Icons.celebration_rounded,
          title: 'Đã đạt mục tiêu hôm nay',
          message: 'Bạn đã học đủ số từ mới đặt ra cho hôm nay. Muốn học thêm 10 từ?',
          actionLabel: 'Học thêm 10 từ',
          onAction: () => _load(extra: 10),
        );
      case SessionKind.difficult:
        return const EmptyState(
          icon: Icons.sentiment_satisfied_alt_rounded,
          title: 'Chưa có từ khó',
          message: 'Những từ bạn hay quên hoặc làm sai sẽ xuất hiện ở đây.',
        );
      case SessionKind.favorites:
        return const EmptyState(
          icon: Icons.favorite_border_rounded,
          title: 'Chưa có từ yêu thích',
          message: 'Nhấn biểu tượng trái tim ở trang chi tiết từ để lưu.',
        );
      default:
        return const EmptyState(icon: Icons.inbox_rounded, title: 'Không có thẻ', message: 'Không tìm thấy từ phù hợp.');
    }
  }

  Widget _summary(BuildContext context) {
    final s = _session;
    final reviewed = s.totalGraded;
    final good = reviewed - s.tally[Grade.again]!;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 110,
            height: 110,
            decoration: const BoxDecoration(gradient: AppColors.heroGradient, shape: BoxShape.circle),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 56),
          ),
        ),
        const SizedBox(height: 20),
        Text('Hoàn thành phiên học!', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          widget.kind == SessionKind.learnNew
              ? 'Bạn vừa học ${s.gradedEntries.length} từ mới với $reviewed lượt chấm.'
              : 'Bạn đã ôn ${s.gradedEntries.length} từ ($reviewed lượt), nhớ được $good lượt.',
          textAlign: TextAlign.center,
        ),
        if (s.pendingLearningSteps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${s.pendingLearningSteps.length} từ sẽ xuất hiện lại trong phần Ôn tập sau ít phút.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 12),
        Center(
          child: _pendingSaves > 0
              ? const Pill('Đang lưu kết quả…', icon: Icons.sync_rounded)
              : _saveErrors > 0
              ? Pill('$_saveErrors kết quả chưa lưu được', icon: Icons.error_outline_rounded, color: AppColors.danger)
              : const Pill('Đã lưu tiến độ', icon: Icons.check_circle_rounded, color: AppColors.success),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            for (final g in Grade.values)
              Expanded(
                child: Column(
                  children: [
                    Text('${s.tally[g]}', style: Theme.of(context).textTheme.headlineSmall),
                    Text(g.labelVi),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 32),
        FilledButton(onPressed: () => context.pop(), child: const Text('Về trang trước')),
        const SizedBox(height: 10),
        if (widget.kind == SessionKind.learnNew && !_extraOffered)
          OutlinedButton(
            onPressed: () {
              _extraOffered = true;
              _load(extra: 10);
            },
            child: const Text('Học thêm 10 từ'),
          ),
        if (widget.kind != SessionKind.review) ...[
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => context.pushReplacement('/review'), child: const Text('Ôn các từ đến hạn')),
        ],
      ],
    );
  }
}

class _CardFace extends StatelessWidget {
  final Widget child;
  final bool highlight;
  const _CardFace({required this.child, this.highlight = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: highlight ? cs.primary.withValues(alpha: 0.35) : cs.outlineVariant.withValues(alpha: 0.6),
          width: highlight ? 1.5 : 1,
        ),
        boxShadow: softShadow(context, opacity: 0.12),
      ),
      child: child,
    );
  }
}

/// 3D flip between [front] and [back].
class FlipCard extends StatelessWidget {
  final bool flipped;
  final Widget front;
  final Widget back;
  const FlipCard({super.key, required this.flipped, required this.front, required this.back});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: flipped ? 1 : 0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
      builder: (context, v, _) {
        final angle = v * math.pi;
        final showBack = v > 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: showBack ? Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(math.pi), child: back) : front,
        );
      },
    );
  }
}
