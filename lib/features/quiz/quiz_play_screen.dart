import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/learning_repository.dart';
import '../../domain/quiz/answer_checker.dart';
import '../../domain/quiz/quiz_engine.dart';
import '../../providers.dart';

class QuizResult {
  final List<QuizQuestion> questions;
  final List<QuizAnswerRecord> answers;
  final QuizConfig config;
  final Duration elapsed;
  const QuizResult(this.questions, this.answers, this.config, this.elapsed);
  int get correct => answers.where((a) => a.correct).length;
}

class QuizPlayScreen extends ConsumerStatefulWidget {
  final QuizConfig config;
  const QuizPlayScreen({super.key, required this.config});
  @override
  ConsumerState<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends ConsumerState<QuizPlayScreen> {
  List<QuizQuestion>? _qs;
  Object? _error;
  int _i = 0;
  int? _selected;
  AnswerCheck? _typedCheck;
  final _typed = TextEditingController();
  final List<QuizAnswerRecord> _answers = [];
  final _started = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    try {
      final learned = await ref.read(learningRepoProvider).learnedIds();
      final qs = await ref.read(quizEngineProvider).build(widget.config, learnedIds: learned);
      if (mounted) setState(() => _qs = qs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool get _answered => _selected != null || _typedCheck != null;

  void _choose(int idx) {
    if (_answered) return;
    final q = _qs![_i];
    setState(() => _selected = idx);
    _record(q, q.options[idx], idx == q.answerIndex);
  }

  void _submitTyped() {
    if (_answered || _typed.text.trim().isEmpty) return;
    final q = _qs![_i];
    final check = checkTyped(_typed.text, q.accepted);
    setState(() => _typedCheck = check);
    _record(q, _typed.text.trim(), check.correct);
  }

  void _record(QuizQuestion q, String answer, bool correct) {
    _answers.add(
      QuizAnswerRecord(
        entryId: q.entryId,
        questionType: q.type.name,
        prompt: q.prompt,
        userAnswer: answer,
        correctAnswer: q.correctAnswer,
        correct: correct,
      ),
    );
  }

  Future<void> _next() async {
    if (_i + 1 < _qs!.length) {
      setState(() {
        _i++;
        _selected = null;
        _typedCheck = null;
        _typed.clear();
      });
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    final type = widget.config.types.length > 1 ? 'mixed' : widget.config.types.first.name;
    await ref.read(learningRepoProvider).recordQuizSession(quizType: 'quiz:$type', startedAt: _started, answers: _answers);
    if (!mounted) return;
    await afterLearningActivity(ref, context);
    if (!mounted) return;
    context.pushReplacement('/quiz/result', extra: QuizResult(_qs!, _answers, widget.config, DateTime.now().difference(_started)));
  }

  Future<bool> _confirmExit() async {
    if (_answers.isEmpty || _i + 1 >= (_qs?.length ?? 0)) return true;
    return confirmDialog(
      context,
      title: 'Thoát bài quiz?',
      message: 'Kết quả bài làm dở sẽ không được lưu.',
      confirm: 'Thoát',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_qs == null ? 'Quiz' : 'Câu ${_i + 1}/${_qs!.length}')),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) return ErrorView(_error!, onRetry: _build);
    if (_qs == null) return const LoadingView(message: 'Đang tạo câu hỏi…');
    if (_qs!.isEmpty) {
      return const EmptyState(
        icon: Icons.quiz_outlined,
        title: 'Không tạo được câu hỏi',
        message: 'Hãy thử phạm vi từ hoặc dạng câu hỏi khác.',
      );
    }
    final q = _qs![_i];
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isWordPrompt = q.type == QuestionType.enToVi || q.type == QuestionType.synonym || q.type == QuestionType.antonym;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: RoundedProgress(value: (_i + (_answered ? 1 : 0)) / _qs!.length),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Pill(q.type.labelVi, icon: Icons.label_rounded),
              const SizedBox(height: 10),
              Text(q.type.instructionVi, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              q.prompt,
                              textAlign: TextAlign.center,
                              style: isWordPrompt
                                  ? tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)
                                  : tt.titleMedium?.copyWith(height: 1.45, fontWeight: FontWeight.w500),
                            ),
                          ),
                          if (isWordPrompt) SpeakButton(q.prompt),
                        ],
                      ),
                      if (q.subPrompt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          q.subPrompt!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (q.isTyped) ..._typedInput(q) else ..._options(q),
              if (_answered) ...[const SizedBox(height: 12), _feedback(q)],
            ],
          ),
        ),
        if (_answered)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _saving ? null : _next, child: Text(_i + 1 < _qs!.length ? 'Câu tiếp theo' : 'Xem kết quả')),
            ),
          ),
      ],
    );
  }

  List<Widget> _options(QuizQuestion q) {
    return [
      for (var k = 0; k < q.options.length; k++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _OptionTile(
            label: String.fromCharCode(65 + k),
            text: q.options[k],
            state: !_answered
                ? _OptState.idle
                : k == q.answerIndex
                ? _OptState.correct
                : k == _selected
                ? _OptState.wrong
                : _OptState.dim,
            onTap: () => _choose(k),
          ),
        ),
    ];
  }

  List<Widget> _typedInput(QuizQuestion q) {
    return [
      TextField(
        controller: _typed,
        enabled: !_answered,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submitTyped(),
        decoration: const InputDecoration(hintText: 'Nhập câu trả lời bằng tiếng Anh', prefixIcon: Icon(Icons.keyboard_rounded)),
      ),
      const SizedBox(height: 10),
      if (!_answered) FilledButton(onPressed: _submitTyped, child: const Text('Kiểm tra')),
    ];
  }

  Widget _feedback(QuizQuestion q) {
    final correct = _answers.last.correct;
    final color = correct ? AppColors.success : AppColors.danger;
    final near = _typedCheck?.nearMiss ?? false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  correct
                      ? 'Chính xác!'
                      : (near ? 'Gần đúng – sai chính tả. Đáp án: ${q.correctAnswer}' : 'Chưa đúng. Đáp án: ${q.correctAnswer}'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(q.explanation, style: const TextStyle(height: 1.4)),
          if (q.exampleVi != null) ...[
            const SizedBox(height: 6),
            Text(
              'Dịch câu: ${q.exampleVi}',
              style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (q.entryId != null) TextButton(onPressed: () => context.push('/word/${q.entryId}'), child: const Text('Xem chi tiết từ')),
        ],
      ),
    );
  }
}

enum _OptState { idle, correct, wrong, dim }

class _OptionTile extends StatelessWidget {
  final String label;
  final String text;
  final _OptState state;
  final VoidCallback onTap;
  const _OptionTile({required this.label, required this.text, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (border, bg, fg) = switch (state) {
      _OptState.correct => (AppColors.success, AppColors.success.withValues(alpha: 0.12), AppColors.success),
      _OptState.wrong => (AppColors.danger, AppColors.danger.withValues(alpha: 0.12), AppColors.danger),
      _OptState.dim => (cs.outlineVariant, Theme.of(context).cardTheme.color!, cs.onSurfaceVariant),
      _OptState.idle => (cs.outlineVariant, Theme.of(context).cardTheme.color!, cs.onSurface),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: state == _OptState.idle || state == _OptState.dim ? 1 : 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: state == _OptState.idle ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: border.withValues(alpha: 0.15),
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ),
              if (state == _OptState.correct) const Icon(Icons.check_rounded, color: AppColors.success),
              if (state == _OptState.wrong) const Icon(Icons.close_rounded, color: AppColors.danger),
            ],
          ),
        ),
      ),
    );
  }
}
