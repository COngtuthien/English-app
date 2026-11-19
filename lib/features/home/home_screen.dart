import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/common.dart';
import '../../data/models/models.dart';
import '../../data/repositories/stats_repository.dart';
import '../../providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Chào buổi sáng';
    if (h < 14) return 'Chào buổi trưa';
    if (h < 18) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final dash = ref.watch(dashboardProvider);
    final name = settings.userName.isEmpty ? 'bạn' : settings.userName;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardProvider),
          child: dash.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(e, onRetry: () => ref.invalidate(dashboardProvider)),
            data: (d) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_greeting()}, $name 👋', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 2),
                          Text(
                            'Mục tiêu IELTS ${settings.targetBand} • Trình độ ${settings.currentLevel}',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    _StreakChip(streak: d.streak),
                  ],
                ),
                const SizedBox(height: 16),
                _DailyCard(stats: d, dailyGoal: settings.dailyNewWords),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.auto_stories_rounded,
                        value: '${d.totalStudied}',
                        label: 'Từ đã học',
                        color: AppColors.indigo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        icon: Icons.workspace_premium_rounded,
                        value: '${d.mastered}',
                        label: 'Thành thạo',
                        color: AppColors.teal,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        icon: Icons.psychology_alt_rounded,
                        value: d.retention == null ? '–' : '${(d.retention! * 100).round()}%',
                        label: 'Khả năng nhớ',
                        color: AppColors.amber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _WeekCard(week: d.week),
                const SizedBox(height: 8),
                SectionHeader('Chủ đề gợi ý', actionLabel: 'Tất cả', onAction: () => context.go('/topics')),
                _RecommendedTopics(preferred: settings.preferredTopics),
                const SizedBox(height: 8),
                SectionHeader('Luyện tập nhanh', actionLabel: 'Xem thêm', onAction: () => context.go('/practice')),
                _QuickPractice(),
                const SizedBox(height: 16),
                _MilestoneCard(total: d.totalStudied, entries: d.totalEntries),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int streak;
  const _StreakChip({required this.streak});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/calendar'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: AppColors.amber),
            const SizedBox(width: 4),
            Text(
              '$streak',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFFB45309)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  final DashboardStats stats;
  final int dailyGoal;
  const _DailyCard({required this.stats, required this.dailyGoal});

  @override
  Widget build(BuildContext context) {
    final progress = dailyGoal == 0 ? 0.0 : stats.newToday / dailyGoal;
    final remaining = (dailyGoal - stats.newToday).clamp(0, dailyGoal);
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: softShadow(context, opacity: 0.25),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Mục tiêu hôm nay',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              Text(
                '${stats.newToday}/$dailyGoal từ mới',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RoundedProgress(value: progress, height: 10, color: Colors.white, background: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(height: 10),
          Text(
            progress >= 1
                ? '🎉 Bạn đã hoàn thành mục tiêu từ mới hôm nay! Ôn tập thêm để ghi nhớ lâu hơn.'
                : 'Còn $remaining từ mới • ${stats.dueNow} từ cần ôn • đã ôn ${stats.reviewsToday} lượt hôm nay',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.92), height: 1.35),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.indigoDeep),
                  onPressed: () => context.push('/learn'),
                  icon: const Icon(Icons.school_rounded),
                  label: const Text('Học từ mới'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  onPressed: () => context.push('/review'),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text('Ôn tập (${stats.dueNow})'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  final List<DayActivity> week;
  const _WeekCard({required this.week});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxY = week.fold<int>(0, (m, d) => d.newWords + d.reviews > m ? d.newWords + d.reviews : m).toDouble();
    final total = week.fold<int>(0, (s, d) => s + d.newWords + d.reviews);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Hoạt động 7 ngày', style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text('$total lượt học', style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 4),
            Row(children: [_legend(AppColors.indigo, 'Từ mới'), const SizedBox(width: 12), _legend(AppColors.teal, 'Ôn tập')]),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: BarChart(
                BarChartData(
                  maxY: maxY < 5 ? 5 : maxY * 1.15,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= week.length) return const SizedBox.shrink();
                          final d = Dates.parseDay(week[i].day);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(Dates.weekdayShortVi(d), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < week.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: (week[i].newWords + week[i].reviews).toDouble(),
                            width: 18,
                            borderRadius: BorderRadius.circular(6),
                            rodStackItems: [
                              BarChartRodStackItem(0, week[i].newWords.toDouble(), AppColors.indigo),
                              BarChartRodStackItem(
                                week[i].newWords.toDouble(),
                                (week[i].newWords + week[i].reviews).toDouble(),
                                AppColors.teal,
                              ),
                            ],
                            color: Colors.transparent,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color c, String t) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 4),
      Text(t, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _RecommendedTopics extends ConsumerWidget {
  final List<String> preferred;
  const _RecommendedTopics({required this.preferred});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(topicsProvider);
    return SizedBox(
      height: 132,
      child: topics.when(
        loading: () => const LoadingView(),
        error: (e, _) => Text('$e'),
        data: (all) {
          final ielts = all.where((t) => t.category == 'ielts').toList();
          final pref = ielts.where((t) => preferred.contains(t.code)).toList();
          final rest = ielts.where((t) => !preferred.contains(t.code) && t.progress < 1).toList()
            ..sort((a, b) => b.wordCount.compareTo(a.wordCount));
          final list = [...pref, ...rest].take(10).toList();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (c, i) {
              final t = list[i];
              return SizedBox(
                width: 150,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.push('/topic/${t.code}'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(AppIcons.of(t.icon), color: AppColors.indigo),
                          const Spacer(),
                          Text(
                            t.nameVi,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          RoundedProgress(value: t.progress, height: 6),
                          const SizedBox(height: 4),
                          Text(
                            '${t.learnedCount}/${t.wordCount} từ',
                            style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _QuickPractice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.quiz_rounded, 'Quiz', '/quiz', AppColors.indigo),
      (Icons.extension_rounded, 'Ghép từ', '/match', AppColors.teal),
      (Icons.keyboard_rounded, 'Gõ từ', '/typing', AppColors.amber),
      (Icons.headphones_rounded, 'Nghe', '/listening', const Color(0xFFEC4899)),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push(items[i].$3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    children: [
                      Icon(items[i].$1, color: items[i].$4, size: 28),
                      const SizedBox(height: 6),
                      Text(items[i].$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  final int total;
  final int entries;
  const _MilestoneCard({required this.total, required this.entries});
  @override
  Widget build(BuildContext context) {
    const steps = [10, 100, 500, 1000, 2000, 3000, 5000, 7500, 10000];
    final next = steps.firstWhere((s) => s > total, orElse: () => entries);
    final prev = steps.lastWhere((s) => s <= total, orElse: () => 0);
    final p = next == prev ? 1.0 : (total - prev) / (next - prev);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.push('/achievements'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.emoji_events_rounded, color: AppColors.amber),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cột mốc tiếp theo: $next từ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    RoundedProgress(value: p, color: AppColors.amber),
                    const SizedBox(height: 4),
                    Text(
                      'Còn ${next - total} từ nữa • Kho từ: $entries mục',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
