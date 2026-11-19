import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../providers.dart';

class TopicsScreen extends ConsumerWidget {
  const TopicsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(topicsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Chủ đề từ vựng')),
      body: AsyncView<List<TopicInfo>>(
        topics,
        onRetry: () => ref.invalidate(topicsProvider),
        builder: (all) {
          final skill = all.where((t) => t.category != 'ielts').toList();
          final ielts = all.where((t) => t.category == 'ielts').toList();
          return CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 0), child: SectionHeader('Kỹ năng & nhóm từ')),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: skill.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (c, i) => _SkillTile(topic: skill[i]),
                ),
              ),
              const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: SectionHeader('50 chủ đề IELTS')),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: ielts.length,
                  itemBuilder: (c, i) => _TopicCard(topic: ielts[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final TopicInfo topic;
  const _TopicCard({required this.topic});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/topic/${topic.code}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(AppIcons.of(topic.icon), color: AppColors.indigo, size: 22),
              ),
              const Spacer(),
              Text(
                topic.nameVi,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
              ),
              Text(
                topic.nameEn,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              RoundedProgress(value: topic.progress, height: 6),
              const SizedBox(height: 4),
              Text('${topic.learnedCount}/${topic.wordCount}', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  final TopicInfo topic;
  const _SkillTile({required this.topic});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AppColors.teal.withValues(alpha: 0.12),
          child: Icon(AppIcons.of(topic.icon), color: AppColors.tealDeep),
        ),
        title: Text(topic.nameVi, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: RoundedProgress(value: topic.progress, height: 6, color: AppColors.teal),
              ),
              const SizedBox(width: 10),
              Text('${topic.learnedCount}/${topic.wordCount}', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/topic/${topic.code}'),
      ),
    );
  }
}
