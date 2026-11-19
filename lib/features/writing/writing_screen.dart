import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/learning_repository.dart';
import '../../providers.dart';

const writingCategories = {
  'academic_word': ('Chọn từ học thuật', 'Academic word choice', Icons.school_rounded),
  'formal': ('Từ vựng trang trọng', 'Formal vocabulary', Icons.workspace_premium_rounded),
  'collocation': ('Kết hợp từ', 'Collocation selection', Icons.join_inner_rounded),
  'completion': ('Hoàn thành câu', 'Sentence completion', Icons.short_text_rounded),
  'paraphrase': ('Nhận diện paraphrase', 'Paraphrase recognition', Icons.swap_horiz_rounded),
  'task1_trend': ('Task 1 – Mô tả xu hướng', 'Trend descriptions', Icons.show_chart_rounded),
  'task2_argument': ('Task 2 – Lập luận', 'Argument vocabulary', Icons.forum_rounded),
};

class WritingScreen extends ConsumerStatefulWidget {
  const WritingScreen({super.key});
  @override
  ConsumerState<WritingScreen> createState() => _WritingScreenState();
}

class _WritingScreenState extends ConsumerState<WritingScreen> {
  Map<String, int>? _counts;
  String? _category; // null = menu, 'mixed' = all
  List<WritingExercise> _items = [];
  List<List<String>> _shuffled = [];
  List<int> _answerIdx = [];
  int _i = 0;
  int? _chosen;
  final List<QuizAnswerRecord> _answers = [];
  DateTime _started = DateTime.now();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    ref.read(vocabRepoProvider).writingCategoryCounts().then((c) => mounted ? setState(() => _counts = c) : null);
  }

  Future<void> _start(String cat) async {
    final repo = ref.read(vocabRepoProvider);
    final all = await repo.writingExercises(category: cat == 'mixed' ? null : cat);
    all.shuffle();
    final take = all.take(10).toList();
    final rng = Random();
    _shuffled = [];
    _answerIdx = [];
    for (final ex in take) {
      final correct = ex.options[ex.answerIndex];
      // keep "both A and B"-style options in place; shuffle the others
      final keepOrder = ex.options.any((o) => o.toLowerCase().contains('both'));
      final opts = keepOrder ? [...ex.options] : ([...ex.options]..shuffle(rng));
      _shuffled.add(opts);
      _answerIdx.add(opts.indexOf(correct));
    }
    if (!mounted) return;
    setState(() {
      _category = cat;
      _items = take;
      _i = 0;
      _chosen = null;
      _answers.clear();
      _done = false;
      _started = DateTime.now();
    });
  }

  void _choose(int k) {
    if (_chosen != null) return;
    final ex = _items[_i];
    setState(() => _chosen = k);
    _answers.add(
      QuizAnswerRecord(
        entryId: null,
        questionType: 'writing_${ex.category}',
        prompt: ex.prompt,
        userAnswer: _shuffled[_i][k],
        correctAnswer: ex.options[ex.answerIndex],
        correct: k == _answerIdx[_i],
      ),
    );
  }

  Future<void> _next() async {
    if (_i + 1 < _items.length) {
      setState(() {
        _i++;
        _chosen = null;
      });
      return;
    }
    await ref.read(learningRepoProvider).recordQuizSession(quizType: 'writing', startedAt: _started, answers: _answers);
    if (!mounted) return;
    await afterLearningActivity(ref, context);
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _category == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _category = null);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_category == null ? 'Từ vựng IELTS Writing' : (writingCategories[_category]?.$1 ?? 'Tổng hợp'))),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_category == null) {
      final cs = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            color: cs.primary.withValues(alpha: 0.06),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Bài tập trắc nghiệm có đáp án xác định, chấm tự động ngoại tuyến. '
                'Ứng dụng không chấm điểm bài luận tự do.',
                style: TextStyle(height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shuffle_rounded, color: AppColors.indigo),
              title: const Text('Bài tổng hợp (10 câu)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${_counts?.values.fold<int>(0, (a, b) => a + b) ?? '…'} câu trong ngân hàng'),
              onTap: () => _start('mixed'),
            ),
          ),
          const SizedBox(height: 8),
          for (final e in writingCategories.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                    child: Icon(e.value.$3, color: const Color(0xFF8B5CF6)),
                  ),
                  title: Text(e.value.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${e.value.$2} • ${_counts?[e.key] ?? 0} câu'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _start(e.key),
                ),
              ),
            ),
          const SectionHeader('Kho cụm từ Writing'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => context.push('/topic/writing_task1'), child: const Text('Task 1')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(onPressed: () => context.push('/topic/writing_task2'), child: const Text('Task 2')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(onPressed: () => context.push('/topic/academic'), child: const Text('Học thuật')),
              ),
            ],
          ),
        ],
      );
    }
    if (_items.isEmpty) return const EmptyState(icon: Icons.inbox, title: 'Chưa có bài tập', message: 'Danh mục này trống.');
    if (_done) {
      final correct = _answers.where((a) => a.correct).length;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Kết quả: $correct/${_answers.length}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          for (var k = 0; k < _answers.length; k++)
            if (!_answers[k].correct)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_items[k].prompt, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'Đáp án: ${_answers[k].correctAnswer}',
                        style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
                      ),
                      Text(_items[k].explanationVi),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _start(_category!), child: const Text('Làm bài khác')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => setState(() => _category = null), child: const Text('Chọn dạng bài khác')),
        ],
      );
    }
    final ex = _items[_i];
    final opts = _shuffled[_i];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: RoundedProgress(value: _i / _items.length)),
            const SizedBox(width: 10),
            Text('${_i + 1}/${_items.length}'),
          ],
        ),
        const SizedBox(height: 14),
        Pill(writingCategories[ex.category]?.$1 ?? ex.category, color: const Color(0xFF8B5CF6)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(ex.prompt, style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.45)),
          ),
        ),
        const SizedBox(height: 12),
        for (var k = 0; k < opts.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(14),
                backgroundColor: _chosen == null
                    ? null
                    : k == _answerIdx[_i]
                    ? AppColors.success.withValues(alpha: 0.12)
                    : k == _chosen
                    ? AppColors.danger.withValues(alpha: 0.12)
                    : null,
                side: BorderSide(
                  color: _chosen == null
                      ? Theme.of(context).colorScheme.outlineVariant
                      : k == _answerIdx[_i]
                      ? AppColors.success
                      : k == _chosen
                      ? AppColors.danger
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              onPressed: () => _choose(k),
              child: Text(opts[k], style: TextStyle(color: Theme.of(context).colorScheme.onSurface, height: 1.3)),
            ),
          ),
        if (_chosen != null) ...[
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (_chosen == _answerIdx[_i] ? AppColors.success : AppColors.danger).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _chosen == _answerIdx[_i] ? 'Chính xác!' : 'Đáp án đúng: ${opts[_answerIdx[_i]]}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _chosen == _answerIdx[_i] ? AppColors.success : AppColors.danger),
                ),
                const SizedBox(height: 6),
                Text(ex.explanationVi, style: const TextStyle(height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _next, child: Text(_i + 1 < _items.length ? 'Câu tiếp theo' : 'Xem kết quả')),
        ],
      ],
    );
  }
}
