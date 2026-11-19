import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/widgets/common.dart';
import '../../data/repositories/stats_repository.dart';
import '../../providers.dart';

String quizTypeVi(String t) {
  if (t.startsWith('quiz:')) return 'Quiz (${t.substring(5) == 'mixed' ? 'tổng hợp' : t.substring(5)})';
  return switch (t) {
    'match' => 'Ghép từ',
    'typing' => 'Gõ từ',
    'listening' => 'Luyện nghe',
    'writing' => 'Writing',
    _ => t,
  };
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(fullStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Thống kê học tập')),
      body: AsyncView<FullStats>(
        stats,
        onRetry: () => ref.invalidate(fullStatsProvider),
        builder: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                StatTile(icon: Icons.auto_stories_rounded, value: '${s.totalStudied}', label: 'Từ đã học', color: AppColors.indigo),
                StatTile(
                  icon: Icons.workspace_premium_rounded,
                  value: '${s.mastered}',
                  label: 'Thành thạo (ổn định ≥ 21 ngày)',
                  color: AppColors.success,
                ),
                StatTile(icon: Icons.pending_actions_rounded, value: '${s.dueNow}', label: 'Đang chờ ôn', color: AppColors.amber),
                StatTile(
                  icon: Icons.track_changes_rounded,
                  value: '${(s.accuracy * 100).round()}%',
                  label: 'Độ chính xác (${s.totalAnswers} lượt)',
                  color: AppColors.teal,
                ),
                StatTile(
                  icon: Icons.local_fire_department_rounded,
                  value: '${s.streak}',
                  label: 'Chuỗi hiện tại (dài nhất ${s.longestStreak})',
                  color: AppColors.danger,
                ),
                StatTile(
                  icon: Icons.timer_rounded,
                  value: '${s.studyMinutes}′',
                  label: 'Phút học (ghi nhận)',
                  color: const Color(0xFF8B5CF6),
                ),
              ],
            ),
            const SectionHeader('Hoạt động 30 ngày'),
            _MonthChart(s: s),
            const SectionHeader('Đánh giá khi ôn thẻ'),
            _RatingBar(counts: s.ratingCounts),
            SectionHeader('Mức độ thành thạo theo chủ đề', actionLabel: 'Lịch học', onAction: () => context.push('/calendar')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    for (final t in s.topics.where((t) => t.learned > 0).take(15))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(AppIcons.of(t.icon), size: 20, color: AppColors.indigo),
                            const SizedBox(width: 10),
                            SizedBox(width: 110, child: Text(t.nameVi, overflow: TextOverflow.ellipsis)),
                            Expanded(child: RoundedProgress(value: t.total == 0 ? 0 : t.learned / t.total)),
                            const SizedBox(width: 8),
                            Text('${t.learned}/${t.total}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    if (s.topics.every((t) => t.learned == 0)) const Text('Chưa có dữ liệu – hãy học vài từ trước.'),
                  ],
                ),
              ),
            ),
            const SectionHeader('Lịch sử bài luyện tập'),
            if (s.quizzes.isEmpty)
              const Card(child: ListTile(title: Text('Chưa có bài luyện tập nào')))
            else
              Card(
                child: Column(
                  children: [
                    for (final q in s.quizzes)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              (q.accuracy >= 0.8
                                      ? AppColors.success
                                      : q.accuracy >= 0.5
                                      ? AppColors.amber
                                      : AppColors.danger)
                                  .withValues(alpha: 0.15),
                          child: Text('${(q.accuracy * 100).round()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        title: Text(quizTypeVi(q.quizType)),
                        subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(q.startedAt.toLocal())),
                        trailing: Text('${q.correct}/${q.total}'),
                      ),
                  ],
                ),
              ),
            const SectionHeader('Lịch sử ôn tập gần đây'),
            if (s.recentReviews.isEmpty)
              const Card(child: ListTile(title: Text('Chưa có lượt ôn tập')))
            else
              Card(
                child: Column(
                  children: [
                    for (final r in s.recentReviews)
                      ListTile(
                        dense: true,
                        title: Text(r['headword'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r['reviewed_at'] as int).toLocal()),
                        ),
                        trailing: Text(
                          ['', 'Quên', 'Khó', 'Nhớ', 'Dễ'][r['rating'] as int],
                          style: TextStyle(
                            color: [
                              Colors.grey,
                              AppColors.danger,
                              AppColors.amber,
                              AppColors.indigo,
                              AppColors.success,
                            ][r['rating'] as int],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () => context.push('/word/${r['id']}'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthChart extends StatelessWidget {
  final FullStats s;
  const _MonthChart({required this.s});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spotsNew = <FlSpot>[];
    final spotsRev = <FlSpot>[];
    for (var i = 0; i < s.last30.length; i++) {
      spotsNew.add(FlSpot(i.toDouble(), s.last30[i].newWords.toDouble()));
      spotsRev.add(FlSpot(i.toDouble(), (s.last30[i].reviews + s.last30[i].answers).toDouble()));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 18, 8),
        child: SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (v, m) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 7,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= s.last30.length) return const SizedBox.shrink();
                      return Text(DateFormat('dd/MM').format(Dates.parseDay(s.last30[i].day)), style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spotsRev,
                  isCurved: true,
                  color: AppColors.teal,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: AppColors.teal.withValues(alpha: 0.12)),
                ),
                LineChartBarData(
                  spots: spotsNew,
                  isCurved: true,
                  color: AppColors.indigo,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingBar extends StatelessWidget {
  final Map<int, int> counts;
  const _RatingBar({required this.counts});
  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const Card(child: ListTile(title: Text('Chưa có lượt ôn thẻ')));
    const colors = {1: AppColors.danger, 2: AppColors.amber, 3: AppColors.indigo, 4: AppColors.success};
    const labels = {1: 'Quên', 2: 'Khó', 3: 'Nhớ', 4: 'Dễ'};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  for (final k in [1, 2, 3, 4])
                    if ((counts[k] ?? 0) > 0)
                      Expanded(
                        flex: counts[k]!,
                        child: Container(height: 14, color: colors[k]),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final k in [1, 2, 3, 4])
                  Column(
                    children: [
                      Text(
                        '${counts[k] ?? 0}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: colors[k]),
                      ),
                      Text(labels[k]!, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
