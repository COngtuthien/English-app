import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/quiz/answer_checker.dart';
import '../../domain/srs/srs_scheduler.dart';
import '../../providers.dart';

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

class _QueueItem {
  final EntrySummary entry;
  int requeues = 0;
  _QueueItem(this.entry);
}

class _FlashcardSessionScreenState extends ConsumerState<FlashcardSessionScreen> {
  final List<_QueueItem> _queue = [];
  final Map<int, EntryDetail> _details = {};
  int _pos = 0;
  int _initialCount = 0;
  bool _flipped = false;
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  late FlashMode _mode;
  DateTime _shownAt = DateTime.now();
  Map<Grade, Duration> _preview = {};
  final Map<Grade, int> _tally = {for (final g in Grade.values) g: 0};
  final Set<int> _learnedNew = {};
  bool _extraOffered = false;

  @override
  void initState() {
    super.initState();
    _mode = ref.read(settingsProvider).flashMode;
    _load();
  }

  Future<List<EntrySummary>> _fetch({int extra = 0}) async {
    final s = ref.read(settingsProvider);
    final learn = ref.read(learningRepoProvider);
    final vocab = ref.read(vocabRepoProvider);
    switch (widget.kind) {
      case SessionKind.learnNew:
        final remaining = extra > 0 ? extra : s.dailyNewWords - await learn.newWordsToday();
        if (remaining <= 0) return [];
        return learn.nextNewWords(remaining, s, topicId: widget.topicId);
      case SessionKind.review:
        return learn.dueEntries(limit: s.dailyReviewLimit);
      case SessionKind.random:
        final learned = await learn.learnedIds();
        return learned.length >= 20 ? (await vocab.summaries((learned..shuffle()).take(20).toList())) : vocab.randomEntries(20);
      case SessionKind.topic:
        return vocab.randomEntries(20, topicId: widget.topicId);
      case SessionKind.difficult:
        return (await learn.difficultWords())..shuffle();
      case SessionKind.favorites:
        return ((await learn.favorites())..shuffle()).take(40).toList();
    }
  }

  Future<void> _load({int extra = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _fetch(extra: extra);
      _queue
        ..clear()
        ..addAll(items.map(_QueueItem.new));
      _pos = 0;
      _initialCount = _queue.length;
      _flipped = false;
      if (_queue.isNotEmpty) await _prepareCurrent();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _prepareCurrent() async {
    final e = _queue[_pos].entry;
    if (!_details.containsKey(e.id)) {
      final d = await ref.read(vocabRepoProvider).detail(e.id);
      if (d != null) _details[e.id] = d;
    }
    final card = await ref.read(learningRepoProvider).card(e.id);
    _preview = ref.read(schedulerProvider).preview(e.id, card, DateTime.now().toUtc());
    _shownAt = DateTime.now();
    // prefetch next
    if (_pos + 1 < _queue.length) {
      final n = _queue[_pos + 1].entry.id;
      if (!_details.containsKey(n)) {
        ref.read(vocabRepoProvider).detail(n).then((d) {
          if (d != null) _details[n] = d;
        });
      }
    }
    final s = ref.read(settingsProvider);
    if (s.autoPlayAudio && (_effectiveMode() == FlashMode.enToVi)) {
      ref.read(ttsProvider).speak(e.headword, accent: s.accent, rate: s.speechRate);
    }
  }

  FlashMode _effectiveMode() {
    if (_mode == FlashMode.cloze && _clozeFor(_queue[_pos].entry) == null) return FlashMode.enToVi;
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

  Future<void> _rate(Grade g) async {
    if (_busy) return;
    setState(() => _busy = true);
    final item = _queue[_pos];
    try {
      final outcome = await ref
          .read(learningRepoProvider)
          .review(
            item.entry.id,
            g,
            mode: widget.kind.mode,
            durationMs: DateTime.now().difference(_shownAt).inMilliseconds.clamp(0, 600000),
          );
      _tally[g] = _tally[g]! + 1;
      if (widget.kind == SessionKind.learnNew) _learnedNew.add(item.entry.id);
      // learning steps: bring the card back later in this session if it is due again soon
      final dueIn = outcome.card.due.difference(DateTime.now().toUtc());
      if (dueIn < const Duration(minutes: 15) && item.requeues < 3) {
        item.requeues++;
        final insertAt = math.min(_queue.length, _pos + 4);
        _queue.insert(insertAt, _QueueItem(item.entry)..requeues = item.requeues);
      }
      _pos++;
      _flipped = false;
      if (_pos < _queue.length) await _prepareCurrent();
      if (mounted) await afterLearningActivity(ref, context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không lưu được kết quả: $e')));
    }
    if (mounted) setState(() => _busy = false);
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
    if (_queue.isEmpty) return _emptyState(context);
    if (_pos >= _queue.length) return _summary(context);
    final item = _queue[_pos];
    final total = math.max(_initialCount, _queue.length);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(child: RoundedProgress(value: _pos / total, height: 8)),
              const SizedBox(width: 12),
              Text('${_pos + 1}/$total', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween(
                  begin: const Offset(0.25, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: KeyedSubtree(
                key: ValueKey('card-$_pos-${item.entry.id}'),
                child: GestureDetector(
                  onTap: () => setState(() => _flipped = !_flipped),
                  child: FlipCard(flipped: _flipped, front: _front(context, item.entry), back: _back(context, item.entry)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: _flipped
              ? Row(
                  children: [
                    for (final g in Grade.values) ...[if (g != Grade.again) const SizedBox(width: 8), Expanded(child: _gradeButton(g))],
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => setState(() => _flipped = true),
                    icon: const Icon(Icons.flip_rounded),
                    label: const Text('Hiện đáp án'),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _gradeButton(Grade g) {
    final color = switch (g) {
      Grade.again => AppColors.danger,
      Grade.hard => AppColors.amber,
      Grade.good => AppColors.indigo,
      Grade.easy => AppColors.success,
    };
    final interval = _preview[g];
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.14),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 10),
        minimumSize: const Size(0, 58),
      ),
      onPressed: _busy ? null : () => _rate(g),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(g.labelVi, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (interval != null) Text(formatInterval(interval), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
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
    final reviewed = _tally.values.fold<int>(0, (a, b) => a + b);
    final good = reviewed - _tally[Grade.again]!;
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
              ? 'Bạn vừa học ${_learnedNew.length} từ mới với $reviewed lượt ôn.'
              : 'Bạn đã ôn $reviewed lượt, nhớ được $good lượt.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            for (final g in Grade.values)
              Expanded(
                child: Column(
                  children: [
                    Text('${_tally[g]}', style: Theme.of(context).textTheme.headlineSmall),
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
