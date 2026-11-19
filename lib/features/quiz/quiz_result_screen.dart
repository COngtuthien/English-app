import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'quiz_play_screen.dart';

class QuizResultScreen extends StatelessWidget {
  final QuizResult result;
  const QuizResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final total = result.answers.length;
    final correct = result.correct;
    final pct = total == 0 ? 0 : (correct * 100 / total).round();
    final mistakes = <int>[
      for (var i = 0; i < result.answers.length; i++)
        if (!result.answers[i].correct) i,
    ];
    final (msg, color) = pct == 100
        ? ('Hoàn hảo! 🎉', AppColors.success)
        : pct >= 80
        ? ('Rất tốt!', AppColors.teal)
        : pct >= 50
        ? ('Khá ổn – hãy ôn lại các câu sai', AppColors.amber)
        : ('Cần luyện thêm', AppColors.danger);
    return Scaffold(
      appBar: AppBar(title: const Text('Kết quả quiz')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: total == 0 ? 0 : correct / total,
                            strokeWidth: 12,
                            color: color,
                            backgroundColor: color.withValues(alpha: 0.15),
                          ),
                        ),
                        Text('$pct%', style: Theme.of(context).textTheme.headlineMedium),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(msg, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
                  const SizedBox(height: 6),
                  Text('Đúng $correct/$total câu • ${result.elapsed.inMinutes} phút ${result.elapsed.inSeconds % 60} giây'),
                ],
              ),
            ),
          ),
          if (mistakes.isNotEmpty) ...[
            SectionHeader('Xem lại câu sai (${mistakes.length})'),
            for (final i in mistakes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: result.questions[i].entryId == null ? null : () => context.push('/word/${result.questions[i].entryId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.questions[i].type.labelVi,
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(result.questions[i].prompt, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text('Bạn trả lời: ${result.answers[i].userAnswer ?? '—'}', style: const TextStyle(color: AppColors.danger)),
                          Text(
                            'Đáp án đúng: ${result.answers[i].correctAnswer}',
                            style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            result.questions[i].explanation,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Làm lại bài mới'),
            onPressed: () => context.pushReplacement('/quiz/play', extra: result.config),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => context.pop(), child: const Text('Hoàn tất')),
        ],
      ),
    );
  }
}
