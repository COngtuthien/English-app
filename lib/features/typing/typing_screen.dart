import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/learning_repository.dart';
import '../../domain/quiz/answer_checker.dart';
import '../../providers.dart';

enum TypingMode { spelling, recall, sentence }

class _TypingItem {
  final EntrySummary entry;
  final String prompt;
  final String? sub;
  final List<String> accepted;
  final String? sentenceVi;
  _TypingItem(this.entry, this.prompt, this.sub, this.accepted, {this.sentenceVi});
}

class TypingScreen extends ConsumerStatefulWidget {
  const TypingScreen({super.key});
  @override
  ConsumerState<TypingScreen> createState() => _TypingScreenState();
}

class _TypingScreenState extends ConsumerState<TypingScreen> {
  TypingMode? _mode;
  List<_TypingItem> _items = [];
  int _i = 0;
  AnswerCheck? _check;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final List<QuizAnswerRecord> _answers = [];
  DateTime _started = DateTime.now();
  bool _loading = false;
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start(TypingMode m) async {
    setState(() {
      _mode = m;
      _loading = true;
      _done = false;
      _i = 0;
      _answers.clear();
      _check = null;
      _ctrl.clear();
    });
    final repo = ref.read(vocabRepoProvider);
    final learned = await ref.read(learningRepoProvider).learnedIds();
    final pool = (learned..shuffle()).take(60).toSet();
    final items = <_TypingItem>[];
    if (m == TypingMode.sentence) {
      var rows = await repo.clozeCandidates(10, fromIds: pool);
      if (rows.length < 10) rows = [...rows, ...await repo.clozeCandidates(10 - rows.length)];
      for (final r in rows) {
        final e = await repo.summary(r['entry_id'] as int);
        final form = r['highlight'] as String;
        final blanked = blankOut(r['text_en'] as String, form);
        if (e == null || blanked == null) continue;
        items.add(
          _TypingItem(e, blanked, 'Gợi ý: ${e.meaningVi} • ${form.length} chữ cái', {form}.toList(), sentenceVi: r['text_vi'] as String?),
        );
      }
    } else {
      final entries = pool.length >= 10
          ? await repo.summaries(pool.take(10).toList())
          : await repo.randomEntries(10, wordsOnly: true, minDifficulty: 2);
      for (final e in entries) {
        if (m == TypingMode.spelling) {
          items.add(_TypingItem(e, e.meaningVi, '${e.posVi} • ${e.definition}', e.spellings));
        } else {
          items.add(_TypingItem(e, e.meaningVi, e.posVi, e.spellings));
        }
      }
    }
    if (!mounted) return;
    _started = DateTime.now();
    setState(() {
      _items = items;
      _loading = false;
    });
    _focus.requestFocus();
  }

  void _submit() {
    if (_check != null || _ctrl.text.trim().isEmpty) return;
    final it = _items[_i];
    final c = checkTyped(_ctrl.text, it.accepted);
    setState(() => _check = c);
    _answers.add(
      QuizAnswerRecord(
        entryId: it.entry.id,
        questionType: 'typing_${_mode!.name}',
        prompt: it.prompt,
        userAnswer: _ctrl.text.trim(),
        correctAnswer: it.accepted.first,
        correct: c.correct,
      ),
    );
  }

  Future<void> _next() async {
    if (_i + 1 < _items.length) {
      setState(() {
        _i++;
        _check = null;
        _ctrl.clear();
      });
      _focus.requestFocus();
      return;
    }
    await ref.read(learningRepoProvider).recordQuizSession(quizType: 'typing', startedAt: _started, answers: _answers);
    if (!mounted) return;
    await afterLearningActivity(ref, context);
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Luyện gõ từ')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_mode == null) {
      final modes = [
        (TypingMode.spelling, 'Chính tả', 'Xem nghĩa + định nghĩa, gõ đúng từ tiếng Anh', Icons.spellcheck_rounded),
        (TypingMode.recall, 'Nhớ từ Việt → Anh', 'Chỉ xem nghĩa tiếng Việt, tự nhớ lại từ', Icons.psychology_rounded),
        (TypingMode.sentence, 'Hoàn thành câu', 'Gõ từ còn thiếu trong câu ví dụ (đúng dạng)', Icons.short_text_rounded),
      ];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final m in modes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.amber.withValues(alpha: 0.15),
                    child: Icon(m.$4, color: AppColors.amber),
                  ),
                  title: Text(m.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(m.$3),
                  onTap: () => _start(m.$1),
                ),
              ),
            ),
          Text(
            'Không phân biệt chữ hoa/thường. Chấp nhận cả cách viết Anh – Mỹ (colour/color) và gạch nối/khoảng trắng. '
            'Lỗi chính tả nhỏ sẽ được chỉ ra nhưng không tính là đúng.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4),
          ),
        ],
      );
    }
    if (_loading) return const LoadingView();
    if (_items.isEmpty) {
      return const EmptyState(icon: Icons.inbox_rounded, title: 'Chưa có dữ liệu', message: 'Không tìm được câu hỏi phù hợp.');
    }
    if (_done) {
      final correct = _answers.where((a) => a.correct).length;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Kết quả: $correct/${_answers.length}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          for (final a in _answers)
            Card(
              child: ListTile(
                leading: Icon(
                  a.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: a.correct ? AppColors.success : AppColors.danger,
                ),
                title: Text(a.correctAnswer, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(a.correct ? a.prompt : 'Bạn gõ: ${a.userAnswer}'),
                onTap: a.entryId == null ? null : () => context.push('/word/${a.entryId}'),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _start(_mode!), child: const Text('Luyện tiếp')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => setState(() => _mode = null), child: const Text('Chọn chế độ khác')),
        ],
      );
    }
    final it = _items[_i];
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RoundedProgress(value: _i / _items.length),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(it.prompt, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.4)),
                if (it.sub != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    it.sub!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                  ),
                ],
                if (_mode == TypingMode.spelling) SpeakButton(it.entry.headword),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _ctrl,
          focusNode: _focus,
          enabled: _check == null,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _check == null ? _submit() : _next(),
          decoration: const InputDecoration(hintText: 'Gõ từ tiếng Anh…', prefixIcon: Icon(Icons.keyboard_rounded)),
        ),
        const SizedBox(height: 12),
        if (_check != null) _feedback(it, _check!),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _check == null ? _submit : _next,
          child: Text(_check == null ? 'Kiểm tra' : (_i + 1 < _items.length ? 'Tiếp theo' : 'Hoàn thành')),
        ),
        if (_check == null)
          TextButton(
            onPressed: () {
              _ctrl.text = '?';
              _submit();
            },
            child: const Text('Không biết – xem đáp án'),
          ),
      ],
    );
  }

  Widget _feedback(_TypingItem it, AnswerCheck c) {
    final color = c.correct ? AppColors.success : (c.nearMiss ? AppColors.amber : AppColors.danger);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.correct ? 'Chính xác! ✅' : (c.nearMiss ? 'Gần đúng – kiểm tra chính tả' : 'Chưa đúng'),
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          if (!c.correct) ...[const SizedBox(height: 6), _DiffLine(typed: _ctrl.text.trim(), expected: c.expected)],
          const SizedBox(height: 6),
          Text('${it.entry.headword} (${it.entry.posVi}) – ${it.entry.meaningVi}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(it.entry.definition, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (it.sentenceVi != null) Text('Dịch: ${it.sentenceVi}', style: const TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

/// Shows expected answer with letters that differ from the typed answer highlighted.
class _DiffLine extends StatelessWidget {
  final String typed;
  final String expected;
  const _DiffLine({required this.typed, required this.expected});
  @override
  Widget build(BuildContext context) {
    final t = typed.toLowerCase();
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Đáp án: '),
          for (var i = 0; i < expected.length; i++)
            TextSpan(
              text: expected[i],
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: (i < t.length && t[i] == expected[i].toLowerCase()) ? AppColors.success : AppColors.danger,
              ),
            ),
          TextSpan(text: '   (bạn gõ: $typed)'),
        ],
      ),
    );
  }
}
