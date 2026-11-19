import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/achievement_repository.dart';
import '../../providers.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(achievementsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Thành tích')),
      body: AsyncView<Map<String, DateTime>>(
        unlocked,
        builder: (have) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: AppColors.amber, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${have.length}/${kAchievements.length} thành tích', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          RoundedProgress(value: have.length / kAchievements.length, color: AppColors.amber),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
              ),
              itemCount: kAchievements.length,
              itemBuilder: (c, i) {
                final a = kAchievements[i];
                final at = have[a.code];
                final on = at != null;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: on ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF97316)]) : null,
                            color: on ? null : Colors.grey.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(on ? AppIcons.of(a.icon) : Icons.lock_rounded, color: on ? Colors.white : Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          a.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w700, color: on ? null : Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(a.description, textAlign: TextAlign.center, maxLines: 3, style: const TextStyle(fontSize: 12)),
                        const Spacer(),
                        if (on)
                          Text(
                            DateFormat('dd/MM/yyyy').format(at.toLocal()),
                            style: const TextStyle(fontSize: 11, color: AppColors.success),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
