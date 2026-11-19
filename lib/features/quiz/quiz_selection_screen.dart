import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/common.dart';
import '../../domain/quiz/quiz_engine.dart';
import '../../providers.dart';

class QuizSelectionScreen extends ConsumerStatefulWidget {
  const QuizSelectionScreen({super.key});
  @override
  ConsumerState<QuizSelectionScreen> createState() => _QuizSelectionScreenState();
}

class _QuizSelectionScreenState extends ConsumerState<QuizSelectionScreen> {
  final Set<QuestionType> _types = {QuestionType.enToVi, QuestionType.viToEn, QuestionType.definition};
  int _count = 10;
  int? _topicId;
  bool _mixed = false;

  @override
  Widget build(BuildContext context) {
    final topics = ref.watch(topicsProvider).valueOrNull ?? const [];
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz từ vựng')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Bài kiểm tra tổng hợp', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Trộn ngẫu nhiên cả 9 dạng câu hỏi'),
              value: _mixed,
              onChanged: (v) => setState(() => _mixed = v),
            ),
          ),
          if (!_mixed) ...[
            const SectionHeader('Dạng câu hỏi'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in QuestionType.values)
                  FilterChip(
                    label: Text(t.labelVi),
                    selected: _types.contains(t),
                    onSelected: (v) => setState(() {
                      v ? _types.add(t) : _types.remove(t);
                      if (_types.isEmpty) _types.add(QuestionType.enToVi);
                    }),
                  ),
              ],
            ),
          ],
          const SectionHeader('Số câu hỏi'),
          Wrap(
            spacing: 8,
            children: [
              for (final n in [5, 10, 20, 30])
                ChoiceChip(label: Text('$n câu'), selected: _count == n, onSelected: (_) => setState(() => _count = n)),
              ActionChip(
                avatar: const Icon(Icons.edit_rounded, size: 16),
                label: Text(![5, 10, 20, 30].contains(_count) ? 'Tùy chỉnh: $_count' : 'Tùy chỉnh'),
                onPressed: () async {
                  final ctrl = TextEditingController(text: '$_count');
                  final n = await showDialog<int>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Số câu hỏi (1–100)'),
                      content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)), child: const Text('OK')),
                      ],
                    ),
                  );
                  if (n != null && n >= 1 && n <= 100) setState(() => _count = n);
                },
              ),
            ],
          ),
          const SectionHeader('Phạm vi từ'),
          DropdownButtonFormField<int?>(
            initialValue: _topicId,
            isExpanded: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.category_rounded)),
            items: [
              const DropdownMenuItem(value: null, child: Text('Ưu tiên từ đã học + toàn bộ kho từ')),
              for (final t in topics)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(t.nameVi, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _topicId = v),
          ),
          const SizedBox(height: 8),
          Text(
            _topicId != null
                ? 'Khi chọn chủ đề, quiz dùng các dạng câu hỏi nghĩa và định nghĩa trong chủ đề đó.'
                : 'Quiz ưu tiên những từ bạn đã học (khoảng 75%) để củng cố trí nhớ.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Bắt đầu'),
            onPressed: () {
              final types = _topicId != null
                  ? (_types.intersection({QuestionType.enToVi, QuestionType.viToEn, QuestionType.definition, QuestionType.spelling}).isEmpty
                        ? {QuestionType.enToVi, QuestionType.viToEn}
                        : _types.intersection({QuestionType.enToVi, QuestionType.viToEn, QuestionType.definition, QuestionType.spelling}))
                  : (_mixed ? QuestionType.values.toSet() : _types);
              context.push(
                '/quiz/play',
                extra: QuizConfig(types: types, count: _count, topicId: _topicId, preferLearned: _topicId == null),
              );
            },
          ),
        ],
      ),
    );
  }
}
