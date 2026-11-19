import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../providers.dart';

final _packsProvider = FutureProvider.autoDispose<List<SpeakingPack>>((ref) => ref.watch(vocabRepoProvider).speakingPacks());
final _packProvider = FutureProvider.autoDispose.family<SpeakingPack?, String>(
  (ref, code) => ref.watch(vocabRepoProvider).speakingPack(code),
);
final _promptsProvider = FutureProvider.autoDispose<List<String>>((ref) => ref.watch(vocabRepoProvider).selfPracticePrompts());

class SpeakingListScreen extends ConsumerWidget {
  const SpeakingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(_packsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Từ vựng IELTS Speaking')),
      body: AsyncView<List<SpeakingPack>>(
        packs,
        builder: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Card(
              color: const Color(0xFF0EA5E9).withValues(alpha: 0.07),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Mỗi gói gồm câu hỏi mẫu, từ vựng – cụm diễn đạt tự nhiên, câu trả lời tham khảo và gợi ý luyện nói. '
                  'Ứng dụng không chấm điểm phát âm.',
                  style: TextStyle(height: 1.4),
                ),
              ),
            ),
            for (final part in [1, 2, 3]) ...[
              SectionHeader(switch (part) {
                1 => 'Part 1 – Giới thiệu & chủ đề quen thuộc',
                2 => 'Part 2 – Cue card (nói 1–2 phút)',
                _ => 'Part 3 – Thảo luận chuyên sâu',
              }),
              for (final p in list.where((p) => p.part == part))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                        child: Text(
                          'P${p.part}',
                          style: const TextStyle(color: Color(0xFF0369A1), fontWeight: FontWeight.w800),
                        ),
                      ),
                      title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${p.titleVi} • ${p.vocab.length} từ/cụm'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/speaking/${p.code}'),
                    ),
                  ),
                ),
            ],
            SectionHeader('Từ vựng Speaking (${'kho tổng hợp'})', actionLabel: 'Mở', onAction: () => context.push('/topic/speaking')),
          ],
        ),
      ),
    );
  }
}

class SpeakingPackScreen extends ConsumerStatefulWidget {
  final String code;
  const SpeakingPackScreen({super.key, required this.code});
  @override
  ConsumerState<SpeakingPackScreen> createState() => _SpeakingPackScreenState();
}

class _SpeakingPackScreenState extends ConsumerState<SpeakingPackScreen> {
  bool _showSample = false;
  int _promptIdx = Random().nextInt(8);

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(_packProvider(widget.code));
    final prompts = ref.watch(_promptsProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Gói Speaking')),
      body: AsyncView<SpeakingPack?>(
        pack,
        builder: (p) {
          if (p == null) return const EmptyState(icon: Icons.search_off, title: 'Không tìm thấy', message: '');
          final cs = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IELTS Speaking Part ${p.part}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 4),
                    Text(
                      p.title,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    Text(p.titleVi, style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              SectionHeader(p.part == 2 ? 'Cue card – bạn nên nói về' : 'Câu hỏi luyện tập'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      for (final q in p.questions)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            p.part == 2 ? Icons.check_box_outline_blank_rounded : Icons.help_outline_rounded,
                            color: cs.primary,
                          ),
                          title: Text(q, style: const TextStyle(fontSize: 15)),
                          trailing: SpeakButton(q, size: 20),
                        ),
                    ],
                  ),
                ),
              ),
              const SectionHeader('Từ vựng & cụm diễn đạt'),
              for (final v in p.vocab) _VocabRow(v: v),
              if (p.tipsVi != null) ...[
                const SectionHeader('Mẹo'),
                Card(
                  color: AppColors.amber.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(p.tipsVi!, style: const TextStyle(height: 1.45)),
                  ),
                ),
              ],
              if (p.sampleAnswer != null) ...[
                SectionHeader(
                  'Câu trả lời mẫu',
                  actionLabel: _showSample ? 'Ẩn' : 'Hiện',
                  onAction: () => setState(() => _showSample = !_showSample),
                ),
                if (_showSample)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.sampleAnswer!, style: const TextStyle(height: 1.55, fontSize: 15)),
                          Align(alignment: Alignment.centerRight, child: SpeakButton(p.sampleAnswer!)),
                        ],
                      ),
                    ),
                  )
                else
                  Text('Hãy tự trả lời trước, sau đó mở câu trả lời mẫu để so sánh.', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
              if (prompts.isNotEmpty) ...[
                const SectionHeader('Tự luyện nói'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prompts[_promptIdx % prompts.length], style: const TextStyle(height: 1.45, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => setState(() => _promptIdx++),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Gợi ý khác'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VocabRow extends ConsumerWidget {
  final SpeakingVocab v;
  const _VocabRow({required this.v});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = v.entryId;
    final fav = id == null ? false : (ref.watch(isFavoriteProvider(id)).valueOrNull ?? false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        child: ListTile(
          title: Text(v.text, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: v.meaningVi == null ? null : Text(v.meaningVi!),
          onTap: id == null ? null : () => context.push('/word/$id'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpeakButton(v.text, size: 20),
              if (id != null)
                IconButton(
                  tooltip: 'Lưu cụm yêu thích',
                  icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? Colors.pinkAccent : null),
                  onPressed: () async {
                    await ref.read(learningRepoProvider).toggleFavorite(id);
                    ref.read(dataVersionProvider.notifier).state++;
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
